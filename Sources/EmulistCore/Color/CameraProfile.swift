import Foundation

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
    public static let rec709 = CameraProfile(
        id: "rec709", name: "Rec.709 (Standard Video)", transfer: .gamma24, primaries: .rec709,
        defaultMatrix: .rec709)

    public static let all: [CameraProfile] = [.appleLog, .sLog3, .vLog, .rec709]

    public static func with(id: String) -> CameraProfile? { all.first { $0.id == id } }
}

/// The delivery encoding. Each case pairs an encoding with the color space the preview is tagged with,
/// so the viewer shows exactly what a color-managed player will show for the exported file.
public enum OutputTransform: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Rec.709 encoded with the BT.709 OETF. macOS and iOS decode this exactly, so the export looks
    /// identical in QuickTime, Photos, Safari and on iPhone.
    case rec709Apple
    /// Rec.709 encoded for a gamma 2.4 reference display (broadcast / Resolve convention).
    case rec709Gamma24

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .rec709Apple: "Rec.709 · Apple & Web"
        case .rec709Gamma24: "Rec.709 · Gamma 2.4"
        }
    }

    public var transfer: TransferFunction {
        switch self {
        case .rec709Apple: .bt709
        case .rec709Gamma24: .gamma24
        }
    }

    public var primaries: ColorPrimaries { .rec709 }
}
