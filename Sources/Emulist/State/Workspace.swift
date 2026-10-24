import AppKit
import EmulistCore
import Observation
import UniformTypeIdentifiers

enum CompareMode: String, CaseIterable, Identifiable {
    case off, split, before
    var id: String { rawValue }
}

/// What the export sheet exports.
enum ExportScope: String, CaseIterable, Identifiable {
    case selectedClip, allClips
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

/// A grade about to be saved as a look or exported as a LUT (from the current clip, a snapshot or a look).
struct LookDraft: Identifiable {
    let id = UUID()
    var name: String
    let settings: GradeSettings
}

/// A film recipe ready to apply: its source and the look it becomes.
struct RecipeLook: Identifiable {
    let recipe: FilmRecipe
    let preset: GradePreset
    var id: UUID { preset.id }

    /// The Fuji X Weekly recipes whose film simulation is among `looks`.
    static func fujiXWeekly(in looks: [FilmStock]) -> [RecipeLook] {
        FilmRecipe.fujiXWeekly.compactMap { recipe in recipe.preset(in: looks).map { RecipeLook(recipe: recipe, preset: $0) } }
    }
}

/// The single source of truth for the session: its clips, the selected clip's grade, saved looks and
/// the app's modes.
@MainActor @Observable
final class Workspace {
    let playback = PlaybackController()
    let thumbnails = LibraryThumbnails()
    let clipThumbnails = ClipThumbnails()

    // Session
    private(set) var clips: [Clip] = []
    private(set) var selectedClipID: UUID?
    /// Clips ⌘-clicked together in the clip strip; pastes go to all of them. Always holds the selection.
    var pickedClipIDs: Set<UUID> = []
    var exportSettings = ExportSettings()
    private(set) var projectURL: URL?
    private(set) var hasUnsavedChanges = false

    // The selected clip's working copy (see `Clip`)
    private(set) var media: MediaInfo?
    private(set) var settings = GradeSettings()
    @ObservationIgnored private var history = EditHistory<GradeSettings>()
    private(set) var canUndo = false
    private(set) var canRedo = false
    var needsProfileConfirmation = false {
        didSet { if !needsProfileConfirmation, let index = selectedIndex { clips[index].needsProfileConfirmation = false } }
    }

    // Looks
    /// Every look in the library (built-in stocks and installed LUTs).
    private(set) var looks = LookLibrary.shared.all
    private(set) var presets = PresetStore.standard.load()
    /// Built-in recipe looks; empty until the Fujifilm simulations they build on are installed.
    private(set) var recipes = RecipeLook.fujiXWeekly(in: LookLibrary.shared.all)
    private(set) var isInstallingFujifilm = false
    /// A grade copied with Copy Grade, waiting to be pasted.
    private(set) var copiedGrade: GradeSettings?
    /// The groups Paste Grade copies; remembered between launches.
    var pasteGroups: Set<GradeGroup> = Workspace.savedPasteGroups {
        didSet { UserDefaults.standard.set(pasteGroups.map(\.rawValue), forKey: Self.pasteGroupsKey) }
    }

    // Modes
    var compare = CompareMode.off
    var splitPosition = 0.5
    var quality = PreviewQuality.full
    var alert: AppAlert?
    var isExportSheetPresented = false
    var exportScope = ExportScope.selectedClip
    var isPasteSheetPresented = false
    var lookDraft: LookDraft?
    var cubeDraft: LookDraft?
    private(set) var isLoading = false

    /// True during a drag or scroll of a control (the viewer previews on a coarser LUT meanwhile).
    @ObservationIgnored private(set) var isContinuousEdit = false
    /// Drag changes waiting for the next display frame (see `continuousEdit`).
    @ObservationIgnored private var pendingSettings: GradeSettings?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    init() {
        // Parse installed LUTs up front so thumbnails and first selections don't wait on disk.
        Task.detached(priority: .utility) { LookLibrary.shared.preload() }
    }

    var title: String {
        projectURL?.deletingPathExtension().lastPathComponent ?? selectedClip?.name ?? "Emulist"
    }

    var selectedClip: Clip? { selectedIndex.map { clips[$0] } }
    private var selectedIndex: Int? { clips.firstIndex { $0.id == selectedClipID } }

