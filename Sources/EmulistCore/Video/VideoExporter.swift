import AVFoundation
import Metal
import VideoToolbox

public struct ExportSettings: Codable, Equatable, Sendable {
    public enum Codec: String, Codable, CaseIterable, Identifiable, Sendable {
        case proRes422HQ = "prores"
        case hevc
        case h264

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .proRes422HQ: "Apple ProRes 422 HQ"
            case .hevc: "HEVC (H.265) 10-bit"
            case .h264: "H.264"
            }
        }

        public var detail: String {
            switch self {
            case .proRes422HQ: "Mastering quality. Large files."
            case .hevc: "Excellent quality, small files. Best for sharing."
            case .h264: "Plays everywhere."
            }
        }

        public var fileType: AVFileType { self == .proRes422HQ ? .mov : .mp4 }
        public var fileExtension: String { self == .proRes422HQ ? "mov" : "mp4" }

        var avCodec: AVVideoCodecType {
            switch self {
            case .proRes422HQ: .proRes422HQ
            case .hevc: .hevc
            case .h264: .h264
            }
        }

        /// Pixel format handed to the encoder; 16-bit float keeps 10-bit codecs free of banding.
        var pixelFormat: (cv: OSType, metal: MTLPixelFormat) {
            self == .h264 ? (kCVPixelFormatType_32BGRA, .bgra8Unorm) : (kCVPixelFormatType_64RGBAHalf, .rgba16Float)
        }

        /// Average bits per pixel per frame for the delivery codecs.
        var bitsPerPixel: Double? {
            switch self {
            case .proRes422HQ: nil
            case .hevc: 0.18
            case .h264: 0.28
            }
        }
    }

    public enum Resolution: String, Codable, CaseIterable, Identifiable, Sendable {
        case source, uhd, hd

        public var id: String { rawValue }
        public var name: String {
            switch self {
            case .source: "Source"
            case .uhd: "2160p"
            case .hd: "1080p"
            }
        }

        /// Scale relative to the source, never upscaling.
        func scale(sourceHeight: Int) -> Double {
            switch self {
            case .source: 1
            case .uhd: min(1, 2160 / Double(sourceHeight))
            case .hd: min(1, 1080 / Double(sourceHeight))
            }
        }
    }

    public var codec: Codec = .hevc
    public var resolution: Resolution = .source
    public var includeAudio = true

    public init(codec: Codec = .hevc, resolution: Resolution = .source, includeAudio: Bool = true) {
        self.codec = codec
        self.resolution = resolution
        self.includeAudio = includeAudio
    }
}

public enum ExportError: LocalizedError {
    case cannotWrite(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cannotWrite(let detail): "The export couldn’t be written. \(detail)"
        case .cancelled: "The export was cancelled."
        }
    }
}

/// Renders a clip through the same `FrameRenderer` as the viewer, in timestamp order, at full quality.
public final class VideoExporter: @unchecked Sendable {
    private let info: MediaInfo
    private let settings: GradeSettings
    private let export: ExportSettings
    private let destination: URL
    private let temporary: URL
    private let lock = NSLock()
    private var cancelled = false

    public init(info: MediaInfo, settings: GradeSettings, export: ExportSettings, destination: URL) throws {
        self.info = info
        self.settings = settings
        self.export = export
        self.destination = destination
        temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(export.codec.fileExtension)")
    }

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    public func run(progress: @escaping @Sendable (Double) -> Void) async throws {
        defer { try? FileManager.default.removeItem(at: temporary) }
        let scale = export.resolution.scale(sourceHeight: info.height)
        let width = Int((Double(info.width) * scale).rounded()) & ~1
        let height = Int((Double(info.height) * scale).rounded()) & ~1

        let writer = try AVAssetWriter(outputURL: temporary, fileType: export.codec.fileType)
        let video = try await VideoPump(
            info: info, settings: settings, codec: export.codec, scale: scale, writer: writer,
            outputSettings: videoSettings(width: width, height: height), size: (width, height))
        let audio = export.includeAudio ? try await AudioPassthrough(info: info, writer: writer, codec: export.codec) : nil

        guard writer.startWriting() else { throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        let isCancelled: @Sendable () -> Bool = { [self] in self.isCancelled }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await video.run(isCancelled: isCancelled, progress: progress) }
            if let audio { group.addTask { try await audio.run(isCancelled: isCancelled) } }
            try await group.waitForAll()
        }

