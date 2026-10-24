import AppKit
import EmulistCore
import Observation
import UniformTypeIdentifiers

enum CompareMode: String, CaseIterable, Identifiable {
    case off, split, before
    var id: String { rawValue }
}

enum PreviewQuality: String, CaseIterable, Identifiable {
    case full, half, quarter
    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// Processing scale for a source whose short side is `shortSide` (reduced previews keep ≥ ~540 lines).
    func scale(shortSide: Int) -> Double {
        switch self {
        case .full: 1
        case .half: max(0.5, min(1, 540 / Double(shortSide)))
        case .quarter: max(0.25, min(1, 540 / Double(shortSide)))
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// The single source of truth for the open clip, its grade and the app's modes.
@MainActor @Observable
final class Workspace {
    let playback = PlaybackController()
    let thumbnails = StockThumbnails()

    private(set) var media: MediaInfo?
    private(set) var settings = GradeSettings()
    var exportSettings = ExportSettings()
    private(set) var projectURL: URL?
    private(set) var hasUnsavedChanges = false
    /// A project whose footage could not be found; offered for relinking.
    private(set) var missingMedia: EmulistProject?
    var needsProfileConfirmation = false

    /// Every look in the library (built-in stocks and installed LUTs).
    private(set) var looks = LookLibrary.shared.all
    private(set) var isInstallingFujifilm = false

    var compare = CompareMode.off
    var splitPosition = 0.5
    var quality = PreviewQuality.full
    var alert: AppAlert?
    var isExportSheetPresented = false
    private(set) var isLoading = false

    @ObservationIgnored private var history = EditHistory<GradeSettings>()
    /// True during a drag or scroll of a control (the viewer previews on a coarser LUT meanwhile).
    @ObservationIgnored private(set) var isContinuousEdit = false
    /// Drag changes waiting for the next display frame (see `continuousEdit`).
    @ObservationIgnored private var pendingSettings: GradeSettings?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    private(set) var canUndo = false
    private(set) var canRedo = false

    init() {
        // Parse installed LUTs up front so thumbnails and first selections don't wait on disk.
        Task.detached(priority: .utility) { LookLibrary.shared.preload() }
    }

    var title: String {
        projectURL?.deletingPathExtension().lastPathComponent ?? media?.url.deletingPathExtension().lastPathComponent
            ?? "Emulist"
    }

    // MARK: Editing

    /// A discrete change (picker, toggle, preset, reset): one undo step.
    func edit(_ change: (inout GradeSettings) -> Void) {
        flushContinuousEdit()
        var next = settings
        change(&next)
        guard next != settings else { return }
        history.record(settings)
        apply(next)
    }

    /// Continuous changes (slider drags) collapse into a single undo step per gesture.
    func beginContinuousEdit() {
        guard !isContinuousEdit else { return }
        isContinuousEdit = true
        history.record(settings)
        updateUndoState()
    }

    /// Pointer events arrive at up to 120 Hz. Their changes wait for the viewer's next display frame
    /// (`flushContinuousEdit`), so SwiftUI updates at most once per frame and the viewer keeps up.
    func continuousEdit(_ change: (inout GradeSettings) -> Void) {
        var next = pendingSettings ?? settings
        change(&next)
        pendingSettings = next
    }

    func endContinuousEdit() {
        flushContinuousEdit()
        isContinuousEdit = false
    }

    /// Applies the latest drag change. Called by the viewer once per display frame, and before any
    /// other edit so changes never reorder.
    func flushContinuousEdit() {
        guard let next = pendingSettings else { return }
        pendingSettings = nil
        apply(next)
    }

    func undo() {
        flushContinuousEdit()
        if let previous = history.undo(from: settings) { apply(previous) }
    }

    func redo() {
        flushContinuousEdit()
        if let next = history.redo(from: settings) { apply(next) }
    }

    func select(_ stock: FilmStock) {
        edit { $0.select(stock) }
    }

    /// Returns the wheels and the adjustments under them to neutral, in one undo step.
    func resetPrimaries() {
        edit { settings in
            let neutral = GradeSettings()
            for kind in ColorWheel.Kind.allCases { settings[wheel: kind] = neutral[wheel: kind] }
            for spec in Controls.primaries + Controls.input { settings[keyPath: spec.keyPath] = neutral[keyPath: spec.keyPath] }
        }
    }

    // MARK: Look library

    var hasFujifilmLooks: Bool { looks.contains { $0.collection == FujifilmLooks.collection } }

    /// Downloads Fujifilm's official film simulation LUTs and adds them to the library.
    func installFujifilm() {
        guard !isInstallingFujifilm else { return }
        isInstallingFujifilm = true
        Task {
            defer { isInstallingFujifilm = false }
            do {
                try await FujifilmLooks.install()
                reloadLooks()
                Task.detached(priority: .utility) { LookLibrary.shared.preload() }
            } catch {
                alert = AppAlert(title: "Couldn’t download the Fujifilm looks", message: error.localizedDescription)
            }
        }
    }

    func presentImportLUT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.cubeType]
        panel.allowsMultipleSelection = true
        panel.message = "Choose .cube LUTs. Name them after their input (e.g. “F-Log2”, “S-Log3”); otherwise Apple Log is assumed."
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(importLUT)
    }

    func importLUT(_ url: URL) {
        do {
            let look = try LookLibrary.shared.importLUT(url)
            reloadLooks()
            if media != nil { select(look) }
        } catch {
            alert = AppAlert(title: "Couldn’t import “\(url.lastPathComponent)”", message: error.localizedDescription)
        }
    }

    private func reloadLooks() {
        looks = LookLibrary.shared.all
        thumbnails.looksChanged(looks)
    }

    private func apply(_ next: GradeSettings) {
        settings = next
        hasUnsavedChanges = true
        updateUndoState()
        thumbnails.settingsChanged(next)
        scheduleAutosave()
    }

    private func updateUndoState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: Opening

    static let cubeType = UTType(filenameExtension: "cube") ?? .data
    static let openableTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, cubeType,
                                          UTType(filenameExtension: EmulistProject.fileExtension) ?? .json]

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableTypes
        panel.message = "Choose LOG footage, an Emulist project or a .cube LUT"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        if url.pathExtension.lowercased() == "cube" { return importLUT(url) }
        Task {
            if url.pathExtension.lowercased() == EmulistProject.fileExtension {
                await openProject(url)
            } else {
                await importFootage(url)
            }
        }
    }

    private func importFootage(_ url: URL) async {
        guard let info = await inspect(url) else { return }
        var fresh = GradeSettings()
        fresh.select(FilmStock.builtIn[0])
        fresh.cameraProfileID = (info.detectedProfile ?? .appleLog).id
        load(info, settings: fresh, projectURL: nil)
        needsProfileConfirmation = info.detectedProfile == nil
    }

    private func openProject(_ url: URL) async {
        do {
            let project = try EmulistProject.decode(Data(contentsOf: url))
            guard let mediaURL = project.media.resolve() else {
                missingMedia = project
                projectURL = url
                return
            }
            guard let info = await inspect(mediaURL) else { return }
            load(info, settings: project.settings, projectURL: url)
            exportSettings = project.export
        } catch {
            alert = AppAlert(title: "Couldn’t open project", message: error.localizedDescription)
        }
    }

    /// Points a project with missing footage at a new file, keeping every grading decision.
    func relinkMissingMedia() {
        guard let project = missingMedia else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.message = "Locate “\(URL(fileURLWithPath: project.media.path).lastPathComponent)”"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let info = await inspect(url) else { return }
            if !project.media.matches(info) {
                alert = AppAlert(
                    title: "This may be a different clip",
                    message: "Its resolution or duration doesn’t match the original footage. Check that you picked the right file.")
            }
            load(info, settings: project.settings, projectURL: projectURL)
            exportSettings = project.export
            hasUnsavedChanges = true
        }
    }

    func closeMissingMedia() {
        missingMedia = nil
        projectURL = nil
    }

    private func inspect(_ url: URL) async -> MediaInfo? {
        isLoading = true
        defer { isLoading = false }
        do {
            return try await MediaInfo.inspect(url)
        } catch {
            alert = AppAlert(title: "Couldn’t open footage", message: error.localizedDescription)
            return nil
        }
    }

    private func load(_ info: MediaInfo, settings: GradeSettings, projectURL: URL?) {
        media = info
        self.settings = settings
        self.projectURL = projectURL
        missingMedia = nil
        hasUnsavedChanges = false
        compare = .off
        history.reset()
        updateUndoState()
        playback.load(info)
        thumbnails.reset(settings: settings, orientation: info.transform, looks: looks)
        NSDocumentController.shared.noteNewRecentDocumentURL(projectURL ?? info.url)
    }

    // MARK: Saving

    func save() {
        if let projectURL { write(to: projectURL) } else { saveAs() }
    }

    func saveAs() {
        guard media != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: EmulistProject.fileExtension) ?? .json]
        panel.nameFieldStringValue = "\(title).\(EmulistProject.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        guard let media else { return }
        do {
            var project = EmulistProject(media: MediaReference(media), settings: settings, export: exportSettings)
            if url == projectURL, let existing = try? EmulistProject.decode(Data(contentsOf: url)) {
                project.id = existing.id
                project.createdAt = existing.createdAt
            }
            try project.encoded().write(to: url, options: .atomic)
            projectURL = url
            hasUnsavedChanges = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            alert = AppAlert(title: "Couldn’t save project", message: error.localizedDescription)
        }
    }

    /// Saved projects are kept up to date automatically, a moment after the last change.
    private func scheduleAutosave() {
        guard let projectURL else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.projectURL == projectURL else { return }
            self.write(to: projectURL)
        }
    }

    // MARK: Viewing

    /// Before ⇄ after. From the split view it goes straight to before.
    func toggleBefore() {
        compare = compare == .before ? .off : .before
    }

    func toggleSplit() {
        compare = compare == .split ? .off : .split
    }

    /// The fraction of the frame (from the left) rendered as "before".
    var beforeSplit: Double {
        switch compare {
        case .off: 0
        case .split: splitPosition
        case .before: 1
        }
    }
}
