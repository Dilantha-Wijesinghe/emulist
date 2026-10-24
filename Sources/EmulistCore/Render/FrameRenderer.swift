import CoreGraphics
import CoreVideo
import Metal
import MetalPerformanceShaders

/// Renders one decoded video frame through the full Emulist pipeline:
///
///     Y'CbCr → camera decode → working linear (exposure, white balance)
///            → [softness] → bloom + halation (scene-linear, half resolution)
///            → grain (log exposure) → primary grade (log exposure) → look LUT (film or LUT look + output)
///
/// Not thread-safe: use one renderer per thread of work (the viewer and each export own their own).
public final class FrameRenderer: @unchecked Sendable {
    public struct Options: Sendable {
        /// Processing resolution relative to the source.
        public var scale: Double = 1
        /// Fraction of the frame width (from the left) that shows the ungraded "before" image.
        public var beforeSplit: Double = 0
        /// The clip's display transform; frames are rendered upright.
        public var orientation: CGAffineTransform = .identity
        /// Bakes uncached look LUTs on the coarse draft grid, for fast previews during a drag.
        public var draft = false

        public init(scale: Double = 1, beforeSplit: Double = 0, orientation: CGAffineTransform = .identity,
                    draft: Bool = false) {
            self.scale = scale
            self.beforeSplit = beforeSplit
            self.orientation = orientation
            self.draft = draft
        }
    }

    /// Output size for an upright frame of `width`×`height` at `scale`: even dimensions, as encoders require.
    public static func outputSize(width: Int, height: Int, scale: Double) -> (width: Int, height: Int) {
        (max(16, Int((Double(width) * scale).rounded()) & ~1), max(16, Int((Double(height) * scale).rounded()) & ~1))
    }

    public let context: MetalContext
    /// Edge length of the baked look LUTs; thumbnails use a coarser grid to bake faster.
    public let lutSize: Int
    private let lutCacheCapacity: Int
    private struct LUTKey: Hashable {
        let pipeline: ColorPipeline
        let size: Int
    }

    private var filmLUTs: [LUTKey: MTLTexture] = [:]
    private var filmLUTOrder: [LUTKey] = []
    private var decodeTables: [TransferFunction: MTLBuffer] = [:]
    private var textures: [String: MTLTexture] = [:]
    private var blurs: [Float: MPSImageGaussianBlur] = [:]
    private lazy var emptyTexture = try? context.makeTexture(width: 1, height: 1)

    public init(context: MetalContext, lutSize: Int = LUTBaker.filmLUTSize, lutCacheCapacity: Int = 16) {
        self.context = context
        self.lutSize = lutSize
        self.lutCacheCapacity = lutCacheCapacity
    }

    /// Encodes all passes for one frame and returns the display-encoded output texture (rgba16Float).
    /// The texture is reused by the next call, so consume it within the same command queue.
    public func encode(
        _ pixelBuffer: CVPixelBuffer, frameIndex: Int, settings: GradeSettings, options: Options = .init(),
        into commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        let stored = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let upright = options.orientation.uprightSize(stored)
        let (width, height) = Self.outputSize(width: Int(upright.width), height: Int(upright.height), scale: options.scale)
        let effects = EffectParameters(settings, height: Double(height))

        let original = try decode(pixelBuffer, settings: settings, orientation: options.orientation,
                                  size: (width, height), into: commandBuffer)
        let working = effects.hasSoftness
            ? try blurred(original, sigma: effects.softnessSigma, key: "soft", into: commandBuffer) : original
        let (bloom, halation) = try lightEffects(working, effects, into: commandBuffer)
        let grain = try grainTexture(effects, frameIndex: frameIndex, aspect: Double(width) / Double(height),
                                     into: commandBuffer)

        let output = try texture("output", width: width, height: height)
        let lookKey = ColorPipeline.look(settings), beforeKey = ColorPipeline.neutral(output: settings.output)
        // A draft only stands in for a LUT that would need a full bake (e.g. while dragging Intensity); grading
        // drags reuse the cached full-size look. Both LUTs share one size, since the shader samples them alike.
        let needsBake = [lookKey, beforeKey].contains { filmLUTs[LUTKey(pipeline: $0, size: lutSize)] == nil }
        let size = options.draft && needsBake ? min(lutSize, LUTBaker.draftLUTSize) : lutSize
        let lookLUT = try filmLUT(LUTKey(pipeline: lookKey, size: size))
        let beforeLUT = try filmLUT(LUTKey(pipeline: beforeKey, size: size))
        var grade = PrimaryGrade(settings).uniforms
        var uniforms = FilmUniforms(
            luminance: WorkingSpace.luminance.float4,
            shaper: SIMD4(Float(WorkingSpace.shaperRange.lowerBound),
                          Float(WorkingSpace.shaperRange.upperBound - WorkingSpace.shaperRange.lowerBound),
                          Float(WorkingSpace.midGrey), Float(size)),
            bloom: SIMD4(Float(effects.bloomAmount), 0, 0, 0),
            halation: SIMD4(Float(effects.halationAmount), Float(effects.halationTint.x),
                            Float(effects.halationTint.y), Float(effects.halationTint.z)),
            grain: SIMD4(Float(effects.grainAmount), Float(effects.grainChroma),
                         Float(max(0, log2(effects.grainCanvasHeight / Double(height)))),
                         Float(effects.grainNormalization)),
            beforeRows: InputTransform.adjustment(for: settings).inverse.rows4,
            compare: SIMD4(Float(options.beforeSplit), 0, 0, 0))
        context.dispatch("film_render", on: commandBuffer, size: (width, height)) { encoder in
            encoder.setTextures([working, original, bloom, halation, grain, lookLUT, beforeLUT, output],
                                range: 0..<8)
            encoder.setBytes(&uniforms, length: MemoryLayout<FilmUniforms>.stride, index: 0)
            encoder.setBytes(&grade, length: MemoryLayout<GradeUniforms>.stride, index: 1)
        }
        return output
    }

