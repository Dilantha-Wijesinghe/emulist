import Foundation
import Testing
@testable import EmulistCore

@Suite struct GradeGroupTests {
    /// Every field of `GradeSettings` changed, found generically through its JSON, so a field added later
    /// that no group copies makes `copyingEveryGroupCopiesEverything` fail.
    static var everythingChanged: GradeSettings {
        get throws {
            func perturb(_ value: Any, key: String) -> Any {
                switch value {
                case let dict as [String: Any]: Dictionary(uniqueKeysWithValues: dict.map { ($0, perturb($1, key: $0)) })
                case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): !number.boolValue
                case let number as NSNumber: number.doubleValue + 1.25
                case let string as String:
                    key == "output" ? OutputTransform.allCases.first { $0.rawValue != string }!.rawValue : string + "-changed"
                default: value
                }
            }
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GradeSettings()))
            let changed = try JSONSerialization.data(withJSONObject: perturb(json, key: ""))
            return try JSONDecoder().decode(GradeSettings.self, from: changed)
        }
    }

    @Test func copyingEveryGroupCopiesEverything() throws {
        let source = try Self.everythingChanged
        var target = GradeSettings()
        target.copy(Set(GradeGroup.allCases), from: source)
        #expect(target == source)
    }

    @Test func groupsAreDisjointAndCopyOnlyThemselves() throws {
        let source = try Self.everythingChanged
        var copiedOnce = GradeSettings()
        for group in GradeGroup.allCases {
            var target = GradeSettings()
            target.copy([group], from: source)
            #expect(target != GradeSettings(), "\(group) copies nothing")
            #expect(target != source, "\(group) copies everything")
            copiedOnce.copy([group], from: source)
        }
        #expect(copiedOnce == source)
        var untouched = GradeSettings()
        untouched.copy([], from: source)
        #expect(untouched == GradeSettings())
    }

    @Test func creativeGroupsLeaveTheClipsOwnSettings() throws {
        var clip = GradeSettings()
        clip.cameraProfileID = CameraProfile.sLog3.id
        clip.exposure = 0.7
        clip.temperature = 20
        clip.output = .rec709Gamma24
        clip.copy(GradeGroup.creative, from: try Self.everythingChanged)
        #expect(clip.cameraProfileID == CameraProfile.sLog3.id && clip.exposure == 0.7 && clip.temperature == 20)
        #expect(clip.output == .rec709Gamma24)
    }
}

@Suite struct PresetTests {
    @Test func applyingALookKeepsTheClipsTexture() {
        var look = GradeSettings()
        look.select(FilmStock.builtIn[1])
        look.saturation = 120
        let preset = GradePreset(name: "Moody", groups: [.look, .primaries], settings: look)
        var clip = GradeSettings()
        clip.grain.amount = 5
        let result = preset.applied(to: clip)
        #expect(result.stockID == look.stockID && result.saturation == 120)
        // `select(stock)` would have loaded the stock's grain; a preset copies only its own groups.
        #expect(result.grain.amount == 5)
    }

    @Test func storeRoundTripsAndDeletes() throws {
        let store = PresetStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "emulist-presets-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        // Whole seconds: files store ISO 8601 dates.
        var first = GradePreset(name: "A", groups: GradeGroup.creative, settings: GradeSettings())
        first.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        var second = GradePreset(name: "B", groups: [.look], settings: GradeSettings())
        second.createdAt = first.createdAt.addingTimeInterval(1)
        try store.save(second)
        try store.save(first)
        #expect(store.load() == [first, second])
        try store.delete(first)
        #expect(store.load() == [second])
    }
}

@Suite struct ProjectSchemaTests {
    @Test func versionOneProjectsOpenAsOneClip() throws {
        let v1 = #"""
        {"schemaVersion": 1, "id": "6F1C6D3A-0D52-4C1E-9A43-8E3A3C0B7A11",
         "createdAt": "2026-10-01T10:00:00Z", "modifiedAt": "2026-10-02T10:00:00Z",
         "media": {"path": "/tmp/a.mov", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5},
         "settings": {"stockID": "nocturne-800", "contrast": 20},
         "export": {"codec": "h264", "resolution": "source", "includeAudio": true}}
        """#
        let project = try EmulistProject.decode(Data(v1.utf8))
        #expect(project.clips.count == 1)
        #expect(project.clips[0].media.path == "/tmp/a.mov" && project.clips[0].settings.contrast == 20)
        #expect(project.clips[0].settings.stockID == "nocturne-800" && project.export.codec == .h264)
        #expect(project.clips[0].snapshots.isEmpty && project.selectedClipID == nil)
    }

    @Test func newerProjectsAreRefused() {
        let future = #"{"schemaVersion": 99, "id": "6F1C6D3A-0D52-4C1E-9A43-8E3A3C0B7A11", "createdAt": "2026-10-01T10:00:00Z", "modifiedAt": "2026-10-01T10:00:00Z", "clips": []}"#
        #expect(throws: ProjectError.self) { try EmulistProject.decode(Data(future.utf8)) }
    }
}
