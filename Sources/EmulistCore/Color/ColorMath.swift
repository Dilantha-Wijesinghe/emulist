import simd

public typealias RGB = SIMD3<Double>
public typealias Matrix3 = simd_double3x3

/// CIE 1931 xy chromaticity coordinate.
public struct Chromaticity: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    /// XYZ of this chromaticity with luminance Y = 1.
    var xyz: SIMD3<Double> { [x / y, 1, (1 - x - y) / y] }

    public static let d65 = Chromaticity(0.3127, 0.3290)
}

/// An RGB color space's primaries and white point.
public struct ColorPrimaries: Codable, Hashable, Sendable {
    public var red: Chromaticity
    public var green: Chromaticity
    public var blue: Chromaticity
    public var white: Chromaticity

    public static let rec709 = ColorPrimaries(
        red: .init(0.640, 0.330), green: .init(0.300, 0.600), blue: .init(0.150, 0.060), white: .d65)
    public static let rec2020 = ColorPrimaries(
        red: .init(0.708, 0.292), green: .init(0.170, 0.797), blue: .init(0.131, 0.046), white: .d65)
    /// Sony S-Gamut3.Cine (Sony technical summary for S-Gamut3.Cine/S-Log3).
    public static let sGamut3Cine = ColorPrimaries(
        red: .init(0.766, 0.275), green: .init(0.225, 0.800), blue: .init(0.089, -0.087), white: .d65)
    /// Panasonic V-Gamut (Panasonic V-Log/V-Gamut reference manual).
    public static let vGamut = ColorPrimaries(
        red: .init(0.730, 0.280), green: .init(0.165, 0.840), blue: .init(0.100, -0.030), white: .d65)

    /// Normalized primary matrix: linear RGB -> CIE XYZ.
    public var rgbToXYZ: Matrix3 {
        let p = Matrix3(columns: (red.xyz * red.y, green.xyz * green.y, blue.xyz * blue.y))
        let scale = p.inverse * white.xyz
        return Matrix3(columns: (p.columns.0 * scale.x, p.columns.1 * scale.y, p.columns.2 * scale.z))
    }

    /// Luminance (Y) weights of the RGB channels.
    public var luminanceWeights: RGB {
        let m = rgbToXYZ
        return [m.columns.0.y, m.columns.1.y, m.columns.2.y]
    }

    /// Matrix converting linear RGB in `self` to linear RGB in `target`, with Bradford adaptation if whites differ.
    public func conversion(to target: ColorPrimaries) -> Matrix3 {
        let adapt = ChromaticAdaptation.bradford(from: white, to: target.white)
        return target.rgbToXYZ.inverse * adapt * rgbToXYZ
    }
}

public enum ChromaticAdaptation {
    // Bradford cone response matrix (Lam 1985, as used by ICC).
    private static let bradfordMatrix = Matrix3(rows: [
        [0.8951, 0.2664, -0.1614],
        [-0.7502, 1.7135, 0.0367],
        [0.0389, -0.0685, 1.0296],
    ])

    /// XYZ -> XYZ von Kries adaptation in Bradford cone space.
    public static func bradford(from source: Chromaticity, to target: Chromaticity) -> Matrix3 {
        if source == target { return matrix_identity_double3x3 }
        let s = bradfordMatrix * source.xyz
        let t = bradfordMatrix * target.xyz
        return bradfordMatrix.inverse * Matrix3(diagonal: t / s) * bradfordMatrix
    }

    /// CIE daylight locus chromaticity for a correlated color temperature (valid 4000 K – 25000 K).
    public static func daylight(kelvin: Double) -> Chromaticity {
        let t = min(max(kelvin, 4000), 25000)
        let x = t <= 7000
            ? -4.6070e9 / (t * t * t) + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
            : -2.0064e9 / (t * t * t) + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        return Chromaticity(x, -3.0 * x * x + 2.87 * x - 0.275)
    }
}

extension Chromaticity {
    /// Offsets the chromaticity along CIE 1976 v' (positive = greener).
    func shiftedV(by dv: Double) -> Chromaticity {
        let d = -2 * x + 12 * y + 3
        let u = 4 * x / d
        let v = 9 * y / d + dv
        let d2 = 6 * u - 16 * v + 12
        return Chromaticity(9 * u / d2, 4 * v / d2)
    }
}

extension Matrix3 {
    /// Row-major float array (for GPU uniforms).
    var floatRows: [Float] {
        (0..<3).flatMap { r in (0..<3).map { c in Float(self[c][r]) } }
    }
}
