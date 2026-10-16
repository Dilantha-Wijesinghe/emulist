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

    /// Processing scale for a source of the given height (half/quarter never drop below ~540 lines).
    func scale(sourceHeight: Int) -> Double {
        switch self {
        case .full: 1
        case .half: max(0.5, min(1, 540 / Double(sourceHeight)))
        case .quarter: max(0.25, min(1, 540 / Double(sourceHeight)))
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

    var compare = CompareMode.off
    var splitPosition = 0.5
    var quality = PreviewQuality.full
    var alert: AppAlert?
    var isExportSheetPresented = false
    private(set) var isLoading = false

    @ObservationIgnored private var history = EditHistory<GradeSettings>()
    @ObservationIgnored private var isContinuousEdit = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    private(set) var canUndo = false
    private(set) var canRedo = false

    var title: String {
        projectURL?.deletingPathExtension().lastPathComponent ?? media?.url.deletingPathExtension().lastPathComponent
            ?? "Emulist"
    }

    // MARK: Editing

    /// A discrete change (picker, toggle, preset, reset): one undo step.
    func edit(_ change: (inout GradeSettings) -> Void) {
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

    func continuousEdit(_ change: (inout GradeSettings) -> Void) {
        var next = settings
        change(&next)
        apply(next)
    }

    func endContinuousEdit() { isContinuousEdit = false }

    func undo() {
        if let previous = history.undo(from: settings) { apply(previous) }
    }

    func redo() {
        if let next = history.redo(from: settings) { apply(next) }
    }

    func select(_ stock: FilmStock) {
        edit { $0.select(stock) }
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

    static let openableTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, UTType(filenameExtension: EmulistProject.fileExtension) ?? .json]

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableTypes
        panel.message = "Choose LOG footage or an Emulist project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
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
        thumbnails.reset(settings: settings)
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

    func toggleBefore() {
        compare = compare == .before ? .off : .before
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
