import Foundation

/// Every user-adjustable decision for a clip, stored in UI units (what the controls show).
/// Conversion to physical units happens in one place each: `PrimaryGrade` and `EffectParameters`.
public struct GradeSettings: Codable, Equatable, Sendable {
    // Input
    public var cameraProfileID = CameraProfile.appleLog.id
    public var exposure = 0.0
    public var temperature = 0.0
    public var tint = 0.0

    // Primaries: color wheels and adjustments, applied in log before the look ("under the LUT")
    public var lift = ColorWheel()
    public var gamma = ColorWheel()
    public var gain = ColorWheel()
    public var offset = ColorWheel()
    public var contrast = 0.0
    public var pivot = 0.0
    public var saturation = 100.0
    public var colorBoost = 0.0
    public var density = 0.0
    public var shadows = 0.0
    public var highlights = 0.0

    // Film
    public var stockID = FilmStock.builtIn[0].id
    public var intensity = 100.0
    public var push = 0.0
    public var fade = 0.0

    // Color head (printer lights)
    public var cyanRed = 0.0
    public var magentaGreen = 0.0
    public var yellowBlue = 0.0

    // Texture & light
    public var grain = GrainSettings()
    public var halation = HalationSettings()
    public var bloom = BloomSettings()

    // Output
    public var output = OutputTransform.rec709Apple

    public init() {}

    public var cameraProfile: CameraProfile { CameraProfile.with(id: cameraProfileID) ?? .appleLog }
    public var stock: FilmStock { FilmStock.with(id: stockID) ?? FilmStock.builtIn[0] }

    /// Selects a stock and loads its recommended texture and light settings.
    public mutating func select(_ stock: FilmStock) {
        stockID = stock.id
        grain = stock.grain
        halation = stock.halation
        bloom = stock.bloom
    }

    public subscript(wheel kind: ColorWheel.Kind) -> ColorWheel {
        get {
            switch kind {
            case .lift: lift
            case .gamma: gamma
            case .gain: gain
            case .offset: offset
            }
        }
        set {
            switch kind {
            case .lift: lift = newValue
            case .gamma: gamma = newValue
            case .gain: gain = newValue
            case .offset: offset = newValue
            }
        }
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case cameraProfileID, exposure, temperature, tint
        case lift, gamma, gain, offset, contrast, pivot, saturation, colorBoost, density, shadows, highlights
        case stockID, intensity, push, fade, cyanRed, magentaGreen, yellowBlue
        case grain, halation, bloom, output
    }

    /// Tolerant decoding: keys missing from older projects keep their defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, into value: inout T) throws {
            if let decoded = try c.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        try read(.cameraProfileID, into: &cameraProfileID)
        try read(.exposure, into: &exposure)
        try read(.temperature, into: &temperature)
        try read(.tint, into: &tint)
        try read(.lift, into: &lift)
        try read(.gamma, into: &gamma)
        try read(.gain, into: &gain)
        try read(.offset, into: &offset)
        try read(.contrast, into: &contrast)
        try read(.pivot, into: &pivot)
        try read(.saturation, into: &saturation)
        try read(.colorBoost, into: &colorBoost)
        try read(.density, into: &density)
        try read(.shadows, into: &shadows)
        try read(.highlights, into: &highlights)
        try read(.stockID, into: &stockID)
        try read(.intensity, into: &intensity)
        try read(.push, into: &push)
        try read(.fade, into: &fade)
        try read(.cyanRed, into: &cyanRed)
        try read(.magentaGreen, into: &magentaGreen)
        try read(.yellowBlue, into: &yellowBlue)
        try read(.grain, into: &grain)
        try read(.halation, into: &halation)
        try read(.bloom, into: &bloom)
        try read(.output, into: &output)
    }
}

public struct GrainSettings: Codable, Hashable, Sendable {
    public var enabled = true
    public var amount = 35.0
    public var size = 35.0
    public var softness = 30.0
    public var chroma = 40.0

    public init() {}
    public init(amount: Double, size: Double, softness: Double = 30, chroma: Double = 40) {
        self.amount = amount
        self.size = size
        self.softness = softness
        self.chroma = chroma
    }
}

public struct HalationSettings: Codable, Hashable, Sendable {
    public var enabled = true
    public var amount = 35.0
    public var radius = 35.0
    public var threshold = 50.0
    public var warmth = 50.0

    public init() {}
    public init(amount: Double, radius: Double, threshold: Double = 50, warmth: Double = 50) {
        self.amount = amount
        self.radius = radius
        self.threshold = threshold
        self.warmth = warmth
    }
}

public struct BloomSettings: Codable, Hashable, Sendable {
    public var enabled = true
    public var amount = 25.0
    public var radius = 40.0
    public var threshold = 55.0

    public init() {}
    public init(amount: Double, radius: Double, threshold: Double = 55) {
        self.amount = amount
        self.radius = radius
        self.threshold = threshold
    }
}
