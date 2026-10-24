import Foundation
import simd

/// One primary color wheel: a puck position on a vectorscope-oriented disk plus a master ring.
///
/// The puck lives in the unit disk with x along Cb (blue) and y along Cr (red), exactly like a
/// vectorscope, so pushing the puck toward a hue on the ring tints the image toward that hue.
public struct ColorWheel: Codable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case lift, gamma, gain, offset
        public var id: String { rawValue }

        /// Per-channel change, in normalized log units, with the puck at the wheel's edge.
        public var chromaScale: Double {
            switch self {
            case .lift, .gamma, .gain: 0.1
            case .offset: 0.06
            }
        }

        /// Master ring range.
        public var masterRange: ClosedRange<Double> {
            switch self {
            case .lift, .gamma, .offset: -0.5...0.5
            case .gain: -0.5...1
            }
        }
    }

    public var x = 0.0
    public var y = 0.0
    public var master = 0.0

    public init(x: Double = 0, y: Double = 0, master: Double = 0) {
        self.x = x
        self.y = y
        self.master = master
    }

    public var isNeutral: Bool { x == 0 && y == 0 && master == 0 }

    /// Per-channel values: master plus a luma-neutral chroma offset (inverse Rec.709 Y'CbCr with Y = 0).
    public func rgb(_ kind: Kind) -> RGB {
        RGB(repeating: master) + Self.chroma(cb: x, cr: y) * kind.chromaScale
    }

    /// The wheel whose `rgb(kind)` is `rgb` (the puck may land outside the unit disk for extreme values).
    public init(rgb: RGB, kind: Kind) {
        let master = simd_dot(rgb, Self.ycbcr.lumaWeights)
        let c = Self.ycbcr.chroma(rgb / kind.chromaScale)
        self.init(x: c.x, y: c.y, master: master)
    }

    /// The vectorscope the wheels are oriented like.
    static let ycbcr = CameraProfile.YCbCrMatrix.rec709

    /// RGB direction of a (Cb, Cr) chroma vector. Also gives the hue drawn at each angle of the wheel.
    public static func chroma(cb: Double, cr: Double) -> RGB { ycbcr.rgb(cb: cb, cr: cr) }
}

/// The primary grade, applied per pixel to log exposure *before* the look (like grading under a LUT
/// in Resolve): the look's film curve then shapes every correction, so pushes stay graceful.
///
/// Wheels work in a normalized log space `t` (0 = 7 stops under mid grey, 1 = 7 stops over), with the
/// classic lift/gamma/gain/offset formulas. Color controls work on log-exposure chroma.
public struct PrimaryGrade: Hashable, Sendable {
    public var lift = RGB.zero
    public var gamma = RGB.zero
    public var gain = RGB.zero
    public var offset = RGB.zero
    /// Log-space contrast multiplier and its pivot (in `t`).
    public var contrast = 1.0
    public var pivot = 0.5
    public var saturation = 1.0
    /// 0…1: extra saturation for muted colors.
    public var colorBoost = 0.0
    /// 0…1: subtractive saturation; saturated colors gain density (get deeper), neutrals are untouched.
    public var density = 0.0
    /// Stops added to shadows / highlights.
    public var shadows = 0.0
    public var highlights = 0.0
    /// Stops added per channel (negative exposure + printer lights).
    public var exposure = RGB.zero

    static let stopsRange = 14.0
    static let stopsFloor = -7.0
    /// Luma ranges (stops) where shadows fade out and highlights fade in.
    static let shadowEdges = (lower: -5.0, upper: 0.5)
    static let highlightEdges = (lower: -0.5, upper: 3.5)
    /// Scales of the color controls: boost for muted colors, and density's deepening and darkening.
    static let boostScale = 1.2
    static let densityDepth = 0.45
    static let densityDarkening = 0.3

    public init() {}

    public init(_ s: GradeSettings) {
        lift = s.lift.rgb(.lift)
        gamma = s.gamma.rgb(.gamma)
        gain = s.gain.rgb(.gain)
        offset = s.offset.rgb(.offset)
        // A pushed negative is also developed longer, which adds contrast and color.
        contrast = pow(2, s.contrast / 100 * 0.6) * (1 + 0.06 * s.push)
        pivot = (s.pivot - Self.stopsFloor) / Self.stopsRange
        saturation = s.saturation / 100 * (1 + 0.04 * s.push)
        colorBoost = s.colorBoost / 100
        density = s.density / 100
        shadows = s.shadows / 100 * 1.5
        highlights = s.highlights / 100 * 1.5

        // Printer lights: complementary pairs in half stops, compensated so overall exposure is preserved.
        var lights = RGB(s.cyanRed, s.magentaGreen, s.yellowBlue) / 100 * 0.5
        lights -= RGB(repeating: simd_dot(lights, WorkingSpace.luminance))
        exposure = lights + RGB(repeating: s.push)
    }

    public var isIdentity: Bool { self == PrimaryGrade() }

    /// Log exposure (stops relative to mid grey, per channel) -> graded log exposure.
    public func apply(_ stops: RGB) -> RGB {
        var e = stops + exposure

        // Wheels and contrast, per channel in normalized log.
        var t = (e - RGB(repeating: Self.stopsFloor)) / Self.stopsRange
        t += lift * (RGB(repeating: 1) - t)
        t *= RGB(repeating: 1) + gain
        t = RGB(Self.gammaCurve(t.x, gamma.x), Self.gammaCurve(t.y, gamma.y), Self.gammaCurve(t.z, gamma.z))
        t += offset
        t = RGB(repeating: pivot) + (t - RGB(repeating: pivot)) * contrast
        e = t * Self.stopsRange + RGB(repeating: Self.stopsFloor)

        // Tonal ranges, hue-preserving (equal stops on every channel).
        let luma = simd_dot(e, WorkingSpace.luminance)
        e += RGB(repeating: shadows * (1 - Self.smoothstep(Self.shadowEdges.lower, Self.shadowEdges.upper, luma))
                 + highlights * Self.smoothstep(Self.highlightEdges.lower, Self.highlightEdges.upper, luma))

        // Color: saturation and boost scale chroma around luminance; density darkens it subtractively.
        let mean = simd_dot(e, WorkingSpace.luminance)
        let chroma = e - RGB(repeating: mean)
        let spread = e.max() - e.min()
        let boost = 1 + colorBoost * Self.boostScale / (1 + spread * spread)
        e = RGB(repeating: mean) + chroma * (saturation * boost)
        return density > 0 ? Self.deepen(e, by: density) : e
    }

    /// Subtractive saturation (0…1), like denser dye: the weaker channels fall most, the whole color darkens
    /// with its saturation, and neutrals (no spread) are untouched.
    static func deepen(_ e: RGB, by density: Double) -> RGB {
        let spread = e.max() - e.min()
        return e + (e - RGB(repeating: e.max())) * (density * densityDepth) - RGB(repeating: density * densityDarkening * spread)
    }

    /// Gamma on normalized log: a power curve between black and white, continued linearly outside.
    static func gammaCurve(_ t: Double, _ g: Double) -> Double {
        guard g != 0, t > 0 else { return t }
        let p = pow(2, -2 * g)
        return t < 1 ? pow(t, p) : 1 + (t - 1) * p
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
