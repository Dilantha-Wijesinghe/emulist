import CoreGraphics
import Foundation
import Testing
import simd
@testable import EmulistCore

@Suite struct TransferFunctionTests {
    @Test func appleLogMidGreyMatchesSpecification() {
        // Apple's white paper / colour-science reference: 18% grey encodes to ~0.4883.
        #expect(abs(TransferFunction.appleLog.encode(0.18) - 0.48834) < 1e-4)
    }

    @Test(arguments: TransferFunction.allCases)
    func roundTrips(_ tf: TransferFunction) {
        for linear in stride(from: 0.0, through: 8.0, by: 0.013) {
            #expect(abs(tf.decode(tf.encode(linear)) - linear) < 1e-9 * max(1, linear))
        }
    }

    @Test func sLog3MidGrey() {
        // Sony: 18% grey = 420 / 1023 code value.
        #expect(abs(TransferFunction.sLog3.encode(0.18) - 420.0 / 1023) < 1e-9)
    }

    @Test func appleLogIsContinuousAtBreakpoint() {
        let below = TransferFunction.appleLog.encode(AppleLog.rt - 1e-9)
        let above = TransferFunction.appleLog.encode(AppleLog.rt)
        #expect(abs(below - above) < 1e-6)
    }
}

@Suite struct ColorMatrixTests {
    @Test func rec2020LuminanceWeights() {
        let w = ColorPrimaries.rec2020.luminanceWeights
        #expect(abs(w.x - 0.2627) < 1e-4 && abs(w.y - 0.6780) < 1e-4 && abs(w.z - 0.0593) < 1e-4)
    }

    @Test func whiteIsPreservedAcrossGamuts() {
        let m = ColorPrimaries.sGamut3Cine.conversion(to: .rec2020)
        let white = m * RGB(1, 1, 1)
        #expect(simd_distance(white, RGB(1, 1, 1)) < 1e-9)
    }

    @Test func rec2020ToRec709MatchesBT2087() {
        // ITU-R BT.2087 first row: 1.6605, -0.5876, -0.0728.
        let m = ColorPrimaries.rec2020.conversion(to: .rec709)
        let red = m * RGB(1, 0, 0)
        #expect(abs(red.x - 1.6605) < 1e-3 && abs(red.y - -0.1246) < 1e-3)
    }

    @Test func bradfordIdentityForSameWhite() {
        #expect(ChromaticAdaptation.bradford(from: .d65, to: .d65) == matrix_identity_double3x3)
    }

    @Test func daylightLocusNearD65() {
        let d = ChromaticAdaptation.daylight(kelvin: 6504)
        #expect(abs(d.x - 0.3127) < 1e-3 && abs(d.y - 0.3290) < 1e-3)
    }
}

@Suite struct FilmModelTests {
    private func displayLinear(_ model: FilmModel, _ scene: Double) -> RGB {
        let out = model.render(RGB(repeating: scene))
        return RGB(model.output.transfer.decode(out.x), model.output.transfer.decode(out.y), model.output.transfer.decode(out.z))
    }

    @Test func neutralMapsMidGreyToTarget() {
        let model = FilmModel(response: .neutral, output: .rec709Apple)
        let grey = displayLinear(model, 0.18)
        #expect(abs(grey.y - FilmResponse.neutral.midGrey) < 1e-3)
        #expect(abs(grey.x - grey.z) < 1e-6)
    }

    @Test(arguments: FilmStock.builtIn)
    func toneCurveIsMonotonicAndBounded(_ stock: FilmStock) {
        let model = FilmModel(response: stock.response, output: .rec709Gamma24)
        var previous = -1.0
        for stops in stride(from: -11.0, through: 9.0, by: 0.05) {
            let value = simd_dot(model.render(RGB(repeating: 0.18 * pow(2, stops))), RGB(0.2126, 0.7152, 0.0722))
            #expect(value >= previous - 1e-9)
            #expect((0...1).contains(value))
            previous = value
        }
    }

