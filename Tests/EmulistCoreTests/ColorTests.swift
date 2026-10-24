import CoreGraphics
import CoreMedia
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

@Suite struct FujifilmTests {
    @Test func fLog2MidGreyMatchesSpecification() {
        // colour-science reference: log_encoding_FLog2(0.18) = 0.3910072.
        #expect(abs(TransferFunction.fLog2.encode(0.18) - 0.3910072) < 1e-6)
        #expect(abs(TransferFunction.fLog.encode(0.18) - 0.4593) < 1e-3)
    }

    @Test func recognizesFujifilmFileNames() {
        #expect(FujifilmLooks.simulation(forFileName: "FLog2_to_CLASSIC-CHROME_65grid_V.1.00")?.name == "Classic Chrome")
        #expect(FujifilmLooks.simulation(forFileName: "FLog2_to_ETERNA-BB_65grid_V.1.00")?.name == "Eterna Bleach Bypass")
        #expect(FujifilmLooks.simulation(forFileName: "FLog2_to_ETERNA_65grid_V.1.00")?.name == "Eterna")
        #expect(FujifilmLooks.simulation(forFileName: "FLog2_to_WDR-709_65grid_V.1.00") == nil)
    }

    @Test func infersLUTInputFromName() {
        #expect(LookLibrary.inputProfile(forName: "FLog2_to_PROVIA") == .fLog2)
        #expect(LookLibrary.inputProfile(forName: "XH2S_FLog_FGamut_to_ETERNA") == .fLog)
        #expect(LookLibrary.inputProfile(forName: "FLog2C_to_PROVIA") == nil)
        #expect(LookLibrary.inputProfile(forName: "My Apple Log Look") == .appleLog)
    }
}

@Suite struct CubeLUTTests {
    private func identityCube(size: Int) -> String {
        var text = "TITLE \"identity\"\nLUT_3D_SIZE \(size)\n"
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let n = Double(size - 1)
            text += "\(Double(r) / n) \(Double(g) / n) \(Double(b) / n)\n"
        } } }
        return text
    }

    @Test func parsesAndInterpolatesIdentityExactly() throws {
        let cube = try CubeLUT(data: Data(identityCube(size: 5).utf8))
        #expect(cube.size == 5 && cube.title == "identity")
        for input in [RGB(0.1, 0.7, 0.33), RGB(0.9, 0.2, 0.55), RGB(0.5, 0.5, 0.5), RGB(0, 1, 0.25)] {
            #expect(simd_distance(cube.sample(input), input) < 1e-6)
        }
    }

    @Test func rejectsWrongEntryCount() {
        #expect(throws: CubeLUT.ParseError.self) { try CubeLUT(data: Data("LUT_3D_SIZE 3\n0 0 0\n".utf8)) }
    }
}

@Suite struct PrimaryGradeTests {
    @Test func defaultsAreIdentity() {
        let grade = PrimaryGrade(GradeSettings())
        #expect(grade.isIdentity)
        let e = RGB(-2.3, 0.4, 1.7)
        #expect(simd_distance(grade.apply(e), e) < 1e-12)
    }

    @Test func wheelRGBRoundTripsAndIsLumaNeutral() {
        let wheel = ColorWheel(x: 0.4, y: -0.3, master: 0.05)
        let rgb = wheel.rgb(.gamma)
        #expect(abs(simd_dot(rgb, ColorWheel.lumaWeights) - 0.05) < 1e-12)
        let back = ColorWheel(rgb: rgb, kind: .gamma)
        #expect(abs(back.x - 0.4) < 1e-12 && abs(back.y + 0.3) < 1e-12 && abs(back.master - 0.05) < 1e-12)
    }

    @Test func pushingTowardRedWarmsTheImage() {
        var settings = GradeSettings()
        settings.gain = ColorWheel(x: 0, y: 0.5) // +Cr = red on a vectorscope
        let out = PrimaryGrade(settings).apply(RGB(repeating: 1))
        #expect(out.x > 1 && out.z < out.x)
    }

    @Test func densityDeepensColorButLeavesNeutralsAlone() {
        var settings = GradeSettings()
        settings.density = 100
        let grade = PrimaryGrade(settings)
        #expect(simd_distance(grade.apply(RGB(repeating: 0.5)), RGB(repeating: 0.5)) < 1e-12)
        let red = RGB(1, -0.5, -0.8)
        let out = grade.apply(red)
        #expect(out.x < red.x && out.y < red.y - 0.5 && out.z < red.z - 0.5)
        #expect(out.max() - out.min() > red.max() - red.min())
    }

