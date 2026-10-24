import Testing
import simd
@testable import EmulistCore

@Suite struct HueVectorTests {
    /// Log-exposure colors around the hue circle (plus neutrals), at a few exposures.
    static let colors: [RGB] = [-3.0, 0, 2].flatMap { stop in
        [RGB(1.2, -0.4, -0.8), RGB(0.8, 0.7, -1), RGB(-0.6, 0.9, -0.5), RGB(-0.9, 0.3, 0.6), RGB(-0.5, -0.4, 1.1),
         RGB(0.7, -0.8, 0.6), RGB(0.35, 0, -0.35), .zero].map { $0 + RGB(repeating: stop) }
    }

    static func hue(_ e: RGB) -> Double { HueVectors.hueAngle(of: HueVectors.plane.chroma(e)) }

    @Test func neutralVectorsChangeNothing() {
        #expect(HueVectors().isNeutral)
        for e in Self.colors { #expect(HueVectors().apply(e) == e) }
        var protecting = HueVectors()
        protecting.protectSkin = 100
        #expect(protecting.isNeutral)
    }

    @Test func vectorsRunAroundTheCircleInOrder() {
        let angles = HueVectors.angles
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 < $1 })
        #expect(angles.last! - angles.first! < 2 * .pi)
        // Each vector's own color sits exactly on its angle.
        for (vector, angle) in zip(HueVectors.Vector.allCases, angles) {
            let d = remainder(Self.hue(vector.rgb) - angle, 2 * .pi)
            #expect(abs(d) < 1e-9)
        }
    }

    @Test func aVectorLeavesOtherHuesAndNeutralsAlone() {
        var vectors = HueVectors()
        vectors.blue = .init(hue: 60, saturation: 50, density: 80)
        let red = RGB(1.2, -0.4, -0.8), yellow = RGB(0.8, 0.7, -1), grey = RGB(repeating: 0.5)
        for e in [red, yellow, grey] { #expect(simd_distance(vectors.apply(e), e) < 1e-12) }
        let blue = RGB(-0.5, -0.4, 1.1)
        #expect(simd_distance(vectors.apply(blue), blue) > 0.1)
    }

    @Test func hueAndSaturationKeepLuminance() {
        var vectors = HueVectors()
        for vector in HueVectors.Vector.allCases { vectors[vector] = .init(hue: 70, saturation: -40) }
        vectors.cyan.saturation = 80
        let luma = HueVectors.plane.lumaWeights
        for e in Self.colors { #expect(abs(simd_dot(vectors.apply(e), luma) - simd_dot(e, luma)) < 1e-9) }
    }

    @Test func positiveHueTurnsTowardTheNextVector() {
        var vectors = HueVectors()
        vectors.red.hue = 100
        let red = HueVectors.Vector.red.rgb * 2 - 1
        let turned = remainder(Self.hue(vectors.apply(red)) - Self.hue(red), 2 * .pi)
        #expect(abs(turned - HueVectors.maxTurn) < 1e-9)
    }

    @Test func blendingIsContinuousAcrossTheWrap() {
        var vectors = HueVectors()
        vectors.magenta = .init(hue: -40, saturation: 30, density: 20)
        vectors.red = .init(hue: 25, saturation: -20, density: 60)
        let wrap = HueVectors.angles[0]
        for (a, b) in [(wrap - 1e-6, wrap + 1e-6), (wrap + 2 * .pi - 1e-6, wrap + 1e-6)] {
            let x = vectors.adjustment(at: a), y = vectors.adjustment(at: b)
            #expect(abs(x.hue - y.hue) < 1e-4 && abs(x.saturation - y.saturation) < 1e-4 && abs(x.density - y.density) < 1e-4)
        }
        #expect(vectors.adjustment(at: wrap) == vectors.red)
    }

    @Test func protectSkinSparesSkinTones() {
        var vectors = HueVectors()
        for vector in HueVectors.Vector.allCases { vectors[vector] = .init(hue: 50, saturation: 50, density: 50) }
        vectors.protectSkin = 100
        #expect(vectors.adjustment(at: HueVectors.skinAngle).isNeutral)
        // Far from skin, full strength.
        #expect(abs(vectors.adjustment(at: HueVectors.skinAngle + .pi).hue - 50) < 1e-6)
        // Skin hue sits between red and yellow.
        #expect(HueVectors.skinAngle > HueVectors.angles[0] && HueVectors.skinAngle < HueVectors.angles[1])
    }

    @Test func theLookCarriesTheVectors() {
        var settings = GradeSettings()
        settings.hueVectors.green.saturation = -50
        #expect(ColorPipeline.look(settings) != ColorPipeline.look(GradeSettings()))
        #expect(ColorPipeline.look(settings).hueVectors == settings.hueVectors)
    }
}
