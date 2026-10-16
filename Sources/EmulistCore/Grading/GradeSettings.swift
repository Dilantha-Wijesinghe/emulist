import Foundation

/// Every user-adjustable decision for a clip, stored in UI units (what the sliders show).
/// Conversion to physical units happens in one place: `FilmResponse.applying(_:)` and `EffectParameters`.
public struct GradeSettings: Codable, Equatable, Sendable {
    // Input
    public var cameraProfileID = CameraProfile.appleLog.id
    public var exposure = 0.0
    public var temperature = 0.0
    public var tint = 0.0

    // Film
    public var stockID = FilmStock.builtIn[0].id
    public var intensity = 100.0
    public var push = 0.0
    public var contrast = 0.0
    public var saturation = 100.0
    public var highlights = 0.0
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
    public var output = OutputTransform.rec709Gamma24

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
