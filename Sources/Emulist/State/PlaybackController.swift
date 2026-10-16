import AVFoundation
import EmulistCore
import Observation

/// AVPlayer-driven playback. Audio plays normally; decoded frames are pulled by the viewer on each display
/// refresh through an `AVPlayerItemVideoOutput`, already in the Y'CbCr format the renderer expects.
/// `currentTime` tracks the frame most recently handed to the viewer.
@MainActor @Observable
final class PlaybackController {
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var output: AVPlayerItemVideoOutput?
    @ObservationIgnored private var endWatcher: Task<Void, Never>?

    private(set) var info: MediaInfo?
    private(set) var currentTime = 0.0
    private(set) var isPlaying = false
    var isLooping = true

    var duration: Double { info?.duration ?? 0 }
    var frameRate: Double { info?.frameRate ?? 24 }

    init() {
        player.actionAtItemEnd = .pause
    }

    func load(_ info: MediaInfo) {
        let item = AVPlayerItem(url: info.url)
        let output = DecodeFormat.makePlayerOutput()
        item.add(output)
        self.output = output
        self.info = info
        player.replaceCurrentItem(with: item)
        currentTime = 0
        isPlaying = false
        endWatcher?.cancel()
        endWatcher = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item).map({ _ in () }) {
                self?.didReachEnd()
            }
        }
    }

    func unload() {
        pause()
        player.replaceCurrentItem(with: nil)
        output = nil
        info = nil
    }

    /// The newest decoded frame for display, with its frame number (nil when nothing new since last call).
    func nextFrame(force: Bool) -> (buffer: CVPixelBuffer, frameIndex: Int)? {
        guard let output, let info else { return nil }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard force || output.hasNewPixelBuffer(forItemTime: time) else { return nil }
        var displayTime = CMTime.zero
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayTime) else { return nil }
        // The timecode follows the frame actually on screen.
        if displayTime.isNumeric { currentTime = displayTime.seconds }
        return (buffer, info.frameIndex(at: displayTime.seconds))
    }

    // MARK: Transport

    func togglePlayback() { isPlaying ? pause() : play() }

    func play() {
        guard info != nil else { return }
        if currentTime >= duration - 1 / frameRate { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(0, duration - 1 / frameRate))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func step(_ frames: Int) {
        pause()
        player.currentItem?.step(byCount: frames)
    }

    private func didReachEnd() {
        if isLooping, isPlaying {
            player.seek(to: .zero)
            player.play()
        } else {
            isPlaying = false
        }
    }
}

extension Double {
    /// HH:MM:SS:FF timecode at the given frame rate.
    func timecode(frameRate: Double) -> String {
        let fps = max(1, Int(frameRate.rounded()))
        let totalFrames = Int((self * frameRate).rounded())
        let frames = totalFrames % fps
        let seconds = totalFrames / fps
        return String(format: "%02d:%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60, frames)
    }
}
