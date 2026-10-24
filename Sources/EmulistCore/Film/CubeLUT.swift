import Foundation
import simd

/// A 3D LUT in the Adobe/Resolve `.cube` format, sampled with tetrahedral interpolation (as Resolve does).
public struct CubeLUT: Sendable {
    public let title: String?
    public let size: Int
    public let domainMin: RGB
    public let domainMax: RGB
    /// Output values, red varying fastest.
    private let values: [SIMD3<Float>]

    public enum ParseError: LocalizedError {
        case missingSize, wrongEntryCount(expected: Int, found: Int), unsupported(String)

        public var errorDescription: String? {
            switch self {
            case .missingSize: "The file has no LUT_3D_SIZE, so it isn’t a 3D .cube LUT."
            case .wrongEntryCount(let expected, let found): "Expected \(expected) LUT entries but found \(found)."
            case .unsupported(let keyword): "Unsupported .cube keyword “\(keyword)”."
            }
        }
    }

    public init(size: Int, values: [SIMD3<Float>], title: String? = nil,
                domainMin: RGB = .zero, domainMax: RGB = RGB(repeating: 1)) throws {
        guard values.count == size * size * size else {
            throw ParseError.wrongEntryCount(expected: size * size * size, found: values.count)
        }
        self.size = size
        self.values = values
        self.title = title
        self.domainMin = domainMin
        self.domainMax = domainMax
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// Parses the text directly from bytes with `strtod`: a 65³ LUT has ~275k lines.
    public init(data: Data) throws {
        var title: String?
        var size = 0
        var domainMin = RGB.zero, domainMax = RGB(repeating: 1)
        var values: [SIMD3<Float>] = []

        // NUL-terminated copy, so strtod always stops.
        var bytes = [CChar](repeating: 0, count: data.count + 1)
        bytes.withUnsafeMutableBytes { _ = data.copyBytes(to: $0) }
        try bytes.withUnsafeMutableBufferPointer { buffer in
            guard var p = buffer.baseAddress else { return }
            func isSpace(_ c: CChar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
            func restOfLine() -> String {
                let start = p
                while p.pointee != 0, p.pointee != 10, p.pointee != 13 { p += 1 }
                return String(decoding: UnsafeRawBufferPointer(start: start, count: p - start), as: UTF8.self)
            }
            func numbers(in line: String) -> [Double] { line.split(separator: " ").compactMap { Double($0) } }

            while true {
                while isSpace(p.pointee) { p += 1 }
                let c = p.pointee
                if c == 0 { break }
                if c == 35 { // '#'
                    p += 1
                    let comment = restOfLine()
                    if comment.lowercased().hasPrefix("title:") { title = String(comment.dropFirst(6)) }
                } else if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { // keyword line
                    let line = restOfLine()
                    let keyword = line.prefix { $0 != " " && $0 != "\t" }
                    let rest = line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
                    switch keyword {
                    case "TITLE": title = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    case "LUT_3D_SIZE":
                        size = Int(rest) ?? 0
                        values.reserveCapacity(size * size * size)
                    case "DOMAIN_MIN": let n = numbers(in: rest); if n.count == 3 { domainMin = RGB(n[0], n[1], n[2]) }
                    case "DOMAIN_MAX": let n = numbers(in: rest); if n.count == 3 { domainMax = RGB(n[0], n[1], n[2]) }
                    case "LUT_1D_SIZE", "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE": throw ParseError.unsupported(String(keyword))
                    default: break
                    }
                } else {
                    var end: UnsafeMutablePointer<CChar>?
                    let r = strtod(p, &end); p = end!
                    let g = strtod(p, &end); p = end!
                    let b = strtod(p, &end)
                    guard let next = end, next != p else { break }
                    p = next
                    values.append(SIMD3(Float(r), Float(g), Float(b)))
                }
            }
        }
        guard size > 1 else { throw ParseError.missingSize }
        try self.init(size: size, values: values, title: title, domainMin: domainMin, domainMax: domainMax)
    }

    /// The LUT as a `.cube` file: TITLE, LUT_3D_SIZE, the domain when it isn't 0…1, then one entry per
    /// line with red varying fastest.
    public func cubeData() -> Data {
        var text = ""
        if let title { text += "TITLE \"\(title.replacingOccurrences(of: "\"", with: "'"))\"\n" }
        text += "LUT_3D_SIZE \(size)\n"
        if domainMin != .zero || domainMax != RGB(repeating: 1) {
            text += "DOMAIN_MIN \(domainMin.x) \(domainMin.y) \(domainMin.z)\nDOMAIN_MAX \(domainMax.x) \(domainMax.y) \(domainMax.z)\n"
        }
        text.reserveCapacity(text.utf8.count + values.count * 27)
        for v in values { text += String(format: "%.6f %.6f %.6f\n", v.x, v.y, v.z) }
        return Data(text.utf8)
    }

