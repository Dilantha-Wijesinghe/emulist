import Foundation
import Testing
@testable import EmulistCore

@Suite struct ExportNamingTests {
    @Test func baseNameJoinsClipAndLookWithoutPathSeparators() {
        #expect(ExportNaming.baseName(clip: "A001", look: "Solstice 400") == "A001 – Solstice 400")
        #expect(ExportNaming.baseName(clip: "A001", look: "Day/Night: v2") == "A001 – Day-Night- v2")
    }

    @Test func collisionsWithinTheBatchAreNumbered() {
        let names = ExportNaming.uniqueFileNames(["a – X", "b – X", "a – X", "a – X"], fileExtension: "mov", taken: [])
        #expect(names == ["a – X.mov", "b – X.mov", "a – X 2.mov", "a – X 3.mov"])
    }

    @Test func existingFilesAreNeverReusedIgnoringCase() {
        let names = ExportNaming.uniqueFileNames(["a – X", "b – X"], fileExtension: "mov", taken: ["A – x.MOV", "a – X 2.mov", "b – X.mp4"])
        #expect(names == ["a – X 3.mov", "b – X.mov"])
    }

    @Test func destinationsAvoidFilesInTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("clip – Look.mp4"))
        let urls = try ExportNaming.destinations(for: ["clip – Look"], in: folder, fileExtension: "mp4")
        #expect(urls.map(\.lastPathComponent) == ["clip – Look 2.mp4"])
    }
}
