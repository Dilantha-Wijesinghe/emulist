import CoreVideo
import Metal

public enum RenderError: LocalizedError {
    case noMetalDevice
    case shaderCompilation(String)
    case textureCreation
    case unsupportedPixelBuffer

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice: "This Mac has no Metal GPU available."
        case .shaderCompilation(let detail): "The image engine failed to start. \(detail)"
        case .textureCreation: "The GPU could not allocate memory for this frame."
        case .unsupportedPixelBuffer: "This video frame format is not supported."
        }
    }
}

/// Immutable GPU state shared by every renderer: device, queue, compiled pipelines, texture cache.
public final class MetalContext: @unchecked Sendable {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let textureCache: CVMetalTextureCache
    let presentPipeline: MTLRenderPipelineState
    private let computePipelines: [String: MTLComputePipelineState]

    public static let presentPixelFormat = MTLPixelFormat.rgba16Float

    public static func make() throws -> MetalContext { try shared.get() }
    private static let shared = Result { try MetalContext() }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw RenderError.noMetalDevice
        }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            let options = MTLCompileOptions()
            if #available(macOS 15.0, *) {
                options.mathMode = .safe
            } else {
                options.fastMathEnabled = false
            }
            library = try device.makeLibrary(source: ShaderSource.code, options: options)
        } catch {
            throw RenderError.shaderCompilation(error.localizedDescription)
        }

        var pipelines: [String: MTLComputePipelineState] = [:]
        for name in ["input_transform", "effects_prefilter", "grain_generate", "film_render", "copy_texture"] {
            guard let function = library.makeFunction(name: name) else { throw RenderError.shaderCompilation(name) }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        computePipelines = pipelines

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "present_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "present_fragment")
        descriptor.colorAttachments[0].pixelFormat = Self.presentPixelFormat
        presentPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let cache else { throw RenderError.textureCreation }
        textureCache = cache
    }

    func pipeline(_ name: String) -> MTLComputePipelineState { computePipelines[name]! }

    /// Dispatches a compute kernel over a 2D grid.
    func dispatch(
        _ name: String, on commandBuffer: MTLCommandBuffer, size: (width: Int, height: Int),
        configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        let state = pipeline(name)
        encoder.setComputePipelineState(state)
        configure(encoder)
        let w = state.threadExecutionWidth
        let h = max(1, state.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: size.width, height: size.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
    }

    func makeTexture(
        width: Int, height: Int, format: MTLPixelFormat = .rgba16Float, mipmapped: Bool = false
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(width, 1), height: max(height, 1), mipmapped: mipmapped)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.textureCreation }
        return texture
    }

    /// Wraps one plane of a pixel buffer as a Metal texture without copying.
    func texture(from pixelBuffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) throws -> CVMetalTexture {
        let planar = CVPixelBufferIsPlanar(pixelBuffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, format, width, height, plane, &texture)
        guard status == kCVReturnSuccess, let texture else { throw RenderError.unsupportedPixelBuffer }
        return texture
    }
}

/// Keeps Core Video wrappers alive until the GPU has finished with the textures they back.
private struct Retained: @unchecked Sendable {
    let objects: [Any]
}

extension MTLCommandBuffer {
    func retain(_ objects: Any...) {
        let retained = Retained(objects: objects)
        addCompletedHandler { _ in _ = retained }
    }
}
