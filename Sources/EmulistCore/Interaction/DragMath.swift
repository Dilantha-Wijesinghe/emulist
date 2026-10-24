import Foundation
import simd

/// The arithmetic behind Emulist's tactile controls, kept free of UI so it can be tested.
///
/// Every control moves *relatively* (the value follows the pointer's travel, never jumps to it), event
/// by event, so pressing ⌥ mid-drag slows the control from that point on. A control's default value is
/// a sticky detent: arriving there parks the value until the pointer has pushed a few points past it.
/// The detent is measured in pointer points, so it is equally narrow under the finger in fine mode.
public enum DragMath {
    /// Fine adjustment (⌥) moves this much slower.
    public static let fineFactor = 0.1

    /// One single-value control during a gesture.
    public struct Dial: Sendable {
        public private(set) var value: Double
        let range: ClosedRange<Double>
        let pointsPerRange: Double
        public let detent: Double?
        /// Pointer points it takes to leave the detent.
        let holdPoints: Double
        /// Pointer points pushed into the detent so far (signed).
        private var held = 0.0

        /// `detentWidth` is the dead zone as a fraction of the full sweep, in pointer travel.
        public init(value: Double, range: ClosedRange<Double>, pointsPerRange: Double, detent: Double? = nil,
                    detentWidth: Double = 0.015) {
            self.value = min(max(value, range.lowerBound), range.upperBound)
            self.range = range
            self.pointsPerRange = pointsPerRange
            self.detent = detent
            holdPoints = detentWidth * pointsPerRange
        }

        /// Moves by `points` of pointer travel (positive increases the value).
        public mutating func move(_ points: Double, fine: Bool = false) {
            let scale = (range.upperBound - range.lowerBound) / pointsPerRange * (fine ? fineFactor : 1)
            var points = points
            if let detent, value == detent {
                held += points
                guard abs(held) > holdPoints else { return }
                points = held - (held > 0 ? holdPoints : -holdPoints)
                held = 0
            }
            let next = value + points * scale
            if let detent, value != detent, (value - detent) * (next - detent) <= 0 {
                // Arrived at or crossed the default: park there, banking the overshoot toward leaving it.
                value = detent
                held = 0
                move((next - detent) / scale, fine: fine)
                return
            }
            value = min(max(next, range.lowerBound), range.upperBound)
        }
    }

    /// A puck in the unit disk moved by `delta` (in disk radii), with a sticky detent at the center.
    /// Callers scale `detentRadius` with their speed so the detent feels the same at every speed.
    public static func puck(from start: SIMD2<Double>, delta: SIMD2<Double>, detentRadius: Double = 0.03) -> SIMD2<Double> {
        let length = simd_length(start)
        let rawStart = length > 0 ? start / length * expand(length, detentRadius) : start
        let raw = rawStart + delta
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
}
