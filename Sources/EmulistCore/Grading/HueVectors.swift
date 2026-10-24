import Foundation
import simd

/// Hue-selective color, like Resolve's ColorSlice: six vectors (red, yellow, green, cyan, blue, magenta),
/// each turning, saturating or deepening only the colors around its hue. Hues between two vectors blend
/// their settings smoothly, and neutrals are never touched.
///
/// Works on log-exposure chroma after the primary grade, before the look, and is baked into the look LUT.
public struct HueVectors: Codable, Hashable, Sendable {
    public enum Vector: String, CaseIterable, Identifiable, Sendable {
        /// In order around the vectorscope, counter-clockwise: each one's + Hue turns it toward the next.
        case red, yellow, green, cyan, blue, magenta

        public var id: String { rawValue }
        public var name: String { rawValue.capitalized }

        /// The vector's color (display-referred, for drawing).
        public var rgb: RGB {
            switch self {
            case .red: RGB(1, 0, 0)
            case .yellow: RGB(1, 1, 0)
            case .green: RGB(0, 1, 0)
            case .cyan: RGB(0, 1, 1)
            case .blue: RGB(0, 0, 1)
            case .magenta: RGB(1, 0, 1)
            }
        }

        public var next: Vector { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
        public var previous: Vector { Self.allCases[(Self.allCases.firstIndex(of: self)! + 5) % Self.allCases.count] }
    }

    public struct Adjustment: Codable, Hashable, Sendable {
        /// −100…100: turns these colors toward the previous (−) or next (+) vector, up to `maxTurn`.
        public var hue = 0.0
        /// −100…100: percent more (or less) saturation.
        public var saturation = 0.0
        /// 0…100: subtractive saturation for these colors only, like the Density control.
        public var density = 0.0

        public init(hue: Double = 0, saturation: Double = 0, density: Double = 0) {
            self.hue = hue
            self.saturation = saturation
            self.density = density
        }

        public var isNeutral: Bool { self == Adjustment() }

        func mixed(with other: Adjustment, _ t: Double) -> Adjustment {
            Adjustment(hue: hue + (other.hue - hue) * t, saturation: saturation + (other.saturation - saturation) * t,
                       density: density + (other.density - density) * t)
        }

        func scaled(_ s: Double) -> Adjustment { Adjustment(hue: hue * s, saturation: saturation * s, density: density * s) }
    }

    public var red = Adjustment()
    public var yellow = Adjustment()
    public var green = Adjustment()
    public var cyan = Adjustment()
    public var blue = Adjustment()
    public var magenta = Adjustment()
    /// 0…100: how much skin tones are spared from the vectors.
    public var protectSkin = 0.0

    public init() {}

    public subscript(vector: Vector) -> Adjustment {
        get {
            switch vector {
            case .red: red
            case .yellow: yellow
            case .green: green
            case .cyan: cyan
            case .blue: blue
            case .magenta: magenta
            }
        }
        set {
            switch vector {
            case .red: red = newValue
            case .yellow: yellow = newValue
            case .green: green = newValue
            case .cyan: cyan = newValue
            case .blue: blue = newValue
            case .magenta: magenta = newValue
            }
        }
    }

    public var isNeutral: Bool { Vector.allCases.allSatisfy { self[$0].isNeutral } }

    /// The hue turn at ±100.
    static let maxTurn = 30.0 * .pi / 180
    /// Chroma is measured in log exposure with the working space's luma, so luminance never changes.
    static let plane = CameraProfile.YCbCrMatrix.rec2020
    /// Each vector's hue angle in that plane, unwrapped so they increase in `Vector` order.
    static let angles: [Double] = Vector.allCases.reduce(into: []) { angles, vector in
        var angle = hueAngle(of: plane.chroma(vector.rgb))
        while let last = angles.last, angle <= last { angle += 2 * .pi }
        angles.append(angle)
    }
    /// The hue of skin, from a typical skin tone (sRGB 0.87, 0.67, 0.55) in scene-linear Rec.2020, and how
    /// wide (radians) the protection reaches either side of it.
    static let skinAngle = hueAngle(of: plane.chroma(WorkingSpace.stops(
        ColorPrimaries.rec709.conversion(to: WorkingSpace.primaries) * RGB(0.87, 0.67, 0.55).decoded(.gamma24))))
    static let skinWidth = 25.0 * .pi / 180

    static func hueAngle(of chroma: SIMD2<Double>) -> Double { atan2(chroma.y, chroma.x) }

    /// The adjustment for colors of hue `angle`: the two nearest vectors' settings, blended smoothly,
    /// with skin tones spared by `protectSkin`.
    func adjustment(at angle: Double) -> Adjustment {
        let angles = Self.angles
        var a = angle
        while a < angles[0] { a += 2 * .pi }
        while a >= angles[0] + 2 * .pi { a -= 2 * .pi }
        let i = angles.lastIndex { $0 <= a }!
        let upper = i + 1 < angles.count ? angles[i + 1] : angles[0] + 2 * .pi
        let t = PrimaryGrade.smoothstep(0, 1, (a - angles[i]) / (upper - angles[i]))
        let vectors = Vector.allCases
        let blended = self[vectors[i]].mixed(with: self[vectors[(i + 1) % vectors.count]], t)
        guard protectSkin > 0 else { return blended }
        var distance = abs(angle - Self.skinAngle).truncatingRemainder(dividingBy: 2 * .pi)
        distance = min(distance, 2 * .pi - distance)
        return blended.scaled(1 - protectSkin / 100 * exp(-pow(distance / Self.skinWidth, 2)))
    }

    /// Log exposure (stops per channel) -> the same luminance with its color adjusted by hue.
    public func apply(_ e: RGB) -> RGB {
        let y = simd_dot(e, Self.plane.lumaWeights)
        let chroma = Self.plane.chroma(e)
        let a = adjustment(at: Self.hueAngle(of: chroma))
        guard !a.isNeutral else { return e }
        let turn = a.hue / 100 * Self.maxTurn
        let turned = SIMD2(chroma.x * cos(turn) - chroma.y * sin(turn), chroma.x * sin(turn) + chroma.y * cos(turn))
            * max(0, 1 + a.saturation / 100)
        let out = RGB(repeating: y) + Self.plane.rgb(cb: turned.x, cr: turned.y)
        return a.density > 0 ? PrimaryGrade.deepen(out, by: a.density / 100) : out
    }
}
