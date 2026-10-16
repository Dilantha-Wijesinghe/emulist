import CoreGraphics
import Metal

extension OutputTransform {
    /// The color space whose decoding matches this output's encoding (Rec.709 primaries, pure power curve).
    /// Tagging the viewer and still images with it makes ColorSync show the display light the grade intends.
    public var colorSpace: CGColorSpace {
        let m = primaries.rgbToXYZ
        let white = primaries.white.xyz
        let matrix = (0..<3).flatMap { c in (0..<3).map { r in CGFloat(m[c][r]) } }
        let gamma = CGFloat(displayGamma)
        return CGColorSpace(
            calibratedRGBWhitePoint: [CGFloat(white.x), 1, CGFloat(white.z)], blackPoint: [0, 0, 0],
            gamma: [gamma, gamma, gamma], matrix: matrix)!
    }
}

extension FrameRenderer {
    /// Reads an rgba16Float texture back as an 8-bit image tagged with the output's color space.
    public func makeImage(from texture: MTLTexture, output: OutputTransform) throws -> CGImage {
        let width = texture.width, height = texture.height
        let bytesPerRow = width * 8
        guard let buffer = context.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let commandBuffer = context.queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { throw RenderError.textureCreation }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let halves = buffer.contents().bindMemory(to: Float16.self, capacity: width * height * 4)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height * 4) where i % 4 != 3 {
            pixels[i] = UInt8(max(0, min(255, (Float(halves[i]) * 255).rounded())))
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: output.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.textureCreation }
        return image
    }
}
