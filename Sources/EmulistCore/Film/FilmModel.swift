import Foundation
import simd

/// Renders scene-linear working-space RGB to display-encoded output RGB through a negative + print model.
///
/// Stages (all per pixel, in this order):
/// 1. Negative exposure: stops relative to mid grey, plus push/pull.
/// 2. Inter-layer crosstalk and color separation, in log exposure (like dye-coupler interimage effects).
/// 3. Negative shoulder: highlights compress asymptotically per channel, so they desaturate gracefully.
/// 4. Printing light balance (stock balance + color head).
/// 5. Print curve per channel: toe, mid-grey contrast, soft roll-off into paper white, black floor.
/// 6. Print saturation, gamut conversion to the output primaries, soft gamut compression.
public struct FilmModel: Sendable {
    public let response: FilmResponse
    public let output: OutputTransform

    private let crosstalk: Matrix3
    private let printAnchor: RGB
    private let toOutput: Matrix3

    public init(response: FilmResponse, output: OutputTransform) {
        self.response = response
        self.output = output
        crosstalk = Matrix3(rows: stride(from: 0, to: 9, by: 3).map {
            SIMD3(response.crosstalk[$0], response.crosstalk[$0 + 1], response.crosstalk[$0 + 2])
        })
        toOutput = WorkingSpace.primaries.conversion(to: output.primaries)
        printAnchor = RGB(
            Self.anchor(response, channel: 0), Self.anchor(response, channel: 1), Self.anchor(response, channel: 2))
    }

    /// Scene-linear working RGB -> display-encoded output RGB in 0...1.
    public func render(_ scene: RGB) -> RGB {
        displayLinear(stops: WorkingSpace.stops(scene)).encoded(output.transfer)
    }

    /// Log exposure (stops relative to mid grey) -> display-linear output RGB in 0...1, gamut mapped.
    public func displayLinear(stops: RGB) -> RGB {
        let r = response
        let mixed = crosstalk * (stops + RGB(repeating: r.exposure))
        let mean = RGB(repeating: simd_dot(mixed, WorkingSpace.luminance))
        var y = printDensity(stops: mean + (mixed - mean) * r.separation)
        let luma = simd_dot(y, WorkingSpace.luminance)
        y = RGB(repeating: luma) + (y - RGB(repeating: luma)) * r.printSaturation
        return simd_clamp(GamutCompression.print.compress(toOutput * y), .zero, RGB(repeating: 1))
    }

    /// Display-linear output of the print, before gamut mapping and encoding (useful for tests and plots).
    public func printDensity(stops e: RGB) -> RGB {
        let r = response
        let negative = RGB(shoulder(e.x), shoulder(e.y), shoulder(e.z)) + r.balance
        return RGB(
            print(negative.x, channel: 0), print(negative.y, channel: 1), print(negative.z, channel: 2))
    }

    // MARK: Negative

    private func shoulder(_ e: Double) -> Double {
        let start = response.shoulderStart
        guard e > start else { return e }
        return start + Curves.softLimit(e - start, limit: response.shoulderRange, hardness: 1.5)
    }

    // MARK: Print

    /// Print curve for one channel: log exposure (stops) -> display-linear light.
    private func print(_ x: Double, channel c: Int) -> Double {
        let r = response
        let k = r.contrast * r.channelContrast[c]
        let t = printAnchor[c] * pow(2, Curves.toeSlope(x, contrast: k, toeContrast: k * r.toe))
        return r.black[c] + (1 - r.black[c]) * Curves.softLimit(t, limit: r.white[c], hardness: r.rolloff)
    }

    /// Linear value at mid grey that, after roll-off and black floor, lands exactly on `midGrey`.
    private static func anchor(_ r: FilmResponse, channel c: Int) -> Double {
        let target = (r.midGrey - r.black[c]) / (1 - r.black[c])
        return Curves.inverseSoftLimit(min(target, r.white[c] * 0.95), limit: r.white[c], hardness: r.rolloff)
    }
}

/// Smooth curve primitives shared by the negative and the print.
enum Curves {
    /// Rational soft clip: ~x for x << limit, approaching `limit` asymptotically.
    static func softLimit(_ x: Double, limit: Double, hardness h: Double) -> Double {
        x / pow(1 + pow(x / limit, h), 1 / h)
    }

    static func inverseSoftLimit(_ y: Double, limit: Double, hardness h: Double) -> Double {
        let q = pow(y / limit, h)
        return limit * pow(q / (1 - q), 1 / h)
    }

    /// Log-log tone line through mid grey with slope `contrast`, easing to `toeContrast` in the shadows.
    static func toeSlope(_ x: Double, contrast k: Double, toeContrast kt: Double) -> Double {
        func softMinZero(_ v: Double) -> Double { -log2(1 + pow(2, -v)) }
        return k * x - (k - kt) * (softMinZero(x) - softMinZero(0))
    }
}

/// Soft gamut compression toward the achromatic axis (after the ACES Reference Gamut Compression idea):
/// colors closer to the axis than `threshold` are untouched; beyond it, distances up to `limit` are rolled
/// smoothly into the gamut.
struct GamutCompression: Sendable {
    let threshold: Double
    let limit: Double
    var power = 1.2

    /// For the print: a gentle, early roll-off that keeps saturated film color smooth.
    static let print = GamutCompression(threshold: 0.8, limit: 1.6)
    /// Before a camera LUT: only colors at the very edge of (or beyond) the camera gamut are touched,
    /// so the LUT sees its intended input everywhere else and never clips flat.
    static let cameraEdge = GamutCompression(threshold: 0.95, limit: 1.5)

    func compress(_ rgb: RGB) -> RGB {
        let achromatic = max(rgb.x, rgb.y, rgb.z)
        guard achromatic > 0 else { return .zero }
        let scale = (limit - threshold) / pow(pow((1 - threshold) / (limit - threshold), -power) - 1, 1 / power)
        func compressed(_ c: Double) -> Double {
            let d = (achromatic - c) / achromatic
            guard d > threshold else { return c }
            let x = (d - threshold) / scale
            let dc = threshold + scale * x / pow(1 + pow(x, power), 1 / power)
            return achromatic - dc * achromatic
        }
        return RGB(compressed(rgb.x), compressed(rgb.y), compressed(rgb.z))
    }
}
