import Metal
import Testing
import simd
@testable import EmulistCore

/// The shader's primary grade must match `PrimaryGrade.apply`, the tested Swift reference.
@Suite struct GPUGradeTests {
    private static let probe = """
    kernel void grade_probe(device const float4 *input [[buffer(0)]], device float4 *output [[buffer(1)]],
                            constant GradeUniforms &grade [[buffer(2)]], uint i [[thread_position_in_grid]]) {
        output[i] = float4(apply_grade(input[i].xyz, grade), 0);
    }
    """

    static var busy: GradeSettings {
        var s = GradeSettings()
        s.lift = ColorWheel(x: 0.3, y: -0.2, master: 0.05)
        s.gamma = ColorWheel(x: 0, y: 0.25, master: -0.1)
        s.gain = ColorWheel(x: -0.2, y: 0, master: 0.2)
        s.offset = ColorWheel(x: 0, y: 0.15, master: 0)
        s.contrast = 35
        s.pivot = 0.8
        s.saturation = 140
        s.colorBoost = 40
        s.density = 40
        s.shadows = 25
        s.highlights = -30
        s.push = 0.7
        s.cyanRed = 20
        s.yellowBlue = -25
        return s
    }

    @Test(arguments: [GradeSettings(), busy])
    func shaderMatchesSwiftReference(_ settings: GradeSettings) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return }
        let library = try MetalContext.makeLibrary(device: device, extra: Self.probe)
        let pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: "grade_probe")))

        // A spread of exposures and colors across the shaper range.
        let tints = [RGB(0, 0, 0), RGB(1.5, 0, -1), RGB(-0.8, 0.6, 0), RGB(0, -2, 1)]
        let samples: [RGB] = stride(from: -9.0, through: 7.0, by: 1).flatMap { stop in
            tints.map { RGB(repeating: stop) + $0 }
        }
        let input = samples.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) }
        let length = input.count * MemoryLayout<SIMD4<Float>>.stride
        let inBuffer = try #require(device.makeBuffer(bytes: input, length: length, options: .storageModeShared))
        let outBuffer = try #require(device.makeBuffer(length: length, options: .storageModeShared))
        let grade = PrimaryGrade(settings)
        var uniforms = grade.uniforms

        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<GradeUniforms>.stride, index: 2)
        encoder.dispatchThreads(MTLSize(width: input.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 32, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let output = outBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: input.count)
        for (i, sample) in samples.enumerated() {
            let expected = grade.isIdentity ? sample : grade.apply(sample)
            let gpu = RGB(Double(output[i].x), Double(output[i].y), Double(output[i].z))
            #expect(abs(gpu - expected).max() < 2e-3, "stops \(sample): gpu \(gpu) vs \(expected)")
        }
    }
}
