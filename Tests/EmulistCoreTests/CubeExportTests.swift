import CoreVideo
import Foundation
import Metal
import Testing
import simd
@testable import EmulistCore

@Suite struct CubeExportTests {
    /// A busy grade on a film look, texture off (no LUT can carry it), for a gamma 2.4 display.
    static var grade: GradeSettings {
        var s = GPUGradeTests.busy
        s.select(FilmStock.builtIn[1])
        s.intensity = 80
        s.fade = 20
        s.output = .rec709Gamma24
        s.grain.enabled = false
        s.halation.enabled = false
        s.bloom.enabled = false
        return s
    }

    /// A natural grade: the kind of look a LUT carries, with little clipping.
    static var natural: GradeSettings {
        var s = grade
        s.lift = ColorWheel(x: 0.1, y: -0.05, master: 0.02)
        s.gain = ColorWheel(x: -0.05, y: 0.05, master: 0.05)
        s.gamma = ColorWheel()
        s.offset = ColorWheel()
        s.contrast = 15
        s.saturation = 115
        s.colorBoost = 20
        s.density = 25
        s.highlights = -15
        s.push = 0
        return s
    }

    @Test func writtenCubeParsesBack() throws {
        let cube = try CubeLUT(baking: Self.grade, input: .appleLog, size: 9, title: "Busy \"look\"")
        let parsed = try CubeLUT(data: cube.cubeData())
        #expect(parsed.size == 9 && parsed.title == "Busy 'look'")
        for code in [RGB(0, 0, 0), RGB(1, 1, 1), RGB(0.3, 0.55, 0.8), RGB(0.61, 0.42, 0.37)] {
            #expect(simd_reduce_max(simd_abs(parsed.sample(code) - cube.sample(code))) < 1e-5)
        }
    }

    /// Between grid points the LUT interpolates. On a 65 grid it stays within half a code of the exact
    /// pipeline on average, and within a few codes where the look is steep (saturated colors through the
    /// print toe). Like any LUT on log input, it bends more for extreme colors with a channel at black.
    @Test func cubeMatchesThePipeline() throws {
        let grade = Self.natural
        let cube = try CubeLUT(baking: grade, input: .appleLog, size: 65, title: "Busy")
        let renderer = try ColorPipeline(grade).makeRenderer()
        let toWorking = InputTransform.matrix(for: grade)
        var errors: [Double] = []
        // Off-grid Apple Log code values from deep shadow to highlights, neutral and saturated.
        for grey in [0.23, 0.37, 0.51, 0.66, 0.74] {
            for dr in [-0.09, -0.03, 0.04, 0.08] {
                for db in [-0.08, -0.02, 0.05, 0.09] {
                    let code = RGB(grey + dr, grey - (dr + db) / 2, grey + db)
                    let exact = simd_clamp(renderer.render(toWorking * code.decoded(.appleLog)), .zero, RGB(repeating: 1))
                    errors.append(simd_reduce_max(simd_abs(cube.sample(code) - exact)) * 255)
                }
            }
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        #expect(errors.max()! < 3, "worst \(errors.max()!) codes")
        #expect(mean < 0.5, "mean \(mean) codes")
    }

    @Test func clipCorrectionsAreLeftOut() throws {
        var corrected = Self.grade
        corrected.exposure = 1.2
        corrected.temperature = 30
        corrected.tint = -20
        let a = try CubeLUT(baking: Self.grade, input: .appleLog, size: 5, title: "a").cubeData()
        let b = try CubeLUT(baking: corrected, input: .appleLog, size: 5, title: "a").cubeData()
        #expect(a == b)
        let other = try CubeLUT(baking: Self.grade, input: .sLog3, size: 5, title: "a").cubeData()
        #expect(a != other)
    }

    /// The exported cube, sampled on the CPU, against the app's GPU render of a frame of color patches.
    @Test func cubeMatchesTheViewer() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let grade = Self.grade
        let cube = try CubeLUT(baking: grade, input: .appleLog, size: 65, title: "Busy")
        // 10-bit video-range Y'CbCr patches, 32×32 pixels each.
        let patches: [(y: Int, cb: Int, cr: Int)] = [
            (300, 512, 512), (480, 512, 512), (640, 512, 512), (800, 512, 512),
            (450, 450, 600), (500, 600, 470), (560, 420, 480), (420, 560, 560),
        ]
        let side = 32
        let buffer = try Self.pixelBuffer(width: side * patches.count, height: side) { x in patches[x / side] }
        let context = try MetalContext.make()
        let renderer = FrameRenderer(context: context)
        let commandBuffer = try #require(context.queue.makeCommandBuffer())
        let texture = try renderer.encode(buffer, frameIndex: 0, settings: grade, into: commandBuffer)
        commandBuffer.commit()
        let image = try renderer.makeImage(from: texture, output: grade.output)
        let pixels = try #require(image.dataProvider?.data as Data?)

        let (rows, norm) = InputTransform.ycbcrUniforms(.rec2020)
        for (index, patch) in patches.enumerated() {
            // The same Y'CbCr → R'G'B' as the shader.
            func sample(_ code: Int) -> Double { Double(code << 6) / 65535 }
            let ycc = RGB(sample(patch.y) * Double(norm.x) - Double(norm.y), sample(patch.cb) * Double(norm.z) - Double(norm.w),
                          sample(patch.cr) * Double(norm.z) - Double(norm.w))
            let code = rows * ycc
            let offset = ((side / 2) * image.bytesPerRow) + (index * side + side / 2) * 4
            let viewer = RGB(Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
            let fromCube = cube.sample(code) * 255
            #expect(simd_reduce_max(simd_abs(viewer - fromCube)) <= 3, "patch \(index): viewer \(viewer), cube \(fromCube)")
        }
    }

    /// An IOSurface-backed 10-bit 4:2:2 frame (the decoder's format), with `patch(x)` giving each column's codes.
    static func pixelBuffer(width: Int, height: Int, patch: (Int) -> (y: Int, cb: Int, cr: Int)) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, DecodeFormat.pixelFormat, DecodeFormat.attributes as CFDictionary, &buffer)
        let frame = try #require(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        for plane in 0..<2 {
            let base = try #require(CVPixelBufferGetBaseAddressOfPlane(frame, plane))
            let stride = CVPixelBufferGetBytesPerRowOfPlane(frame, plane) / 2
            let samples = base.assumingMemoryBound(to: UInt16.self)
            for row in 0..<CVPixelBufferGetHeightOfPlane(frame, plane) {
                for x in 0..<width {
                    let p = patch(plane == 0 ? x : x & ~1)
                    // 10-bit codes sit in the high bits of each 16-bit sample.
                    if plane == 0 {
                        samples[row * stride + x] = UInt16(p.y << 6)
                    } else {
                        samples[row * stride + x] = UInt16((x % 2 == 0 ? p.cb : p.cr) << 6)
                    }
                }
            }
        }
        return frame
    }
}