    // MARK: Editing

    /// A discrete change (picker, toggle, preset, reset): one undo step.
    func edit(_ change: (inout GradeSettings) -> Void) {
        flushContinuousEdit()
        var next = settings
        change(&next)
        guard next != settings else { return }
        history.record(settings)
        commit(next)
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
        commit(next)
    }

    func undo() {
        flushContinuousEdit()
        if let previous = history.undo(from: settings) { commit(previous) }
    }

    func redo() {
        flushContinuousEdit()
        if let next = history.redo(from: settings) { commit(next) }
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

    /// Sets the selected clip's grade (undo history is handled by the callers).
    private func commit(_ next: GradeSettings) {
        settings = next
        updateUndoState()
        refreshLibraryThumbnails()
        sessionChanged()
    }

    private func updateUndoState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: Copy, paste and snapshots

    func copyGrade() {
        flushContinuousEdit()
        copiedGrade = settings
    }

    /// Pastes the copied grade's `pasteGroups` onto the picked clips (or every clip): one undo step each.
    func pasteGrade(toAllClips: Bool = false) {
        guard let copiedGrade else { return }
        copyGrade(copiedGrade, groups: pasteGroups, to: toAllClips ? Set(clips.map(\.id)) : pickedClipIDs)
    }

    /// Copies the selected clip's grade (`pasteGroups` of it) onto every other clip.
    func applyGradeToAllClips() {
        flushContinuousEdit()
        copyGrade(settings, groups: pasteGroups, to: Set(clips.map(\.id)).subtracting([selectedClipID].compactMap { $0 }))
    }

    private func copyGrade(_ source: GradeSettings, groups: Set<GradeGroup>, to clipIDs: Set<UUID>) {
        for index in clips.indices where clipIDs.contains(clips[index].id) {
            if clips[index].id == selectedClipID {
                edit { $0.copy(groups, from: source) }
            } else {
                var pasted = clips[index].settings
                pasted.copy(groups, from: source)
                guard pasted != clips[index].settings else { continue }
                clips[index].history.record(clips[index].settings)
                clips[index].settings = pasted
            }
        }
        sessionChanged()
    }

    var snapshots: [GradeSnapshot] { selectedClip?.snapshots ?? [] }

    func takeSnapshot() {
        guard let index = selectedIndex else { return }
        flushContinuousEdit()
        clips[index].snapshots.append(GradeSnapshot(name: "Snapshot \(clips[index].snapshots.count + 1)", settings: settings))
        sessionChanged()
    }

    func restore(_ snapshot: GradeSnapshot) {
        edit { $0 = snapshot.settings }
    }

    func delete(_ snapshot: GradeSnapshot) {
        guard let index = selectedIndex else { return }
        clips[index].snapshots.removeAll { $0.id == snapshot.id }
        sessionChanged()
    }

    // MARK: Saved looks (presets)

    /// Opens the Save Look sheet for `source` (the current grade by default).
    func saveLook(from source: GradeSettings? = nil, name: String? = nil) {
        lookDraft = draft(from: source, name: name)
    }

    /// Opens the Export Look as .cube sheet for `source` (the current grade by default).
    func exportCube(from source: GradeSettings? = nil, name: String? = nil) {
        cubeDraft = draft(from: source, name: name)
    }

    /// A look applied as its thumbnail shows it: on top of the current grade.
    func exportCube(_ preset: GradePreset) {
        exportCube(from: preset.applied(to: settings), name: preset.name)
    }

    private func draft(from source: GradeSettings?, name: String?) -> LookDraft {
        flushContinuousEdit()
        return LookDraft(name: name ?? "\(settings.stock.name) Look", settings: source ?? settings)
    }

    func savePreset(name: String, groups: Set<GradeGroup>, settings: GradeSettings) {
        store(GradePreset(name: name, groups: groups, settings: settings))
    }

    func apply(_ preset: GradePreset) {
        edit { $0 = preset.applied(to: $0) }
    }

    func rename(_ preset: GradePreset, to name: String) {
        var renamed = preset
        renamed.name = name
        store(renamed)
    }

    func delete(_ preset: GradePreset) {
        do {
            try PresetStore.standard.delete(preset)
            presets.removeAll { $0.id == preset.id }
            refreshLibraryThumbnails()
        } catch {
            alert = AppAlert(title: "Couldn’t delete “\(preset.name)”", message: error.localizedDescription)
        }
    }

    private func store(_ preset: GradePreset) {
        do {
            try PresetStore.standard.save(preset)
            if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset } else { presets.append(preset) }
            refreshLibraryThumbnails()
        } catch {
            alert = AppAlert(title: "Couldn’t save “\(preset.name)”", message: error.localizedDescription)
        }
    }

