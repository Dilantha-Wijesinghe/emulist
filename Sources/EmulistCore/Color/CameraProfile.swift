import Foundation
import simd

/// How a camera encodes its image: transfer function, gamut and the Y'CbCr matrix it records with.
public struct CameraProfile: Identifiable, Hashable, Sendable {
    public enum YCbCrMatrix: String, Codable, Sendable {
        case rec709, rec2020

        /// (Kr, Kb) luma coefficients.
        var coefficients: (kr: Double, kb: Double) {
            switch self {
            case .rec709: (0.2126, 0.0722)
            case .rec2020: (0.2627, 0.0593)
            }
        }

        /// Y' weights of R', G' and B'.
        public var lumaWeights: RGB {
            let (kr, kb) = coefficients
            return RGB(kr, 1 - kr - kb, kb)
        }

        /// (Cb, Cr) of an R'G'B' signal: each within ±0.5 for colors inside the cube.
        public func chroma(_ rgb: RGB) -> SIMD2<Double> {
            let (kr, kb) = coefficients
            let y = simd_dot(rgb, lumaWeights)
            return SIMD2((rgb.z - y) / (2 * (1 - kb)), (rgb.x - y) / (2 * (1 - kr)))
        }

        /// The R'G'B' offset of a (Cb, Cr) chroma at zero Y': the inverse of `chroma`.
        public func rgb(cb: Double, cr: Double) -> RGB {
            let (kr, kb) = coefficients
            let r = 2 * (1 - kr) * cr
            let b = 2 * (1 - kb) * cb
            return RGB(r, -(kr * r + kb * b) / (1 - kr - kb), b)
        }
    }

    public let id: String
    public let name: String
    public let transfer: TransferFunction
    public let primaries: ColorPrimaries
    public let defaultMatrix: YCbCrMatrix

    public static let appleLog = CameraProfile(
        id: "apple-log", name: "Apple Log", transfer: .appleLog, primaries: .rec2020, defaultMatrix: .rec2020)
    public static let sLog3 = CameraProfile(
        id: "sony-slog3-sgamut3cine", name: "Sony S-Log3 / S-Gamut3.Cine", transfer: .sLog3,
        primaries: .sGamut3Cine, defaultMatrix: .rec709)
    public static let vLog = CameraProfile(
        id: "panasonic-vlog", name: "Panasonic V-Log / V-Gamut", transfer: .vLog, primaries: .vGamut,
        defaultMatrix: .rec709)
    public static let fLog = CameraProfile(
        id: "fujifilm-flog", name: "Fujifilm F-Log / F-Gamut", transfer: .fLog, primaries: .fGamut,
        defaultMatrix: .rec709)
    public static let fLog2 = CameraProfile(
        id: "fujifilm-flog2", name: "Fujifilm F-Log2 / F-Gamut", transfer: .fLog2, primaries: .fGamut,
        defaultMatrix: .rec709)
    public static let rec709 = CameraProfile(
        id: "rec709", name: "Rec.709 (Standard Video)", transfer: .gamma24, primaries: .rec709,
        defaultMatrix: .rec709)

    public static let all: [CameraProfile] = [.appleLog, .sLog3, .vLog, .fLog, .fLog2, .rec709]

    public static func with(id: String) -> CameraProfile? { all.first { $0.id == id } }
}

/// The delivery encoding. Both cases show the same image in Emulist's viewer; they differ in which players
/// reproduce it exactly. The file is tagged Rec.709 (1-1-1) either way.
public enum OutputTransform: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Encoded for Apple's video pipeline, which decodes Rec.709 with gamma ≈ 1.961: QuickTime, Photos,
    /// Safari, iPhone and iPad show exactly what the viewer shows.
    case rec709Apple
    /// Encoded for a gamma 2.4 reference display (broadcast, DaVinci Resolve convention).
    case rec709Gamma24

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .rec709Apple: "Rec.709 · Apple Devices"
        case .rec709Gamma24: "Rec.709 · Gamma 2.4"
        }
    }

    public var detail: String {
        switch self {
        case .rec709Apple: "Looks exactly like the viewer on Mac, iPhone and iPad."
        case .rec709Gamma24: "Broadcast and grading-suite standard. Appears lighter in QuickTime."
        }
    }

    public var transfer: TransferFunction {
        switch self {
        case .rec709Apple: .gamma1961
        case .rec709Gamma24: .gamma24
        }
    }

    var displayGamma: Double {
        switch self {
        case .rec709Apple: 1.961
        case .rec709Gamma24: 2.4
        }
    }

    public var primaries: ColorPrimaries { .rec709 }
}
