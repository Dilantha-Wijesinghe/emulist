import Foundation
import simd

// GPU-facing uniforms. Layouts mirror the structs in `ShaderSource` (float4-only, so no padding surprises).
// This file is also the single place where UI units become physical units.

struct InputUniforms {
    var ycbcrRows: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var ycbcrNorm: SIMD4<Float>
    var workingRows: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var transfer: SIMD4<Float>
}

struct PrefilterUniforms {
    var thresholds: SIMD4<Float>
    var luminance: SIMD4<Float>
}

struct FilmUniforms {
    var luminance: SIMD4<Float>
    var shaper: SIMD4<Float>
    var bloom: SIMD4<Float>
    var halation: SIMD4<Float>
    var grain: SIMD4<Float>
    var beforeRows: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var compare: SIMD4<Float>
}

extension Matrix3 {
    var rows4: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        func row(_ r: Int) -> SIMD4<Float> { SIMD4(Float(self[0][r]), Float(self[1][r]), Float(self[2][r]), 0) }
        return (row(0), row(1), row(2))
    }
}

extension SIMD3<Double> {
    var float4: SIMD4<Float> { SIMD4(Float(x), Float(y), Float(z), 0) }
}

/// Input stage: camera decode, gamut conversion, exposure and white balance.
public enum InputTransform {
    /// Exposure and white balance applied in the working space (scene-referred, so it behaves like light).
    public static func adjustment(for s: GradeSettings) -> Matrix3 {
        let mired = 1e6 / 6504 - s.temperature * 0.6
        let assumedWhite = ChromaticAdaptation.daylight(kelvin: 1e6 / mired).shiftedV(by: s.tint / 100 * 0.02)
        let p = WorkingSpace.primaries
        let balance = p.rgbToXYZ.inverse * ChromaticAdaptation.bradford(from: assumedWhite, to: p.white) * p.rgbToXYZ
        return balance * pow(2, s.exposure)
    }

    /// Camera linear RGB -> adjusted working-space linear RGB.
    public static func matrix(for s: GradeSettings) -> Matrix3 {
        adjustment(for: s) * s.cameraProfile.primaries.conversion(to: WorkingSpace.primaries)
    }

    /// Y'CbCr -> R'G'B' for a 10-bit video-range signal stored in 16-bit containers ('x422').
    static func ycbcrUniforms(_ matrix: CameraProfile.YCbCrMatrix) -> (rows: Matrix3, norm: SIMD4<Float>) {
        let (kr, kb) = matrix.coefficients
        let kg = 1 - kr - kb
        let rows = Matrix3(rows: [
            [1, 0, 2 * (1 - kr)],
            [1, -2 * kb * (1 - kb) / kg, -2 * kr * (1 - kr) / kg],
            [1, 2 * (1 - kb), 0],
        ])
        let code = 65535.0 / 64.0
        let norm = SIMD4<Float>(Float(code / 876), Float(64.0 / 876), Float(code / 896), Float(512.0 / 896))
        return (rows, norm)
    }

    static func uniforms(_ s: GradeSettings, ycbcr: CameraProfile.YCbCrMatrix) -> InputUniforms {
        let y = ycbcrUniforms(ycbcr)
        return InputUniforms(
            ycbcrRows: y.rows.rows4, ycbcrNorm: y.norm, workingRows: matrix(for: s).rows4,
            transfer: SIMD4(Float(LUTBaker.transferLUTSize), 0, 0, 0))
    }
}

/// Physical parameters of the texture and light effects, resolved for one processing resolution.
/// Sizes are fractions of frame height, so preview and full-resolution export look the same.
public struct EffectParameters: Equatable, Sendable {
    public static let referenceHeight = 1080.0
    /// Light effects are computed at this fraction of the processing resolution.
    public static let lightScale = 0.5

    public var bloomAmount = 0.0, bloomSigma = 0.0, bloomThreshold = 0.0
    public var halationAmount = 0.0, halationSigma = 0.0, halationThreshold = 0.0, halationTint = RGB.zero
    public var grainAmount = 0.0, grainSigma = 0.0, grainChroma = 0.0, grainCanvasHeight = 0.0
    public var softnessSigma = 0.0

    public init(_ s: GradeSettings, height: Double) {
        let lightHeight = height * Self.lightScale
        if s.bloom.enabled, s.bloom.amount > 0 {
            bloomAmount = s.bloom.amount / 100 * 0.6
            bloomSigma = (0.008 + s.bloom.radius / 100 * 0.07) * lightHeight
            bloomThreshold = WorkingSpace.midGrey * pow(2, 0.5 + s.bloom.threshold / 100 * 4.5)
        }
        if s.halation.enabled, s.halation.amount > 0 {
            halationAmount = s.halation.amount / 100 * 0.8
            halationSigma = (0.0015 + s.halation.radius / 100 * 0.012) * lightHeight
            halationThreshold = WorkingSpace.midGrey * pow(2, 1 + s.halation.threshold / 100 * 4)
            let warmth = s.halation.warmth / 100
            halationTint = RGB(1, 0.08 + 0.42 * warmth, 0.02 * warmth)
        }
        if s.grain.enabled, s.grain.amount > 0 {
            grainAmount = s.grain.amount / 100 * 0.38
            grainCanvasHeight = max(height, Self.referenceHeight)
            grainSigma = (0.45 + s.grain.size / 100 * 1.9) * grainCanvasHeight / Self.referenceHeight
            grainChroma = s.grain.chroma / 100
        }
        softnessSigma = s.grain.softness / 100 * 1.6 * height / Self.referenceHeight
    }

    var hasBloom: Bool { bloomAmount > 0 }
    var hasHalation: Bool { halationAmount > 0 }
    var hasGrain: Bool { grainAmount > 0 }
    var hasSoftness: Bool { softnessSigma > 0.3 }

    /// Standard deviation of white noise after a Gaussian blur of `sigma` pixels is 1 / (2·σ·√π).
    var grainNormalization: Double { grainSigma > 0.5 ? 2 * grainSigma * Double.pi.squareRoot() : 1 }
}
