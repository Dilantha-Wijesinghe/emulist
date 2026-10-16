import Foundation

/// Opto-electronic transfer functions. `decode` maps a normalized code value (0...1) to linear light,
/// `encode` is its inverse. Constants come from the respective vendor documents; none are invented.
public enum TransferFunction: String, Codable, CaseIterable, Sendable {
    case appleLog
    case sLog3
    case vLog
    /// Display-referred Rec.709 video, interpreted through the BT.1886 (gamma 2.4) EOTF.
    case gamma24
    /// The effective gamma Apple's video pipeline (AVFoundation, QuickTime, Photos, Safari) applies to
    /// Rec.709-tagged video. Measured on macOS 26: matches a 1.961 power within 1%.
    case gamma1961
    /// ITU-R BT.709 OETF.
    case bt709
    case linear

    public func decode(_ v: Double) -> Double {
        switch self {
        case .appleLog: AppleLog.decode(v)
        case .sLog3: SLog3.decode(v)
        case .vLog: VLog.decode(v)
        case .gamma24: pow(max(v, 0), 2.4)
        case .gamma1961: pow(max(v, 0), 1.961)
        case .bt709: v < 4.5 * 0.018 ? v / 4.5 : pow((v + 0.099) / 1.099, 1 / 0.45)
        case .linear: v
        }
    }

    public func encode(_ l: Double) -> Double {
        switch self {
        case .appleLog: AppleLog.encode(l)
        case .sLog3: SLog3.encode(l)
        case .vLog: VLog.encode(l)
        case .gamma24: pow(max(l, 0), 1 / 2.4)
        case .gamma1961: pow(max(l, 0), 1 / 1.961)
        case .bt709: l < 0.018 ? 4.5 * l : 1.099 * pow(l, 0.45) - 0.099
        case .linear: l
        }
    }
}

/// Apple Log profile (Apple, "Apple Log Profile White Paper", 2023).
enum AppleLog {
    static let r0 = -0.05641088
    static let rt = 0.01
    static let c = 47.28711236
    static let beta = 0.00964052
    static let gamma = 0.08550479
    static let delta = 0.69336945
    static let pt = c * (rt - r0) * (rt - r0)

    static func encode(_ r: Double) -> Double {
        if r >= rt { return gamma * log2(r + beta) + delta }
        if r >= r0 { return c * (r - r0) * (r - r0) }
        return 0
    }

    static func decode(_ p: Double) -> Double {
        if p >= pt { return pow(2, (p - delta) / gamma) - beta }
        if p >= 0 { return (p / c).squareRoot() + r0 }
        return r0
    }
}

/// Sony S-Log3 (Sony, "Technical Summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3").
enum SLog3 {
    private static let cut = 171.2102946929 / 1023

    static func decode(_ v: Double) -> Double {
        v >= cut
            ? pow(10, (v * 1023 - 420) / 261.5) * (0.18 + 0.01) - 0.01
            : (v * 1023 - 95) * 0.01125 / (171.2102946929 - 95)
    }

    static func encode(_ l: Double) -> Double {
        l >= 0.01125
            ? (420 + log10((l + 0.01) / (0.18 + 0.01)) * 261.5) / 1023
            : (l * (171.2102946929 - 95) / 0.01125 + 95) / 1023
    }
}

/// Panasonic V-Log (Panasonic, "V-Log/V-Gamut Reference Manual").
enum VLog {
    private static let b = 0.00873, c = 0.241514, d = 0.598206

    static func decode(_ v: Double) -> Double {
        v < 0.181 ? (v - 0.125) / 5.6 : pow(10, (v - d) / c) - b
    }

    static func encode(_ l: Double) -> Double {
        l < 0.01 ? 5.6 * l + 0.125 : c * log10(l + b) + d
    }
}

extension SIMD3<Double> {
    public func decoded(_ transfer: TransferFunction) -> Self {
        Self(transfer.decode(x), transfer.decode(y), transfer.decode(z))
    }

    public func encoded(_ transfer: TransferFunction) -> Self {
        Self(transfer.encode(x), transfer.encode(y), transfer.encode(z))
    }
}
