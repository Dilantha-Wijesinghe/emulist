import Foundation

/// Every look the app can use: the built-in film stocks plus `.cube` LUTs found in the looks folder
/// (`~/Library/Application Support/Emulist/Looks/<Collection>/*.cube`). Parsed LUTs are cached.
public final class LookLibrary: @unchecked Sendable {
    public static let shared = LookLibrary()

    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Emulist/Looks", directoryHint: .isDirectory)
    }

    public static let importedCollection = "Imported"

    private let lock = NSLock()
    private var external: [FilmStock] = []
    private var cubes: [URL: CubeLUT] = [:]

    init() { reload() }

    /// Built-in stocks first, then each external collection (Fujifilm first, then alphabetical).
    public var all: [FilmStock] {
        FilmStock.builtIn + lock.withLock { external }
    }

    public func stock(id: String) -> FilmStock? { all.first { $0.id == id } }

    /// Rescans the looks folder. Cheap: only file names and headers are read.
    public func reload() {
        let root = Self.directory
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension.lowercased() == "cube" }
        let looks = files.compactMap { Self.look(for: $0, root: root) }.sorted(by: Self.libraryOrder)
        lock.withLock { external = looks }
    }

    /// The parsed LUT for `source`, loaded on first use.
    public func cube(for source: LUTSource) throws -> CubeLUT {
        if let cached = lock.withLock({ cubes[source.url] }) { return cached }
        let cube = try CubeLUT(contentsOf: source.url)
        lock.withLock { cubes[source.url] = cube }
        return cube
    }

    /// Parses every LUT in the background so thumbnails and the first selection don't wait.
    public func preload() {
        for look in all { if let lut = look.lut { _ = try? cube(for: lut) } }
    }

    /// Copies a `.cube` file into the Imported collection and returns its look.
    @discardableResult
    public func importLUT(_ url: URL) throws -> FilmStock {
        _ = try CubeLUT(contentsOf: url)
        let folder = Self.directory.appending(path: Self.importedCollection, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: url, to: destination)
        reload()
        guard let look = Self.look(for: destination, root: Self.directory) else { throw CubeLUT.ParseError.missingSize }
        return look
    }

    // MARK: Discovery

    static func look(for url: URL, root: URL) -> FilmStock? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let input = inputProfile(forName: name) else { return nil }
        let collection = url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
            ? importedCollection : url.deletingLastPathComponent().lastPathComponent
        var look = FilmStock(
            id: "lut:\(collection)/\(url.lastPathComponent)", name: displayName(name), format: "\(input.name) LUT",
            summary: "A 3D LUT for \(input.name) footage.", collection: collection, response: .neutral,
            lut: LUTSource(url: url, inputProfileID: input.id),
            grain: GrainSettings(amount: 20, size: 25), halation: HalationSettings(amount: 15, radius: 30),
            bloom: BloomSettings(amount: 12, radius: 40))
        if let fuji = FujifilmLooks.simulation(forFileName: name) { fuji.decorate(&look) }
        return look
    }

    /// The camera encoding a LUT expects, from the naming conventions vendors use. LUTs for encodings
    /// Emulist can't produce (e.g. F-Log2 C / F-Gamut C, whose primaries are unpublished) are skipped.
    static func inputProfile(forName name: String) -> CameraProfile? {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        if key.contains("flog2c") || key.contains("fgamutc") { return nil }
        if key.contains("flog2") { return .fLog2 }
        if key.contains("flog") { return .fLog }
        if key.contains("slog3") { return .sLog3 }
        if key.contains("vlog") { return .vLog }
        return .appleLog
    }

    private static func displayName(_ fileName: String) -> String {
        fileName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    private static func libraryOrder(_ a: FilmStock, _ b: FilmStock) -> Bool {
        func rank(_ collection: String) -> Int {
            collection == FujifilmLooks.collection ? 0 : collection == importedCollection ? 2 : 1
        }
        if a.collection != b.collection {
            return (rank(a.collection), a.collection) < (rank(b.collection), b.collection)
        }
        let ia = FujifilmLooks.order(of: a), ib = FujifilmLooks.order(of: b)
        return (ia, a.name) < (ib, b.name)
    }
}

extension [FilmStock] {
    /// Looks grouped by collection, in first-appearance order.
    public var groupedByCollection: [(name: String, looks: [FilmStock])] {
        var order: [String] = []
        var groups: [String: [FilmStock]] = [:]
        for look in self {
            if groups[look.collection] == nil { order.append(look.collection) }
            groups[look.collection, default: []].append(look)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