        if isCancelled() {
            writer.cancelWriting()
            throw ExportError.cancelled
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
    }

    private func videoSettings(width: Int, height: Int) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: export.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        var compression: [String: Any] = [:]
        if let bpp = export.codec.bitsPerPixel {
            compression[AVVideoAverageBitRateKey] = Int(Double(width * height) * info.frameRate * bpp)
            compression[AVVideoExpectedSourceFrameRateKey] = info.frameRate
        }
        if export.codec == .hevc {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }
        if !compression.isEmpty { settings[AVVideoCompressionPropertiesKey] = compression }
        return settings
    }
}

/// Decodes, renders and encodes video frames in timestamp order. Owns all of its GPU and AV state.
private final class VideoPump: @unchecked Sendable {
    private let info: MediaInfo
    private let settings: GradeSettings
    private let options: FrameRenderer.Options
    private let format: (cv: OSType, metal: MTLPixelFormat)
    private let context: MetalContext
    private let renderer: FrameRenderer
    private let frames: FrameReader
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    init(info: MediaInfo, settings: GradeSettings, codec: ExportSettings.Codec, scale: Double, writer: AVAssetWriter,
         outputSettings: [String: Any], size: (width: Int, height: Int)) async throws {
        self.info = info
        self.settings = settings
        self.writer = writer
        options = FrameRenderer.Options(scale: scale)
        format = codec.pixelFormat
        context = try MetalContext.make()
        renderer = FrameRenderer(context: context)
        frames = try await FrameReader(info: info)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: format.cv,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        writer.add(input)
    }

    func run(isCancelled: @escaping @Sendable () -> Bool, progress: @escaping @Sendable (Double) -> Void) async throws {
        let total = Double(info.frameCount)
        try await input.drain(on: "emulist.export.video") { [self] in
            guard !isCancelled(), let frame = try frames.next() else { return false }
            try write(frame.pixelBuffer, at: frame.time)
            progress(min(1, (frame.time.seconds * info.frameRate + 1) / total))
            return true
        }
        if isCancelled() { frames.cancel() }
    }

    private func write(_ source: CVPixelBuffer, at time: CMTime) throws {
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.cannotWrite("No buffer pool.") }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output, let commandBuffer = context.queue.makeCommandBuffer() else {
            throw ExportError.cannotWrite("Out of memory.")
        }
        output.tagRec709()
        let rendered = try renderer.encode(
            source, frameIndex: info.frameIndex(at: time.seconds), settings: settings, options: options,
            into: commandBuffer)
        try renderer.copy(rendered, to: output, format: format.metal, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard adaptor.append(output, withPresentationTime: time) else {
            throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "")
        }
    }
}

/// Copies the source audio into the export: passthrough for MOV, AAC for MP4.
private final class AudioPassthrough: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let input: AVAssetWriterInput

    init?(info: MediaInfo, writer: AVAssetWriter, codec: ExportSettings.Codec) async throws {
        let asset = AVURLAsset(url: info.url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        reader = try AVAssetReader(asset: asset)
        if codec.fileType == .mov {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let hint = try await track.load(.formatDescriptions).first
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
        } else {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 256_000,
            ])
        }
        input.expectsMediaDataInRealTime = false
        reader.add(output)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
    }

    func run(isCancelled: @escaping @Sendable () -> Bool) async throws {
        guard reader.startReading() else { throw ExportError.cannotWrite("Audio couldn’t be read.") }
        try await input.drain(on: "emulist.export.audio") { [self] in
            guard !isCancelled(), let sample = output.copyNextSampleBuffer() else { return false }
            return input.append(sample)
        }
    }
}

private extension AVAssetWriterInput {
    /// Feeds the input whenever it is ready until `next` returns false, then marks it finished.
    func drain(on queue: String, next: @escaping @Sendable () throws -> Bool) async throws {
        let box = ResumeOnce()
        nonisolated(unsafe) let input = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: queue)) {
                while input.isReadyForMoreMediaData {
                    do {
                        if try !next() {
                            input.markAsFinished()
                            box.resume(continuation, with: .success(()))
                            return
                        }
                    } catch {
                        input.markAsFinished()
                        box.resume(continuation, with: .failure(error))
                        return
                    }
                }
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
        lock.withLock {
            guard !done else { return }
            done = true
            continuation.resume(with: result)
        }
    }
}

private extension CVPixelBuffer {
    func tagRec709() {
        CVBufferSetAttachments(self, [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ] as CFDictionary, .shouldPropagate)
    }
}