    /// Copies `source` into a pixel buffer (any Metal-compatible RGB format), e.g. for export.
    public func copy(_ source: MTLTexture, to pixelBuffer: CVPixelBuffer, format: MTLPixelFormat,
                     into commandBuffer: MTLCommandBuffer) throws {
        let target = try context.texture(from: pixelBuffer, plane: 0, format: format)
        guard let texture = CVMetalTextureGetTexture(target) else { throw RenderError.unsupportedPixelBuffer }
        context.dispatch("copy_texture", on: commandBuffer, size: (texture.width, texture.height)) { encoder in
            encoder.setTextures([source, texture], range: 0..<2)
        }
        commandBuffer.retain(target)
    }

    /// Draws `image` into a render pass (e.g. a view's drawable), scaled into `rect` (in drawable pixels).
    public func present(_ image: MTLTexture, in rect: CGRect, pass: MTLRenderPassDescriptor,
                        into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setViewport(MTLViewport(
            originX: rect.minX, originY: rect.minY, width: rect.width, height: rect.height, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(context.presentPipeline)
        encoder.setFragmentTexture(image, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: Passes

    private func decode(_ pixelBuffer: CVPixelBuffer, settings: GradeSettings, orientation: CGAffineTransform,
                        size: (Int, Int), into commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else { throw RenderError.unsupportedPixelBuffer }
        let luma = try context.texture(from: pixelBuffer, plane: 0, format: .r16Unorm)
        let chroma = try context.texture(from: pixelBuffer, plane: 1, format: .rg16Unorm)
        guard let lumaTexture = CVMetalTextureGetTexture(luma), let chromaTexture = CVMetalTextureGetTexture(chroma)
        else { throw RenderError.unsupportedPixelBuffer }

        let output = try texture("working", width: size.0, height: size.1)
        let profile = settings.cameraProfile
        var uniforms = InputTransform.uniforms(
            settings, ycbcr: pixelBuffer.ycbcrMatrix ?? profile.defaultMatrix, orientation: orientation,
            bufferSize: CGSize(width: lumaTexture.width, height: lumaTexture.height))
        let table = try decodeTable(profile.transfer)
        context.dispatch("input_transform", on: commandBuffer, size: size) { encoder in
            encoder.setTextures([lumaTexture, chromaTexture, output], range: 0..<3)
            encoder.setBytes(&uniforms, length: MemoryLayout<InputUniforms>.stride, index: 0)
            encoder.setBuffer(table, offset: 0, index: 1)
        }
        // CVMetalTextures must outlive the GPU work that reads them.
        commandBuffer.retain(luma, chroma)
        return output
    }

    private func lightEffects(_ working: MTLTexture, _ e: EffectParameters,
                              into commandBuffer: MTLCommandBuffer) throws -> (MTLTexture, MTLTexture) {
        guard let empty = emptyTexture else { throw RenderError.textureCreation }
        guard e.hasBloom || e.hasHalation else { return (empty, empty) }

        let width = max(1, Int(Double(working.width) * EffectParameters.lightScale))
        let height = max(1, Int(Double(working.height) * EffectParameters.lightScale))
        let source = try texture("light", width: width, height: height)
        var uniforms = PrefilterUniforms(
            thresholds: SIMD4(Float(e.hasBloom ? e.bloomThreshold : 1e6),
                              Float(e.hasHalation ? e.halationThreshold : 1e6), 24, 0),
            luminance: WorkingSpace.luminance.float4)
        context.dispatch("effects_prefilter", on: commandBuffer, size: (width, height)) { encoder in
            encoder.setTextures([working, source], range: 0..<2)
            encoder.setBytes(&uniforms, length: MemoryLayout<PrefilterUniforms>.stride, index: 0)
        }
        let bloom = e.hasBloom ? try blurred(source, sigma: e.bloomSigma, key: "bloom", into: commandBuffer) : empty
        let halation = e.hasHalation
            ? try blurred(source, sigma: e.halationSigma, key: "halation", into: commandBuffer) : empty
        return (bloom, halation)
    }

    private func grainTexture(_ e: EffectParameters, frameIndex: Int, aspect: Double,
                              into commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard e.hasGrain else { return try emptyTexture.orThrow() }
        let height = Int(e.grainCanvasHeight)
        let width = Int((e.grainCanvasHeight * aspect).rounded())
        let noise = try texture("grain-noise", width: width, height: height)
        var seed = SIMD4<UInt32>(UInt32(truncatingIfNeeded: frameIndex), 0x45_4D_55_4C, 0, 0)
        context.dispatch("grain_generate", on: commandBuffer, size: (width, height)) { encoder in
            encoder.setTexture(noise, index: 0)
            encoder.setBytes(&seed, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
        }
        let grain = e.grainSigma > 0.5
            ? try blurred(noise, sigma: e.grainSigma, key: "grain-blur", into: commandBuffer) : noise

        // The grain canvas never drops below 1080 lines; smaller previews sample a filtered mip level.
        let mipmapped = try texture("grain", width: width, height: height, mipmapped: true)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw RenderError.textureCreation }
        blit.copy(from: grain, sourceSlice: 0, sourceLevel: 0, to: mipmapped, destinationSlice: 0,
                  destinationLevel: 0, sliceCount: 1, levelCount: 1)
        blit.generateMipmaps(for: mipmapped)
        blit.endEncoding()
        return mipmapped
    }

    private func blurred(_ source: MTLTexture, sigma: Double, key: String,
                         into commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let output = try texture(key, width: source.width, height: source.height)
        let quantized = Float((sigma * 8).rounded() / 8)
        let blur = blurs[quantized] ?? {
            let kernel = MPSImageGaussianBlur(device: context.device, sigma: quantized)
            kernel.edgeMode = .clamp
            blurs[quantized] = kernel
            return kernel
        }()
        blur.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: output)
        return output
    }

    // MARK: Resources

    private func texture(_ key: String, width: Int, height: Int, mipmapped: Bool = false) throws -> MTLTexture {
        if let existing = textures[key], existing.width == width, existing.height == height { return existing }
        let texture = try context.makeTexture(width: width, height: height, mipmapped: mipmapped)
        textures[key] = texture
        return texture
    }

    private func decodeTable(_ transfer: TransferFunction) throws -> MTLBuffer {
        if let table = decodeTables[transfer] { return table }
        let values = LUTBaker.decodeLUT(transfer)
        guard let buffer = context.device.makeBuffer(
            bytes: values, length: values.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        else { throw RenderError.textureCreation }
        decodeTables[transfer] = buffer
        return buffer
    }

    /// Baked looks are cached by pipeline, so switching looks back and forth (or drawing thumbnails)
    /// does not rebake.
    private func filmLUT(_ key: LUTKey) throws -> MTLTexture {
        if let lut = filmLUTs[key] {
            filmLUTOrder.removeAll { $0 == key }
            filmLUTOrder.append(key)
            return lut
        }
        let size = key.size
        let data = LUTBaker.filmLUT(try key.pipeline.makeRenderer(), size: size)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = .shaderRead
        guard let lut = context.device.makeTexture(descriptor: descriptor) else { throw RenderError.textureCreation }
        data.withUnsafeBytes { bytes in
            lut.replace(region: MTLRegionMake3D(0, 0, 0, size, size, size), mipmapLevel: 0, slice: 0,
                        withBytes: bytes.baseAddress!, bytesPerRow: size * 8, bytesPerImage: size * size * 8)
        }
        filmLUTs[key] = lut
        filmLUTOrder.append(key)
        if filmLUTOrder.count > lutCacheCapacity { filmLUTs[filmLUTOrder.removeFirst()] = nil }
        return lut
    }
}

extension CVPixelBuffer {
    /// The Y'CbCr matrix the decoder attached to this frame, if it is one we support.
    var ycbcrMatrix: CameraProfile.YCbCrMatrix? {
        guard let value = CVBufferCopyAttachment(self, kCVImageBufferYCbCrMatrixKey, nil) as? String else {
            return nil
        }
        switch value as CFString {
        case kCVImageBufferYCbCrMatrix_ITU_R_2020: return .rec2020
        case kCVImageBufferYCbCrMatrix_ITU_R_709_2: return .rec709
        default: return nil
        }
    }
}

extension Optional {
    func orThrow() throws -> Wrapped {
        guard let self else { throw RenderError.textureCreation }
        return self
    }
}
