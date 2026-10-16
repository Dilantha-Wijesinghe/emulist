import Foundation

/// A saved grade (`.emulist`, JSON). Projects only reference footage; the source file is never modified.
public struct EmulistProject: Codable, Equatable, Sendable {
    public static let fileExtension = "emulist"
    public static let currentSchemaVersion = 1

    public var schemaVersion = currentSchemaVersion
    public var id = UUID()
    public var createdAt = Date()
    public var modifiedAt = Date()
    public var media: MediaReference
    public var settings: GradeSettings
    public var export: ExportSettings

    public init(media: MediaReference, settings: GradeSettings, export: ExportSettings = .init()) {
        self.media = media
        self.settings = settings
        self.export = export
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EmulistProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(EmulistProject.self, from: data)
        guard project.schemaVersion <= currentSchemaVersion else { throw ProjectError.newerVersion }
        return project
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