    private static let pasteGroupsKey = "pasteGroups"
    private static var savedPasteGroups: Set<GradeGroup> {
        guard let raw = UserDefaults.standard.stringArray(forKey: pasteGroupsKey) else { return GradeGroup.creative }
        return Set(raw.compactMap(GradeGroup.init(rawValue:)))
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
        recipes = RecipeLook.fujiXWeekly(in: looks)
        refreshLibraryThumbnails()
    }

    private func refreshLibraryThumbnails() {
        thumbnails.update(settings: settings, looks: looks, presets: presets + recipes.map(\.preset))
    }

    // MARK: Opening

    static let cubeType = UTType(filenameExtension: "cube") ?? .data
    static let projectType = UTType(filenameExtension: EmulistProject.fileExtension) ?? .json
    static let openableTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, cubeType, projectType]

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose LOG footage (several clips at once if you like), an Emulist project or .cube LUTs"
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// LUTs join the library; a project replaces the session (any footage alongside it is ignored);
    /// otherwise footage is added to the session as clips.
    func open(_ urls: [URL]) {
        let byKind = Dictionary(grouping: urls) { $0.pathExtension.lowercased() }
        byKind["cube"]?.forEach(importLUT)
        if let project = byKind[EmulistProject.fileExtension]?.first {
            Task { await openProject(project) }
            return
        }
        let footage = urls.filter { $0.pathExtension.lowercased() != "cube" }
        if !footage.isEmpty { Task { await addClips(footage) } }
    }

