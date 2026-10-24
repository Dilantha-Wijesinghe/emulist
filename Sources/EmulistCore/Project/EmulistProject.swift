import Foundation

/// A saved session (`.emulist`, JSON): its clips, each with a grade and snapshots. Projects only
/// reference footage; source files are never modified.
public struct EmulistProject: Codable, Equatable, Sendable {
    public static let fileExtension = "emulist"
    /// 2: several clips with snapshots. 1: a single clip (still opens).
    public static let currentSchemaVersion = 2

    public var schemaVersion = currentSchemaVersion
    public var id = UUID()
    public var createdAt = Date()
    public var modifiedAt = Date()
    public var clips: [ProjectClip]
    public var selectedClipID: UUID?
    public var export: ExportSettings

    public init(clips: [ProjectClip], selectedClipID: UUID? = nil, export: ExportSettings = .init()) {
        self.clips = clips
        self.selectedClipID = selectedClipID
        self.export = export
    }

    public func encoded() throws -> Data { try EmulistJSON.encode(self) }

    public static func decode(_ data: Data) throws -> EmulistProject {
        let project = try EmulistJSON.decode(EmulistProject.self, from: data)
        guard project.schemaVersion <= currentSchemaVersion else { throw ProjectError.newerVersion }
        return project
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, modifiedAt, clips, selectedClipID, export
    }

    /// Version 1 stored one clip's footage and grade at the top level.
    private enum LegacyKeys: String, CodingKey {
        case media, settings
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        export = try c.decodeIfPresent(ExportSettings.self, forKey: .export) ?? .init()
        selectedClipID = try c.decodeIfPresent(UUID.self, forKey: .selectedClipID)
        if let clips = try c.decodeIfPresent([ProjectClip].self, forKey: .clips) {
            self.clips = clips
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            clips = [ProjectClip(media: try legacy.decode(MediaReference.self, forKey: .media),
                                 settings: try legacy.decode(GradeSettings.self, forKey: .settings))]
        }
    }
}

/// One clip in a project: its footage, its grade, and the grades it has been snapshotted at.
public struct ProjectClip: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var media: MediaReference
    public var settings: GradeSettings
    public var snapshots: [GradeSnapshot] = []

    public init(id: UUID = UUID(), media: MediaReference, settings: GradeSettings, snapshots: [GradeSnapshot] = []) {
        self.id = id
        self.media = media
        self.settings = settings
        self.snapshots = snapshots
    }
}

/// A grade saved at a moment, to come back to or compare against.
public struct GradeSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var settings: GradeSettings
    public var createdAt = Date()

    public init(name: String, settings: GradeSettings) {
        self.name = name
        self.settings = settings
    }
}

/// Where the footage lives, plus enough metadata to recognise it when relinking.
public struct MediaReference: Codable, Equatable, Sendable {
    public var path: String
    public var bookmark: Data?
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var duration: Double

    public init(_ info: MediaInfo) {
        path = info.url.path
        bookmark = try? info.url.bookmarkData(options: .minimalBookmark)
        width = info.width
        height = info.height
        frameRate = info.frameRate
        duration = info.duration
    }

    /// The footage's current location: the bookmark follows moves and renames; the path is the fallback.
    public func resolve() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a candidate file plausibly is this footage (used to warn before relinking to a different clip).
    public func matches(_ info: MediaInfo) -> Bool {
        info.width == width && info.height == height && abs(info.duration - duration) < 0.5
    }
}

public enum ProjectError: LocalizedError {
    case newerVersion

    public var errorDescription: String? {
        "This project was saved by a newer version of Emulist."
    }
}
