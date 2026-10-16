import Foundation

/// A film look: the tonal and color response of a negative printed to a positive, plus recommended
/// texture and light settings. Stocks are pure data (Codable), so new looks need no code changes.
public struct FilmStock: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var format: String
    public var summary: String
    public var response: FilmResponse
    public var grain: GrainSettings
    public var halation: HalationSettings
    public var bloom: BloomSettings

    public static func with(id: String) -> FilmStock? { builtIn.first { $0.id == id } }
}

/// The numeric model of a negative + print. Every field interpolates linearly, which is how film
/// intensity works: the response is blended toward `.neutral`, never the rendered pixels.
///
/// Log-exposure values are in stops relative to scene mid grey (0.18).
public struct FilmResponse: Codable, Hashable, Sendable {
    // Negative
    /// Exposure given to the negative, in stops (push/pull lives here).
    public var exposure: Double
    /// Inter-layer crosstalk in log exposure (row-major 3×3, rows sum to 1). Shapes hue character.
    public var crosstalk: [Double]
    /// Log-domain color separation around luminance. 1 = neutral, > 1 = richer color.
    public var separation: Double
    /// Stops above mid grey where the negative begins compressing highlights.
    public var shoulderStart: Double
    /// Stops above `shoulderStart` the compressed highlights approach asymptotically.
    public var shoulderRange: Double
    /// Per-channel color balance of the negative / printing light, in stops.
    public var balance: RGB

    // Print
    /// Display contrast at mid grey (log-log slope).
    public var contrast: Double
    /// Per-channel contrast multipliers; differences create cross-over tints in shadows vs highlights.
    public var channelContrast: RGB
    /// Contrast in the deep shadows relative to `contrast` (< 1 = softer, more open toe).
    public var toe: Double
    /// Hardness of the print's highlight roll-off into paper white (higher = later, crisper).
    public var rolloff: Double
    /// Display-linear luminance of scene mid grey.
    public var midGrey: Double
    /// Display-linear black floor per channel (print Dmax / matte lift).
    public var black: RGB
    /// Display-linear white per channel (base/paper white).
    public var white: RGB
    /// Saturation of the final print, around luminance.
    public var printSaturation: Double

    public static let neutral = FilmResponse(
        exposure: 0, crosstalk: [1, 0, 0, 0, 1, 0, 0, 0, 1], separation: 1, shoulderStart: 3.5, shoulderRange: 5,
        balance: .zero, contrast: 1.45, channelContrast: [1, 1, 1], toe: 0.85, rolloff: 1.6, midGrey: 0.16,
        black: .zero, white: [1, 1, 1], printSaturation: 1)

    public func mixed(with other: FilmResponse, amount t: Double) -> FilmResponse {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func mix(_ a: RGB, _ b: RGB) -> RGB { a + (b - a) * t }
        return FilmResponse(
            exposure: mix(exposure, other.exposure),
            crosstalk: zip(crosstalk, other.crosstalk).map { mix($0, $1) },
            separation: mix(separation, other.separation),
            shoulderStart: mix(shoulderStart, other.shoulderStart),
            shoulderRange: mix(shoulderRange, other.shoulderRange),
            balance: mix(balance, other.balance),
            contrast: mix(contrast, other.contrast),
            channelContrast: mix(channelContrast, other.channelContrast),
            toe: mix(toe, other.toe),
            rolloff: mix(rolloff, other.rolloff),
            midGrey: mix(midGrey, other.midGrey),
            black: mix(black, other.black),
            white: mix(white, other.white),
            printSaturation: mix(printSaturation, other.printSaturation))
    }
}

extension FilmResponse {
    /// The response for a grade: the stock blended by intensity, then the user's film controls.
    public init(for settings: GradeSettings) {
        self = FilmResponse.neutral.mixed(with: settings.stock.response, amount: settings.intensity / 100)
        apply(settings)
    }

    private mutating func apply(_ s: GradeSettings) {
        // Push/pull: a pushed negative is also developed longer, which adds contrast and color.
        exposure += s.push
        contrast *= 1 + 0.06 * s.push
        separation *= 1 + 0.04 * s.push

        contrast *= pow(2, s.contrast / 100 * 0.6)
        separation *= s.saturation / 100
        printSaturation *= 0.5 + 0.5 * min(s.saturation / 100, 1.5)

        // Highlights: positive values compress earlier and softer (more "negative-like" latitude).
        shoulderStart -= s.highlights / 100 * 1.5
        rolloff *= pow(2, -s.highlights / 100 * 0.7)

        // Fade lifts the print black and opens the toe like a matte print.
        let fade = s.fade / 100
        black += RGB(repeating: fade * 0.06)
        toe *= 1 - 0.35 * fade

        // Printer lights: complementary pairs, compensated so overall exposure is preserved.
        var lights = RGB(s.cyanRed, s.magentaGreen, s.yellowBlue) / 100 * 0.5
        lights -= RGB(repeating: (lights * WorkingSpace.luminance).sum())
        balance += lights
    }
}