    private func addClips(_ urls: [URL]) async {
        var added: [Clip] = []
        for url in urls {
            if let info = await inspect(url) { added.append(Clip(media: info)) }
        }
        guard let first = added.first else { return }
        clips += added
        selectClip(first.id)
        sessionChanged()
        added.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0.reference.url) }
    }

    private func openProject(_ url: URL) async {
        do {
            let project = try EmulistProject.decode(Data(contentsOf: url))
            var opened = project.clips.map(Clip.init)
            for index in opened.indices {
                // Missing footage leaves just that clip waiting to be relinked.
                if let mediaURL = opened[index].reference.resolve(), let info = await inspect(mediaURL, quietly: true) {
                    opened[index].media = info
                }
            }
            guard confirmLeavingSession() else { return }
            resetSession()
            clips = opened
            exportSettings = project.export
            projectURL = url
            selectClip(project.selectedClipID.flatMap { id in opened.first { $0.id == id }?.id } ?? opened.first?.id)
            hasUnsavedChanges = false
            clipThumbnails.update(thumbnailItems)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            alert = AppAlert(title: "Couldn’t open project", message: error.localizedDescription)
        }
    }

    private func inspect(_ url: URL, quietly: Bool = false) async -> MediaInfo? {
        isLoading = true
        defer { isLoading = false }
        do {
            return try await MediaInfo.inspect(url)
        } catch {
            if !quietly { alert = AppAlert(title: "Couldn’t open footage", message: error.localizedDescription) }
            return nil
        }
    }

    // MARK: Clips

    func selectClip(_ id: UUID?) {
        guard let id, id != selectedClipID || media == nil, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        flushContinuousEdit()
        syncSelectedClip()
        selectedClipID = id
        pickedClipIDs = [id]
        let clip = clips[index]
        settings = clip.settings
        history = clip.history
        media = clip.media
        compare = .off
        updateUndoState()
        needsProfileConfirmation = clip.needsProfileConfirmation
        if let media = clip.media {
            playback.load(media)
            thumbnails.reset(orientation: media.transform)
            refreshLibraryThumbnails()
        } else {
            playback.unload()
        }
    }

    /// ⌘-click: adds a clip to, or removes it from, the clips a paste goes to.
    func togglePicked(_ id: UUID) {
        guard id != selectedClipID else { return }
        if pickedClipIDs.contains(id) { pickedClipIDs.remove(id) } else { pickedClipIDs.insert(id) }
    }

    func selectAdjacentClip(_ step: Int) {
        guard let index = selectedIndex, clips.indices.contains(index + step) else { return }
        selectClip(clips[index + step].id)
    }

    func removeClip(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        guard clips.count > 1 else { return resetSession() }
        if id == selectedClipID { selectClip(clips[index == clips.count - 1 ? index - 1 : index + 1].id) }
        clips.remove(at: index)
        pickedClipIDs.remove(id)
        sessionChanged()
    }

    /// Points the selected clip at its footage's new location, keeping every grading decision.
    func relinkSelectedClip() {
        guard let index = selectedIndex else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.message = "Locate “\(URL(fileURLWithPath: clips[index].reference.path).lastPathComponent)”"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let info = await inspect(url), let index = selectedIndex else { return }
            if !clips[index].reference.matches(info) {
                alert = AppAlert(
                    title: "This may be a different clip",
                    message: "Its resolution or duration doesn’t match the original footage. Check that you picked the right file.")
            }
            clips[index].link(info)
            media = nil
            selectClip(clips[index].id)
            sessionChanged()
        }
    }

    /// Ends the session, once anything unsaved is saved or knowingly discarded.
    func closeProject() {
        guard confirmLeavingSession() else { return }
        resetSession()
    }

    /// Before the session is closed, replaced or the app quits: true when nothing would be lost. A saved
    /// project is written now; a session never saved asks to save, discard or cancel.
    func confirmLeavingSession() -> Bool {
        flushContinuousEdit()
        guard hasUnsavedChanges, !clips.isEmpty else { return true }
        if let projectURL {
            write(to: projectURL)
            return !hasUnsavedChanges
        }
        let alert = NSAlert()
        alert.messageText = "Save this session first?"
        alert.informativeText = clips.count == 1
            ? "Its grade and snapshots will be lost if you don’t save them."
            : "The grades and snapshots of its \(clips.count) clips will be lost if you don’t save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveAs()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// No clips, no project.
    private func resetSession() {
        flushContinuousEdit()
        playback.unload()
        clips = []
        selectedClipID = nil
        pickedClipIDs = []
        media = nil
        settings = GradeSettings()
        history.reset()
        updateUndoState()
        projectURL = nil
        hasUnsavedChanges = false
        needsProfileConfirmation = false
        clipThumbnails.update([])
    }

    /// Writes the working copy back into the selected clip's record.
    private func syncSelectedClip() {
        guard let index = selectedIndex else { return }
        clips[index].settings = settings
        clips[index].history = history
    }

    /// Every clip with its grade as it stands now, the selected clip's working copy included.
    func clipsForExport() -> [Clip] {
        flushContinuousEdit()
        syncSelectedClip()
        return clips
    }

    private var thumbnailItems: [(id: UUID, media: MediaInfo, settings: GradeSettings)] {
        clips.compactMap { clip in
            clip.media.map { (clip.id, $0, clip.id == selectedClipID ? settings : clip.settings) }
        }
    }

    /// Something worth saving changed: refresh the clip strip and autosave.
    private func sessionChanged() {
        hasUnsavedChanges = true
        if clips.count > 1 { clipThumbnails.update(thumbnailItems) }
        scheduleAutosave()
    }

    // MARK: Saving

    func presentExport(_ scope: ExportScope) {
        exportScope = scope
        isExportSheetPresented = true
    }

    func save() {
        if let projectURL { write(to: projectURL) } else { saveAs() }
    }

    /// Returns whether the project was written.
    @discardableResult
    func saveAs() -> Bool {
        guard !clips.isEmpty else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = "\(title).\(EmulistProject.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        write(to: url)
        return !hasUnsavedChanges
    }

    private func write(to url: URL) {
        flushContinuousEdit()
        syncSelectedClip()
        do {
            var project = EmulistProject(clips: clips.map(\.saved), selectedClipID: selectedClipID, export: exportSettings)
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

extension MediaReference {
    var url: URL { URL(fileURLWithPath: path) }
}
