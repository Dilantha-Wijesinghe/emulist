import Foundation
import simd

/// The arithmetic behind Emulist's tactile controls, kept free of UI so it can be tested.
///
/// Every control drags *relatively* (the value moves with the pointer's travel, never jumps to it),
/// and its default value is a sticky detent: a small dead zone the value rests in until the pointer
/// has moved past it. The dead zone lives in "travel" space, so leaving it never makes the value jump.
public enum DragMath {
    /// Fine adjustment (⌥) moves this much slower.
    public static let fineFactor = 0.1

    /// The value after dragging `travel` points from `start`, where `pointsPerRange` points sweep the
    /// whole range. `detentWidth` is the dead zone around `detent`, as a fraction of the range.
    public static func value(
        from start: Double, travel: Double, range: ClosedRange<Double>, pointsPerRange: Double,
        fine: Bool = false, detent: Double? = nil, detentWidth: Double = 0.015
    ) -> Double {
        let span = range.upperBound - range.lowerBound
        let delta = travel / pointsPerRange * span * (fine ? fineFactor : 1)
        guard let detent else { return clamp(start + delta, range) }
        let width = detentWidth * span
        let raw = expand(start - detent, width) + delta
        return clamp(detent + collapse(raw, width), range)
    }

    /// A puck in the unit disk moved by `delta` (in disk radii), with a sticky detent at the center.
    public static func puck(from start: SIMD2<Double>, delta: SIMD2<Double>, fine: Bool = false,
                            detentRadius: Double = 0.03) -> SIMD2<Double> {
        let scaled = delta * (fine ? fineFactor : 1)
        let length = simd_length(start)
        let rawStart = length > 0 ? start / length * expand(length, detentRadius) : start
        let raw = rawStart + scaled
        let rawLength = simd_length(raw)
        guard rawLength > 0 else { return .zero }
        let collapsed = min(collapse(rawLength, detentRadius), 1)
        return raw / rawLength * collapsed
    }

    /// Whether moving from `a` to `b` arrived at or crossed `detent` (for a haptic click).
    public static func reached(_ detent: Double, from a: Double, to b: Double) -> Bool {
        a != detent && (b == detent || (a - detent) * (b - detent) < 0)
    }

    // Dead zone of half-width `w` around zero: travel → value and its inverse.
    private static func collapse(_ x: Double, _ w: Double) -> Double { x > w ? x - w : x < -w ? x + w : 0 }
    private static func expand(_ x: Double, _ w: Double) -> Double { x > 0 ? x + w : x < 0 ? x - w : 0 }

    private static func clamp(_ x: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
