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

    /// Scene-linear RGB -> stops relative to mid grey, floored at the bottom of the shaper range.
    public static func stops(_ scene: RGB) -> RGB {
        let floor = midGrey * pow(2, shaperRange.lowerBound)
        return RGB(log2(max(scene.x, floor) / midGrey), log2(max(scene.y, floor) / midGrey),
                   log2(max(scene.z, floor) / midGrey))
    }

    /// Stops relative to mid grey -> scene-linear RGB.
    public static func linear(stops: RGB) -> RGB {
        RGB(midGrey * pow(2, stops.x), midGrey * pow(2, stops.y), midGrey * pow(2, stops.z))
    }

    /// Stops relative to mid grey -> normalized LUT coordinate.
    public static func shaperCoordinate(stops: Double) -> Double {
        (stops - shaperRange.lowerBound) / (shaperRange.upperBound - shaperRange.lowerBound)
    }

    /// Normalized LUT coordinate -> stops relative to mid grey.
    public static func stops(shaperCoordinate s: Double) -> Double {
        shaperRange.lowerBound + s * (shaperRange.upperBound - shaperRange.lowerBound)
    }
}
