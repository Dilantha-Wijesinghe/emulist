import EmulistCore
import Foundation

/// One clip of the session: its footage, grade, undo history and snapshots.
///
/// The selected clip's grade and history are edited in the workspace's working copy (`Workspace.settings`,
/// at full speed during drags); its record here is brought up to date when another clip is selected or
/// the project is saved.
struct Clip: Identifiable {
    let id: UUID
    var reference: MediaReference
    /// nil while the footage can't be found.
    var media: MediaInfo?
    var settings: GradeSettings
    var snapshots: [GradeSnapshot] = []
    var history = EditHistory<GradeSettings>()
    /// The camera profile was a guess: ask when the clip is first shown.
    var needsProfileConfirmation = false

    var name: String { URL(fileURLWithPath: reference.path).deletingPathExtension().lastPathComponent }

    /// Newly imported footage, starting from the default look with the camera profile the file declares.
    init(media: MediaInfo) {
        id = UUID()
        reference = MediaReference(media)
        self.media = media
        settings = GradeSettings()
        settings.select(FilmStock.builtIn[0])
        settings.cameraProfileID = (media.detectedProfile ?? .appleLog).id
        needsProfileConfirmation = media.detectedProfile == nil
    }

    /// A clip from a saved project (its footage is located separately).
    init(_ saved: ProjectClip) {
        id = saved.id
        reference = saved.media
        settings = saved.settings
        snapshots = saved.snapshots
    }

    var saved: ProjectClip { ProjectClip(id: id, media: reference, settings: settings, snapshots: snapshots) }

    /// Points the clip at (new) footage.
    mutating func link(_ info: MediaInfo) {
        media = info
        reference = MediaReference(info)
    }
}
