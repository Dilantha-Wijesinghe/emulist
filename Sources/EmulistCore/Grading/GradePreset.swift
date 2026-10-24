import Foundation

/// A saved look ("My Looks"): some groups of a grade, applied on top of any clip's own settings.
public struct GradePreset: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var groups: Set<GradeGroup>
    public var settings: GradeSettings
    public var createdAt = Date()

    public init(name: String, groups: Set<GradeGroup>, settings: GradeSettings) {
        self.name = name
        self.groups = groups
        self.settings = settings
    }

    /// `settings` with this preset's groups applied.
    public func applied(to settings: GradeSettings) -> GradeSettings {
        var result = settings
        result.copy(groups, from: self.settings)
        return result
    }
}

/// Presets on disk, one JSON file each (`~/Library/Application Support/Emulist/Presets/<id>.emulistlook`).
public struct PresetStore: Sendable {
    public static let fileExtension = "emulistlook"
    public static let standard = PresetStore(
        directory: URL.applicationSupportDirectory.appending(path: "Emulist/Presets", directoryHint: .isDirectory))

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Every readable preset, oldest first (unreadable files are skipped).
    public func load() -> [GradePreset] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == Self.fileExtension }
            .compactMap { try? EmulistJSON.decode(GradePreset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ preset: GradePreset) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try EmulistJSON.encode(preset).write(to: url(for: preset), options: .atomic)
    }

    public func delete(_ preset: GradePreset) throws {
        try FileManager.default.removeItem(at: url(for: preset))
    }

    private func url(for preset: GradePreset) -> URL {
        directory.appending(path: "\(preset.id.uuidString).\(Self.fileExtension)")
    }
}
