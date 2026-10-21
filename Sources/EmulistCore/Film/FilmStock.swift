import Foundation

/// A look: either Emulist's negative + print model (`response`) or an external 3D LUT (`lut`), plus
/// recommended texture and light settings. Looks are pure data, so new ones need no code changes.
public struct FilmStock: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var format: String
    public var summary: String
    /// Library grouping, e.g. "Emulist Film" or "Fujifilm".
    public var collection = FilmStock.emulistCollection
    public var response: FilmResponse
    /// When set, the look is this LUT instead of `response`.
    public var lut: LUTSource? = nil
    public var grain: GrainSettings
    public var halation: HalationSettings
    public var bloom: BloomSettings

    public static let emulistCollection = "Emulist Film"

    public static func with(id: String) -> FilmStock? { LookLibrary.shared.stock(id: id) }
}

/// An external `.cube` LUT and the camera encoding it expects as input. Its output is taken to be
/// Rec.709 video for a gamma 2.4 display, the convention for camera and creative LUTs.
public struct LUTSource: Codable, Hashable, Sendable {
    public var url: URL
    public var inputProfileID: String

    public init(url: URL, inputProfileID: String) {
        self.url = url
        self.inputProfileID = inputProfileID
    }

    public var inputProfile: CameraProfile { CameraProfile.with(id: inputProfileID) ?? .appleLog }
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
        balance: .zero, contrast: 1.7, channelContrast: [1, 1, 1], toe: 0.85, rolloff: 1.0, midGrey: 0.16,
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
    /// The response for a grade: the stock blended toward neutral by intensity.
    public init(for settings: GradeSettings) {
        self = FilmResponse.neutral.mixed(with: settings.stock.response, amount: settings.intensity / 100)
    }
}
