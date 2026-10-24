import Foundation

/// Fujifilm's official film simulation LUTs (F-Log2 / F-Gamut → BT.709), published free by Fujifilm for
/// its cameras. They are downloaded from Fujifilm on request and never bundled with Emulist.
///
/// Apple Log footage reaches them through a colorimetric bridge: Apple Log → scene-linear Rec.2020
/// (= F-Gamut) → F-Log2. Each simulation then renders exactly as Fujifilm designed it.
public enum FujifilmLooks {
    public static let collection = "Fujifilm"

    /// The GFX ETERNA 55 package is the only one that carries every simulation (65-point grids).
    public static let packageURL = URL(string: "https://dl.fujifilm-x.com/support/lut/gfx-eterna-55-3d-lut-v110.zip")!
    public static let packageSize = "46 MB"

    struct Simulation {
        let key: String
        let name: String
        let format: String
        let summary: String
        var grain = GrainSettings(amount: 18, size: 22, softness: 25, chroma: 35)
        var halation = HalationSettings(amount: 15, radius: 30)
        var bloom = BloomSettings(amount: 12, radius: 40)

        func decorate(_ look: inout FilmStock) {
            look.name = name
            look.format = format
            look.summary = summary
            look.collection = FujifilmLooks.collection
            look.grain = grain
            look.halation = halation
            look.bloom = bloom
        }
    }

    /// In the order Fujifilm lists them on its cameras.
    static let simulations: [Simulation] = [
        Simulation(key: "PROVIA", name: "Provia", format: "Standard",
                   summary: "Fujifilm’s standard. Faithful, balanced color with natural contrast for any subject."),
        Simulation(key: "Velvia", name: "Velvia", format: "Vivid",
                   summary: "Vivid slide film. Deep blues and lush greens with punchy contrast, made for landscapes.",
                   grain: GrainSettings(amount: 14, size: 18, softness: 20, chroma: 35)),
        Simulation(key: "ASTIA", name: "Astia", format: "Soft",
                   summary: "Soft and flattering. Gentle tonality for skin, while keeping colors bright."),
        Simulation(key: "CLASSIC-CHROME", name: "Classic Chrome", format: "Documentary",
                   summary: "Muted, full-bodied documentary color. Firm shadows, restrained reds, cyan-leaning skies.",
                   grain: GrainSettings(amount: 24, size: 26, softness: 25, chroma: 30)),
        Simulation(key: "REALA-ACE", name: "Reala Ace", format: "Natural",
                   summary: "Faithful color with crisp, firm tonality. True to life, with a little bite."),
        Simulation(key: "PRO-Neg.Std", name: "Pro Neg. Std", format: "Studio Negative",
                   summary: "Soft studio negative. Smooth skin, subdued color and gentle gradation."),
        Simulation(key: "CLASSIC-Neg.", name: "Classic Neg.", format: "Snapshot Negative",
                   summary: "Everyday negative film. Hard tonality, teal-tinted shadows and warm, nostalgic highlights.",
                   grain: GrainSettings(amount: 30, size: 30, softness: 28, chroma: 45),
                   halation: HalationSettings(amount: 22, radius: 32)),
        Simulation(key: "ETERNA", name: "Eterna", format: "Cinema",
                   summary: "Motion picture film. Low saturation, soft shadows and a muted, cinematic palette.",
                   grain: GrainSettings(amount: 22, size: 26, softness: 28, chroma: 35),
                   halation: HalationSettings(amount: 22, radius: 35)),
        Simulation(key: "ETERNA-BB", name: "Eterna Bleach Bypass", format: "Cinema · Bleach Bypass",
                   summary: "Silver-retained cinema print. Desaturated, high contrast and gritty.",
                   grain: GrainSettings(amount: 30, size: 28, softness: 25, chroma: 25)),
        Simulation(key: "ACROS", name: "Acros", format: "Monochrome",
                   summary: "Black and white with smooth tonality, rich blacks and fine, sharp grain.",
                   grain: GrainSettings(amount: 30, size: 24, softness: 22, chroma: 0),
                   halation: HalationSettings(amount: 0, radius: 30)),
    ]

    /// Fujifilm names its files `FLog2_to_<SIMULATION>_65grid_V.1.00.cube`.
    static func simulation(forFileName name: String) -> Simulation? {
        guard let range = name.range(of: "_to_") else { return nil }
        let rest = name[range.upperBound...]
        return simulations.first { rest.hasPrefix($0.key + "_") || rest == $0.key }
    }

    /// The simulation a Fujifilm look renders (nil for any other look).
    public static func simulationKey(of look: FilmStock) -> String? {
        guard look.collection == collection, let lut = look.lut else { return nil }
        return simulation(forFileName: lut.url.deletingPathExtension().lastPathComponent)?.key
    }

    static func order(of look: FilmStock) -> Int {
        simulations.firstIndex { $0.name == look.name && look.collection == collection } ?? simulations.count
    }

    public static var isInstalled: Bool {
        LookLibrary.shared.all.contains { $0.collection == collection }
    }

    /// Downloads Fujifilm's LUT package and installs the F-Log2 film simulations into the looks folder.
    public static func install() async throws {
        let (archive, response) = try await URLSession.shared.download(from: packageURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "emulist-fujifilm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archive.path, scratch.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }

        try installLUTs(from: scratch)
        LookLibrary.shared.reload()
    }

    /// Copies the 65-point F-Log2 simulations found anywhere under `folder` (skipping the neutral
    /// WDR and F-Log2-709 conversions, which aren't looks).
    public static func installLUTs(from folder: URL) throws {
        let destination = LookLibrary.directory.appending(path: collection, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "cube" && $0.lastPathComponent.hasPrefix("FLog2_to_")
                && $0.lastPathComponent.contains("65grid") && simulation(forFileName: $0.deletingPathExtension().lastPathComponent) != nil }
        guard !files.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        for file in files {
            let target = destination.appending(path: file.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: file, to: target)
        }
    }
}