    @Test func colorBoostFavorsMutedColors() {
        var settings = GradeSettings()
        settings.colorBoost = 100
        let grade = PrimaryGrade(settings)
        func gain(_ e: RGB) -> Double { (grade.apply(e).max() - grade.apply(e).min()) / (e.max() - e.min()) }
        #expect(gain(RGB(0.1, 0, -0.1)) > gain(RGB(1.5, 0, -1.5)))
    }

    @Test func legacyProjectsDecodeWithDefaults() throws {
        let legacy = #"{"cameraProfileID":"apple-log","exposure":0.5,"stockID":"nocturne-800","intensity":80}"#
        let settings = try JSONDecoder().decode(GradeSettings.self, from: Data(legacy.utf8))
        #expect(settings.exposure == 0.5 && settings.intensity == 80 && settings.stockID == "nocturne-800")
        #expect(settings.lift.isNeutral && settings.saturation == 100 && settings.grain == GrainSettings())
    }
}

@Suite struct ProfileDetectionTests {
    private let bt2020 = kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String

    @Test func blackmagicCameraOnIPhoneIsAppleLog() {
        let iPhone = MediaInfo.Recorder(software: "Blackmagic Cam 3.5.200045", model: "Apple iPhone 16 Pro Max 48mm")
        #expect(MediaInfo.detectProfile(log: nil, transfer: nil, primaries: bt2020, recorder: iPhone) == .appleLog)
        // Tagged modes (here HLG) and other apps are left to the user.
        #expect(MediaInfo.detectProfile(log: nil, transfer: "ITU_R_2100_HLG", primaries: bt2020, recorder: iPhone) == nil)
        #expect(MediaInfo.detectProfile(log: nil, transfer: nil, primaries: bt2020,
                                        recorder: .init(software: "Other", model: "Apple iPhone 15 Pro")) == nil)
    }
}

@Suite struct DragMathTests {
    private func dial(_ value: Double, range: ClosedRange<Double> = -100...100, detent: Double? = 0) -> DragMath.Dial {
        DragMath.Dial(value: value, range: range, pointsPerRange: 200, detent: detent, detentWidth: 0.015)
    }

    @Test func dragIsRelativeAndClamped() {
        var d = DragMath.Dial(value: 10, range: 0...100, pointsPerRange: 100)
        d.move(50)
        #expect(d.value == 60)
        d.move(500)
        #expect(d.value == 100)
        var fine = DragMath.Dial(value: 10, range: 0...100, pointsPerRange: 100)
        fine.move(50, fine: true)
        #expect(fine.value == 15)
    }

    @Test func defaultIsAStickyDetentWithoutJumps() {
        // From the detent, small travel stays put (the dead zone is 3 points)…
        var d = dial(0)
        d.move(2)
        #expect(d.value == 0)
        // …and leaving it is continuous: just past the dead zone the value is just past zero.
        d.move(1.1)
        #expect(d.value > 0 && d.value < 0.2)
        // Starting away from the detent, the first movement is never a jump.
        var nudge = dial(40)
        nudge.move(1)
        #expect(abs(nudge.value - 41) < 1e-9)
        // Crossing it parks there.
        var cross = dial(2)
        cross.move(-4)
        #expect(cross.value == 0)
    }

    @Test func fineModeKeepsTheDetentNarrowAndNeverJumps() {
        // The same 4 points of pointer travel leave the detent with or without ⌥.
        for fine in [false, true] {
            var d = dial(0)
            d.move(4, fine: fine)
            #expect(d.value > 0)
        }
        // Switching speed mid-drag changes only what follows.
        var d = dial(50)
        d.move(10, fine: true)
        #expect(abs(d.value - 51) < 1e-9)
        d.move(10)
        #expect(abs(d.value - 61) < 1e-9)
    }

    @Test func detentCrossingIsReported() {
        #expect(DragMath.reached(0, from: 5, to: -5))
        #expect(DragMath.reached(0, from: 5, to: 0))
        #expect(!DragMath.reached(0, from: 0, to: 3))
        #expect(!DragMath.reached(0, from: 5, to: 3))
    }

    @Test func puckStaysInDiskAndCenters() {
        let far = DragMath.puck(from: .zero, delta: SIMD2(5, 0))
        #expect(abs(simd_length(far) - 1) < 1e-9)
        #expect(DragMath.puck(from: SIMD2(0.2, 0), delta: SIMD2(-0.21, 0)) == .zero)
        // Away from the center the puck tracks the pointer (the radial detent couples axes only slightly).
        let moved = DragMath.puck(from: SIMD2(0.5, 0.2), delta: SIMD2(0.01, 0))
        #expect(abs(moved.x - 0.51) < 1e-3 && abs(moved.y - 0.2) < 1e-3)
    }
}