    @Test func zeroIntensityEqualsNeutral() {
        var settings = GradeSettings()
        settings.intensity = 0
        #expect(FilmResponse(for: settings) == .neutral)
    }

    @Test func printerLightsPreserveExposure() {
        var settings = GradeSettings()
        settings.intensity = 0
        settings.cyanRed = 60
        settings.yellowBlue = -40
        let balance = FilmResponse(for: settings).balance
        #expect(abs(simd_dot(balance, WorkingSpace.luminance)) < 1e-12)
    }
}

@Suite struct ProjectTests {
    @Test func projectRoundTrips() throws {
        var settings = GradeSettings()
        settings.select(FilmStock.builtIn[2])
        settings.exposure = 0.7
        settings.halation.amount = 12
        let media = MediaReference(MediaInfo(
            url: URL(fileURLWithPath: "/tmp/clip.mov"), width: 3840, height: 2160, frameRate: 24, duration: 10,
            codec: "apch", colorPrimaries: nil, transferFunction: nil, logTransferFunction: nil, hasAudio: true,
            detectedProfile: .appleLog))
        let project = EmulistProject(media: media, settings: settings, export: ExportSettings(codec: .h264))
        let decoded = try EmulistProject.decode(project.encoded())
        #expect(decoded.settings == settings)
        #expect(decoded.export == project.export)
        #expect(decoded.media.width == 3840)
    }

    @Test func effectSizesScaleWithResolution() {
        let settings = GradeSettings()
        let hd = EffectParameters(settings, height: 1080)
        let uhd = EffectParameters(settings, height: 2160)
        #expect(abs(uhd.halationSigma - 2 * hd.halationSigma) < 1e-9)
        #expect(abs(uhd.bloomSigma - 2 * hd.bloomSigma) < 1e-9)
        #expect(abs(uhd.grainSigma - 2 * hd.grainSigma) < 1e-9)
        // Below the 1080-line reference the grain canvas stays put and is filtered down instead.
        #expect(EffectParameters(settings, height: 540).grainCanvasHeight == 1080)
    }

    @Test func stockSelectionLoadsRecommendedEffects() {
        var settings = GradeSettings()
        let stock = FilmStock.builtIn[1]
        settings.select(stock)
        #expect(settings.grain == stock.grain && settings.halation == stock.halation)
    }
}

@Suite struct OutputTests {
    /// The viewer is tagged with `colorSpace`; ColorSync must decode our encoding back to the same light.
    @Test(arguments: OutputTransform.allCases)
    func previewColorSpaceInvertsEncoding(_ output: OutputTransform) {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        for light in [0.01, 0.05, 0.16, 0.4, 0.8] {
            let code = output.transfer.encode(light)
            let color = CGColor(colorSpace: output.colorSpace, components: [code, code, code, 1])!
            let decoded = color.converted(to: linear, intent: .relativeColorimetric, options: nil)!.components![1]
            #expect(abs(decoded - light) / light < 0.01)
        }
    }
}

@Suite struct OrientationTests {
    // A typical iPhone portrait transform: 90° clockwise, translated back into view.
    private let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    private let stored = CGSize(width: 1920, height: 1080)

    @Test func portraitIsUprightSize() {
        #expect(portrait.uprightSize(stored) == CGSize(width: 1080, height: 1920))
    }

    @Test func portraitMapsCornersCorrectly() {
        let m = portrait.uprightToStored(bufferSize: stored)
        // The displayed top-left pixel is the stored bottom-left one (T maps (0, 1080) to (0, 0)).
        let topLeft = CGPoint(x: 0, y: 0).applying(m)
        #expect(abs(topLeft.x - 0) < 1e-9 && abs(topLeft.y - 1) < 1e-9)
        let topRight = CGPoint(x: 1, y: 0).applying(m)
        #expect(abs(topRight.x - 0) < 1e-9 && abs(topRight.y - 0) < 1e-9)
    }

    @Test func identityIsUntouched() {
        #expect(CGAffineTransform.identity.uprightToStored(bufferSize: stored).isIdentity)
    }
}
