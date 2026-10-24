import Metal
import simd

/// The scopes Emulist draws. They read the image as it's shown: display-encoded R'G'B' (every output is
/// Rec.709), like the scopes on Resolve's color page.
public enum ScopeKind: String, CaseIterable, Identifiable, Sendable {
    case waveform, parade, vectorscope

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .waveform: "Waveform"
        case .parade: "RGB Parade"
        case .vectorscope: "Vectorscope"
        }
    }
}

/// Where colors land on the scopes. Shared by the GPU (through its uniforms) and the graticules.
public enum ScopeGeometry {
    /// The Y'CbCr matrix of the delivery signal.
    public static let matrix = CameraProfile.YCbCrMatrix.rec709
    /// Cb and Cr at the vectorscope's edge: 100% green, the most saturated color bar, sits at 0.59.
    public static let vectorRange = 0.6

    /// A color's place on the vectorscope: x along Cb, y along Cr (up), the scope's edge at 1.
    public static func vectorPoint(_ rgb: RGB) -> SIMD2<Double> { matrix.chroma(rgb) / vectorRange }

    /// The 75% color bar targets.
    public static let targets: [(label: String, point: SIMD2<Double>)] = [
        ("R", RGB(1, 0, 0)), ("Yl", RGB(1, 1, 0)), ("G", RGB(0, 1, 0)),
        ("Cy", RGB(0, 1, 1)), ("B", RGB(0, 0, 1)), ("Mg", RGB(1, 0, 1)),
    ].map { ($0, vectorPoint($1 * 0.75)) }

    /// Unit direction of the skin-tone line: the NTSC I axis (YIQ, I = 1, Q = 0 in R'G'B'), along which
    /// skin of every complexion falls, plotted with the delivery matrix. About 130° from +Cb.
    public static let skinToneDirection = simd_normalize(vectorPoint(RGB(0.956, -0.272, -1.106)))
}

/// Computes scopes of an image on the GPU. One pass bins a grid of samples of the image (four waveforms,
/// R' G' B' and Y', by column and level, plus a Cb/Cr histogram); each scope is then drawn from the bins
/// at the size it's shown, so drawing two scopes reads the image once.
///
/// Not thread-safe: the viewer owns one.
public final class ScopeRenderer: @unchecked Sendable {
    static let columns = 512
    static let levels = 512
    static let vectorBins = 256
    /// The image is sampled on a grid this wide (two samples per column, so every column gets as many)
    /// and at most this tall: a 4K frame costs what an HD one does.
    static let grid = (width: columns * 2, maxHeight: 576)

    public let context: MetalContext
    private let waveBins: MTLBuffer
    private let vectorBins: MTLBuffer
    private var uniforms: ScopeUniforms
    private var outputs: [ScopeKind: MTLTexture] = [:]

    public init(context: MetalContext) throws {
        self.context = context
        let wave = Self.columns * Self.levels * 4 * MemoryLayout<UInt32>.stride
        let vector = Self.vectorBins * Self.vectorBins * MemoryLayout<UInt32>.stride
        guard let waveBins = context.device.makeBuffer(length: wave, options: .storageModeShared),
              let vectorBins = context.device.makeBuffer(length: vector, options: .storageModeShared)
        else { throw RenderError.textureCreation }
        self.waveBins = waveBins
        self.vectorBins = vectorBins
        let (kr, kb) = ScopeGeometry.matrix.coefficients
        uniforms = ScopeUniforms(
            luma: ScopeGeometry.matrix.lumaWeights.float4,
            chroma: SIMD4(Float(1 / (2 * (1 - kb))), Float(1 / (2 * (1 - kr))), Float(ScopeGeometry.vectorRange), 0),
            bins: SIMD4(UInt32(Self.columns), UInt32(Self.levels), UInt32(Self.vectorBins), 0),
            draw: .zero)
    }

    /// Bins `image` (display-encoded R'G'B'). Call once per image, before drawing its scopes.
    public func analyze(_ image: MTLTexture, into commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.fill(buffer: waveBins, range: 0..<waveBins.length, value: 0)
        blit.fill(buffer: vectorBins, range: 0..<vectorBins.length, value: 0)
        blit.endEncoding()

        let grid = Self.grid(width: image.width, height: image.height)
        // A trace is full strength where a column's samples crowd into a few levels, and faint where they spread.
        uniforms.draw.y = Float(grid.width * grid.height) / Float(Self.columns) / 48
        uniforms.draw.z = Float(grid.width * grid.height) / Float(Self.vectorBins * Self.vectorBins) * 6
        context.dispatch("scope_analyze", on: commandBuffer, size: grid) { encoder in
            encoder.setTexture(image, index: 0)
            encoder.setBuffer(waveBins, offset: 0, index: 0)
            encoder.setBuffer(vectorBins, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<ScopeUniforms>.stride, index: 2)
        }
    }

    /// Draws a scope of the last analyzed image into a texture of `width`×`height` pixels, reused by the
    /// next call for the same kind.
    public func draw(_ kind: ScopeKind, width: Int, height: Int,
                     into commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        let output = try outputs[kind].flatMap { $0.width == width && $0.height == height ? $0 : nil }
            ?? context.makeTexture(width: width, height: height)
        outputs[kind] = output
        var uniforms = uniforms
        uniforms.draw.x = kind == .parade ? 1 : 0
        let isVector = kind == .vectorscope
        context.dispatch(isVector ? "scope_vector" : "scope_waveform", on: commandBuffer,
                         size: (output.width, output.height)) { encoder in
            encoder.setTexture(output, index: 0)
            encoder.setBuffer(isVector ? vectorBins : waveBins, offset: 0, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<ScopeUniforms>.stride, index: 1)
        }
        return output
    }

    // MARK: Binning (mirrors `scope_analyze`; used by tests)

    static func grid(width: Int, height: Int) -> (width: Int, height: Int) {
        (grid.width, max(1, min(grid.maxHeight, grid.width * height / max(width, 1))))
    }

    /// The waveform level a signal value falls in.
    static func level(_ value: Double) -> Int { min(Int(min(max(value, 0), 1) * Double(levels)), levels - 1) }

    /// The vectorscope bin (column along Cb, row along Cr) a color falls in.
    static func vectorBin(_ rgb: RGB) -> SIMD2<Int> {
        let p = (ScopeGeometry.vectorPoint(simd_clamp(rgb, .zero, RGB(repeating: 1))) * 0.5 + 0.5) * Double(vectorBins)
        return SIMD2(min(max(Int(p.x), 0), vectorBins - 1), min(max(Int(p.y), 0), vectorBins - 1))
    }

    /// Bin counts of the last analysis, once its command buffer has completed: waveform counts indexed
    /// `(level * columns + column) * 4 + channel` (R', G', B', Y'), vectorscope counts `row * size + column`.
    var counts: (wave: [UInt32], vector: [UInt32]) {
        func read(_ buffer: MTLBuffer) -> [UInt32] {
            Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt32.self, capacity: buffer.length / 4),
                                      count: buffer.length / 4))
        }
        return (read(waveBins), read(vectorBins))
    }
}
