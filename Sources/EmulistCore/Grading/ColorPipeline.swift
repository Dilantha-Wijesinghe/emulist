import Foundation
import simd

/// Everything the baked 3D LUT encodes, as a value: primary grade → look → fade → output encoding.
/// It is `Hashable`, so it doubles as the cache key for baked LUTs.
public struct ColorPipeline: Hashable, Sendable {
    public enum Look: Hashable, Sendable {
        /// Emulist's negative + print model (intensity is already blended into the response).
        case film(FilmResponse)
        /// An external LUT, blended with the neutral film by `intensity` (0…1).
        case lut(LUTSource, intensity: Double)
    }

    public var grade: PrimaryGrade
    public var look: Look
    /// 0…1: lifts the print black like a matte print.
    public var fade: Double
    public var output: OutputTransform

    public init(_ settings: GradeSettings) {
        grade = PrimaryGrade(settings)
        let stock = settings.stock
        look = stock.lut.map { .lut($0, intensity: settings.intensity / 100) } ?? .film(FilmResponse(for: settings))
        fade = settings.fade / 100
        output = settings.output
    }

    /// The ungraded "before" image: neutral film, no corrections.
    public static func neutral(output: OutputTransform) -> ColorPipeline {
        var settings = GradeSettings()
        settings.output = output
        var pipeline = ColorPipeline(settings)
        pipeline.look = .film(.neutral)
        return pipeline
    }

    /// Resolves the pipeline into something that can render pixels (loading the LUT if there is one).
    public func makeRenderer() throws -> Renderer {
        let lut: Renderer.LUTStage? = try {
            guard case .lut(let source, let intensity) = look else { return nil }
            let profile = source.inputProfile
            return Renderer.LUTStage(
                cube: try LookLibrary.shared.cube(for: source), transfer: profile.transfer,
                toInput: WorkingSpace.primaries.conversion(to: profile.primaries), intensity: intensity)
        }()
        let response: FilmResponse = if case .film(let response) = look { response } else { .neutral }
        return Renderer(grade: grade, film: FilmModel(response: response, output: output), lut: lut,
                        fade: fade, output: output)
    }

    public struct Renderer: Sendable {
        struct LUTStage: Sendable {
            let cube: CubeLUT
            let transfer: TransferFunction
            let toInput: Matrix3
            let intensity: Double

            /// Log exposure -> the LUT's display-linear Rec.709 output (its signal is for a gamma 2.4 display).
            /// Colors pushed outside the camera gamut are rolled back in first, so the LUT never clips them flat.
            func displayLinear(stops: RGB) -> RGB {
                let code = GamutCompression.compress(toInput * WorkingSpace.linear(stops: stops)).encoded(transfer)
                return simd_clamp(cube.sample(code), .zero, RGB(repeating: 1)).decoded(.gamma24)
            }
        }

        let grade: PrimaryGrade
        let film: FilmModel
        let lut: LUTStage?
        let fade: Double
        let output: OutputTransform

        /// Scene-linear working RGB -> display-encoded output RGB in 0...1.
        public func render(_ scene: RGB) -> RGB {
            var stops = WorkingSpace.stops(scene)
            if !grade.isIdentity { stops = grade.apply(stops) }
            var light: RGB
            if let lut {
                light = lut.displayLinear(stops: stops)
                if lut.intensity < 1 {
                    let neutral = film.displayLinear(stops: stops)
                    light = neutral + (light - neutral) * lut.intensity
                }
            } else {
                light = film.displayLinear(stops: stops)
            }
            let black = fade * 0.06
            light = RGB(repeating: black) + light * (1 - black)
            return light.encoded(output.transfer)
        }
    }
}
