import Metal
import Testing
import simd
@testable import EmulistCore

/// The GPU scopes must bin every sample where `ScopeRenderer`'s Swift mirror says it belongs.
@Suite struct ScopeTests {
    /// Left half `left`, right half `right`, at the sample grid's own size so each sample reads one texel.
    private static func image(_ context: MetalContext, width: Int, height: Int, left: RGB, right: RGB) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        let texture = try #require(context.device.makeTexture(descriptor: descriptor))
        let pixels = (0..<height).flatMap { _ in
            (0..<width).flatMap { x in
                let c = x < width / 2 ? left : right
                return [Float16(c.x), Float16(c.y), Float16(c.z), 1]
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels,
                        bytesPerRow: width * 8)
        return texture
    }

    @Test func binsMatchTheSwiftMirror() throws {
        guard let context = try? MetalContext.make() else { return }
        let scopes = try ScopeRenderer(context: context)
        let left = RGB(0.75, 0.6, 0.2), right = RGB(0.1, 0.3, 0.9)
        let (width, height) = ScopeRenderer.grid(width: 1024, height: 512)
        let commandBuffer = try #require(context.queue.makeCommandBuffer())
        scopes.analyze(try Self.image(context, width: width, height: height, left: left, right: right), into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let (wave, vector) = scopes.counts
        let columns = ScopeRenderer.columns, samplesPerHalf = UInt32(width * height / 2)
        for (color, columnRange) in [(left, 0..<columns / 2), (right, columns / 2..<columns)] {
            let values = [color.x, color.y, color.z, simd_dot(color, ScopeGeometry.matrix.lumaWeights)]
            for (channel, value) in values.enumerated() {
                let level = ScopeRenderer.level(value)
                let hits = columnRange.reduce(UInt32(0)) { $0 + wave[(level * columns + $1) * 4 + channel] }
                #expect(hits == samplesPerHalf, "channel \(channel) of \(color) at level \(level)")
            }
            let bin = ScopeRenderer.vectorBin(color)
            #expect(vector[bin.y * ScopeRenderer.vectorBins + bin.x] == samplesPerHalf, "vector bin of \(color)")
        }
        #expect(vector.reduce(0, +) == UInt32(width * height))
        #expect(wave.reduce(0, +) == UInt32(width * height * 4))
    }

    @Test func drawsAtAnySize() throws {
        guard let context = try? MetalContext.make() else { return }
        let scopes = try ScopeRenderer(context: context)
        let commandBuffer = try #require(context.queue.makeCommandBuffer())
        scopes.analyze(try Self.image(context, width: 64, height: 32, left: .zero, right: RGB(repeating: 1)), into: commandBuffer)
        for kind in ScopeKind.allCases {
            let texture = try scopes.draw(kind, width: 301, height: 97, into: commandBuffer)
            #expect(texture.width == 301 && texture.height == 97)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)
    }

    @Test func graticuleGeometry() {
        // Every 75% bar target sits inside the scope; red points up and to the left, blue to the right.
        for target in ScopeGeometry.targets { #expect(simd_length(target.point) < 1) }
        let red = ScopeGeometry.targets[0].point, blue = ScopeGeometry.targets[4].point
        #expect(red.y > 0 && red.x < 0 && blue.x > 0)
        // The skin-tone line runs between red and yellow, about 130° from +Cb.
        let angle = atan2(ScopeGeometry.skinToneDirection.y, ScopeGeometry.skinToneDirection.x) * 180 / .pi
        #expect(abs(angle - 130.5) < 1)
        // A typical skin tone lies within a few degrees of it.
        let skin = simd_normalize(ScopeGeometry.vectorPoint(RGB(0.87, 0.67, 0.55)))
        #expect(acos(simd_dot(skin, ScopeGeometry.skinToneDirection)) * 180 / .pi < 4)
    }
}
