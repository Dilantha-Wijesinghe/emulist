import AVFoundation

/// Sequential, timestamp-ordered decoding of a clip's video track (used by export and the CLI).
public final class FrameReader: @unchecked Sendable {
    public let info: MediaInfo
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    public init(info: MediaInfo, startingAt seconds: Double = 0) async throws {
        let asset = AVURLAsset(url: info.url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
        reader = try AVAssetReader(asset: asset)
        if seconds > 0 {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600), end: .positiveInfinity)
        }
        output = AVAssetReaderTrackOutput(track: track, outputSettings: DecodeFormat.attributes)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw MediaError.decodeFailed(reader.error?.localizedDescription ?? "")
        }
        self.info = info
    }

    /// The next decoded frame, or nil at the end of the clip.
    public func next() throws -> (pixelBuffer: CVPixelBuffer, time: CMTime)? {
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                return (buffer, CMSampleBufferGetPresentationTimeStamp(sample))
            }
        }
        if reader.status == .failed { throw MediaError.decodeFailed(reader.error?.localizedDescription ?? "") }
        return nil
    }

    public func cancel() { reader.cancelReading() }
}
