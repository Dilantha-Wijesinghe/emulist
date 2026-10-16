import Foundation

/// The single internal processing convention: scene-referred linear light with Rec.2020 primaries and
/// a D65 white, where 0.18 is mid grey. Values above 1 (highlights) and below 0 are preserved.
///
/// Between the GPU and the film LUT, linear values travel through a log "shaper" so the LUT covers
/// `shaperRange` stops around mid grey with even precision per stop.
public enum WorkingSpace {
    public static let primaries = ColorPrimaries.rec2020
    public static let luminance = primaries.luminanceWeights
    public static let midGrey = 0.18
    public static let shaperRange: ClosedRange<Double> = -11...9

    /// Stops relative to mid grey -> normalized LUT coordinate.
    public static func shaperCoordinate(stops: Double) -> Double {
        (stops - shaperRange.lowerBound) / (shaperRange.upperBound - shaperRange.lowerBound)
    }

    /// Normalized LUT coordinate -> stops relative to mid grey.
    public static func stops(shaperCoordinate s: Double) -> Double {
        shaperRange.lowerBound + s * (shaperRange.upperBound - shaperRange.lowerBound)
    }
}
