import Foundation

/// File names for exports: "<clip> – <look>.<ext>".
public enum ExportNaming {
    /// The name without an extension. Path separators in clip or look names become hyphens.
    public static func baseName(clip: String, look: String) -> String {
        "\(clip) – \(look)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// One file name per base name, unique within the list and never one of `taken` (compared ignoring case,
    /// like the file system). Collisions get " 2", " 3", …
    public static func uniqueFileNames(_ baseNames: [String], fileExtension: String, taken: Set<String>) -> [String] {
        var used = Set(taken.map { $0.lowercased() })
        return baseNames.map { base in
            var name = "\(base).\(fileExtension)"
            var number = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(number).\(fileExtension)"
                number += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }

    /// Destinations in `folder` for a batch: nothing already in the folder (the footage included) is overwritten.
    public static func destinations(for baseNames: [String], in folder: URL, fileExtension: String) throws -> [URL] {
        let existing = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        return uniqueFileNames(baseNames, fileExtension: fileExtension, taken: Set(existing))
            .map { folder.appendingPathComponent($0) }
    }
}
