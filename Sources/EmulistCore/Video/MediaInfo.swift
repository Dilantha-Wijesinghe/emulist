import AVFoundation
import CoreVideo

public enum MediaError: LocalizedError {
    case unreadable(URL)
    case noVideoTrack
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” can’t be opened. Check that the file exists and isn’t damaged."
        case .noVideoTrack: "This file doesn’t contain a video track."
        case .decodeFailed(let detail): "This video couldn’t be decoded on this Mac. \(detail)"
        }
    }
}

/// The pixel format every decoder delivers: 10-bit 4:2:2 video-range Y'CbCr, Metal-compatible.
/// Asking for Y'CbCr (not RGB) keeps AVFoundation from applying any color conversion of its own.
public enum DecodeFormat {
    public static let pixelFormat = kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange

    public static var attributes: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
        ]
    }

    /// A player output that delivers frames in this format.
    public static func makePlayerOutput() -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
    }
}

/// What we know about a clip after inspecting it.
public struct MediaInfo: Sendable, Equatable {
    public var url: URL
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var duration: Double
    public var codec: String
    public var colorPrimaries: String?
    public var transferFunction: String?
    /// Reverse-DNS identifier of a LOG curve declared by the camera (e.g. Apple Log), if any.
    public var logTransferFunction: String?
    public var hasAudio: Bool
    /// The track's display transform (e.g. a 90° rotation for footage shot vertically).
    public var transform: CGAffineTransform = .identity
    /// A camera profile we can identify with confidence from the file's metadata, if any.
    public var detectedProfile: CameraProfile?

    public var frameCount: Int { max(1, Int((duration * frameRate).rounded())) }
    public var resolutionLabel: String { "\(width)×\(height)" }

    /// Frame number for a presentation time. Playback and export use this same mapping, so grain is identical.
    public func frameIndex(at seconds: Double) -> Int { Int((seconds * frameRate).rounded()) }

    public static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) == true else { throw MediaError.unreadable(url) }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }

        let (size, transform, rate, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        let oriented = size.applying(transform)
        let duration = try await asset.load(.duration).seconds
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        let format = formats.first
        let extensions = format.flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] } ?? [:]
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let log = extensions[kCMFormatDescriptionExtension_LogTransferFunction as String] as? String
        let metadata = try await asset.load(.metadata)
        func string(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first
            else { return nil }
            return try? await item.load(.stringValue)
        }
        let recorder = Recorder(software: await string(.quickTimeMetadataSoftware),
                                model: await string(.quickTimeMetadataModel))

        return MediaInfo(
            url: url, width: Int(abs(oriented.width)), height: Int(abs(oriented.height)),
            frameRate: rate > 0 ? Double(rate) : 30, duration: duration,
            codec: format.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?",
            colorPrimaries: primaries, transferFunction: transfer, logTransferFunction: log, hasAudio: hasAudio,
            transform: transform,
            detectedProfile: detectProfile(log: log, transfer: transfer, primaries: primaries, recorder: recorder))
    }

    /// The app and device that recorded a clip, from its QuickTime metadata.
    struct Recorder {
        var software: String?
        var model: String?
    }

    /// Only claims a profile when the metadata is explicit (or unambiguous); otherwise the user is asked.
    static func detectProfile(log: String?, transfer: String?, primaries: String? = nil,
                              recorder: Recorder = Recorder()) -> CameraProfile? {
        if log == kCMFormatDescriptionLogTransferFunction_AppleLog as String { return .appleLog }
        let transferName = transfer?.lowercased() ?? ""
        if transferName.contains("slog3") || transferName.contains("s-log3") { return .sLog3 }
        if transferName.contains("vlog") || transferName.contains("v-log") { return .vLog }
        // Blackmagic Camera on iPhone writes Apple Log with Rec.2020 primaries and no transfer tag (observed
        // with Blackmagic Cam 3.5). If another of its modes ever records untagged Rec.2020, Input fixes it.
        if transfer == nil, primaries == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String,
           recorder.software?.hasPrefix("Blackmagic Cam") == true, recorder.model?.hasPrefix("Apple iPhone") == true {
            return .appleLog
        }
        return nil
    }

    /// Apple Log 2 (iPhone 17 Pro and later) uses a gamut Apple hasn't published, so it can't be decoded exactly.
    public var isAppleLog2: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return logTransferFunction == kCVImageBufferLogTransferFunction_AppleLog2 as String
    }
}

private func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
}