    /// Tetrahedral interpolation; inputs outside the domain are clamped to its edge.
    public func sample(_ input: RGB) -> RGB {
        let n = Double(size - 1)
        let normalized = (input - domainMin) / (domainMax - domainMin)
        let p = simd_clamp(normalized, .zero, RGB(repeating: 1)) * n
        let base = SIMD3<Int>(min(Int(p.x), size - 2), min(Int(p.y), size - 2), min(Int(p.z), size - 2))
        let f = p - RGB(Double(base.x), Double(base.y), Double(base.z))

        func at(_ dr: Int, _ dg: Int, _ db: Int) -> RGB {
            let v = values[((base.z + db) * size + base.y + dg) * size + base.x + dr]
            return RGB(Double(v.x), Double(v.y), Double(v.z))
        }
        let c000 = at(0, 0, 0), c111 = at(1, 1, 1)
        let (r, g, b) = (f.x, f.y, f.z)
        if r > g {
            if g > b { return c000 + (at(1, 0, 0) - c000) * r + (at(1, 1, 0) - at(1, 0, 0)) * g + (c111 - at(1, 1, 0)) * b }
            if r > b { return c000 + (at(1, 0, 0) - c000) * r + (at(1, 0, 1) - at(1, 0, 0)) * b + (c111 - at(1, 0, 1)) * g }
            return c000 + (at(0, 0, 1) - c000) * b + (at(1, 0, 1) - at(0, 0, 1)) * r + (c111 - at(1, 0, 1)) * g
        }
        if b > g { return c000 + (at(0, 0, 1) - c000) * b + (at(0, 1, 1) - at(0, 0, 1)) * g + (c111 - at(0, 1, 1)) * r }
        if b > r { return c000 + (at(0, 1, 0) - c000) * g + (at(0, 1, 1) - at(0, 1, 0)) * b + (c111 - at(0, 1, 1)) * r }
        return c000 + (at(0, 1, 0) - c000) * g + (at(1, 1, 0) - at(0, 1, 0)) * r + (c111 - at(1, 1, 0)) * b
    }
}

extension CubeLUT {
    /// A grade baked into a LUT for other apps (e.g. DaVinci Resolve): from `input` code values (0…1, full
    /// range) to the grade's output encoding, through the same pipeline as the viewer. The clip's own
    /// corrections (exposure, white balance) are left out, so the LUT carries the look; grain, halation and
    /// bloom work on neighboring pixels, so no LUT can carry them.
    public init(baking settings: GradeSettings, input: CameraProfile, size: Int, title: String) throws {
        var look = settings
        look.copy([.input], from: GradeSettings())
        look.cameraProfileID = input.id
        let toWorking = InputTransform.matrix(for: look)
        let renderer = try ColorPipeline(look).makeRenderer()
        let scale = 1 / Double(size - 1)
        var values = [SIMD3<Float>](repeating: .zero, count: size * size * size)
        values.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            LUTBaker.forEachPoint(size: size) { point, r, g, b in
                let code = RGB(Double(r), Double(g), Double(b)) * scale
                let display = simd_clamp(renderer.render(toWorking * code.decoded(input.transfer)), .zero, RGB(repeating: 1))
                out[point] = SIMD3<Float>(display)
            }
        }
        try self.init(size: size, values: values, title: title)
    }
}
