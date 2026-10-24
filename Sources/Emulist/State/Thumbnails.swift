import CoreVideo
import EmulistCore
import Observation

/// Renders thumbnails off the main thread through the same engine as the viewer, on a coarser LUT grid
/// and with texture effects off (grain and glow only muddy a thumbnail). One shared actor, so the GPU
/// renderer and its LUT cache are never used concurrently.
actor ThumbnailRenderer {
    static let shared = ThumbnailRenderer()

    /// A decoded frame; CVPixelBuffers are immutable once decoded, so they can cross into the actor.
    struct Frame: @unchecked Sendable {
        let buffer: CVPixelBuffer
        let orientation: CGAffineTransform
    }

    private lazy var renderer: FrameRenderer? = (try? MetalContext.make())
        .map { FrameRenderer(context: $0, lutSize: LUTBaker.draftLUTSize, lutCacheCapacity: 64) }
    private var clipFrames: [UUID: Frame] = [:]

    /// `frame` rendered with each grade, keyed by the items' ids.
    func render(_ frame: Frame, _ items: [(id: String, settings: GradeSettings)], height: Double) -> [String: CGImage] {
        guard let renderer else { return [:] }
        let upright = frame.orientation.uprightSize(
            CGSize(width: CVPixelBufferGetWidth(frame.buffer), height: CVPixelBufferGetHeight(frame.buffer)))
        let options = FrameRenderer.Options(scale: min(1, height / upright.height), orientation: frame.orientation)
        var images: [String: CGImage] = [:]
        for item in items {
            let settings = item.settings.withoutTexture
            guard let commandBuffer = renderer.context.queue.makeCommandBuffer(),
                  let texture = try? renderer.encode(frame.buffer, frameIndex: 0, settings: settings, options: options,
                                                     into: commandBuffer)
            else { continue }
            commandBuffer.commit()
            images[item.id] = try? renderer.makeImage(from: texture, output: settings.output)
        }
        return images
    }

    /// A representative frame of a clip (a second in), decoded once.
    func frame(forClip id: UUID, media: MediaInfo) async -> Frame? {
        if let frame = clipFrames[id] { return frame }
        guard let reader = try? await FrameReader(info: media, startingAt: min(1, media.duration / 2)),
              let decoded = try? reader.next() else { return nil }
        reader.cancel()
        let frame = Frame(buffer: decoded.pixelBuffer, orientation: media.transform)
        clipFrames[id] = frame
        return frame
    }

    func forgetClip(_ id: UUID) { clipFrames[id] = nil }
}

extension GradeSettings {
    /// The grade as thumbnails show it.
    var withoutTexture: GradeSettings {
        var settings = self
        settings.grain.enabled = false
        settings.halation.enabled = false
        settings.bloom.enabled = false
        return settings
    }
}

/// Live previews of every look and preset on the current frame, with the current grade applied, so
/// choosing a look is visual rather than by name.
@MainActor @Observable
final class LibraryThumbnails {
    private(set) var images: [String: CGImage] = [:]

    @ObservationIgnored private var frame: ThumbnailRenderer.Frame?
    @ObservationIgnored private var orientation = CGAffineTransform.identity
    @ObservationIgnored private var settings = GradeSettings()
    @ObservationIgnored private var looks: [FilmStock] = []
    @ObservationIgnored private var presets: [GradePreset] = []
    @ObservationIgnored private var pending: Task<Void, Never>?

    nonisolated static func id(for preset: GradePreset) -> String { "preset:\(preset.id.uuidString)" }

    /// A new clip: previews wait for its first frame.
    func reset(orientation: CGAffineTransform) {
        frame = nil
        images = [:]
        self.orientation = orientation
    }

    func frameChanged(_ buffer: CVPixelBuffer) {
        frame = ThumbnailRenderer.Frame(buffer: buffer, orientation: orientation)
        schedule()
    }

    /// Re-renders when anything a thumbnail shows has changed.
    func update(settings: GradeSettings, looks: [FilmStock], presets: [GradePreset]) {
        let changed = settings.withoutTexture != self.settings.withoutTexture
            || looks.map(\.id) != self.looks.map(\.id) || presets != self.presets
        self.settings = settings
        self.looks = looks
        self.presets = presets
        if changed { schedule() }
    }

    private func schedule() {
        pending?.cancel()
        guard let frame else { return }
        let items = looks.map { look in
            var withLook = settings
            withLook.select(look)
            return (id: look.id, settings: withLook)
        } + presets.map { (id: Self.id(for: $0), settings: $0.applied(to: settings)) }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let images = await ThumbnailRenderer.shared.render(frame, items, height: 150)
            guard !Task.isCancelled else { return }
            self?.images = images
        }
    }
}

/// A graded thumbnail per clip, for the clip strip. Only clips whose grade changed are re-rendered.
@MainActor @Observable
final class ClipThumbnails {
    private(set) var images: [UUID: CGImage] = [:]

    @ObservationIgnored private var rendered: [UUID: GradeSettings] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?

    func update(_ clips: [(id: UUID, media: MediaInfo, settings: GradeSettings)]) {
        let ids = Set(clips.map(\.id))
        for removed in rendered.keys where !ids.contains(removed) {
            rendered[removed] = nil
            images[removed] = nil
            Task { await ThumbnailRenderer.shared.forgetClip(removed) }
        }
        let stale = clips.filter { rendered[$0.id] != $0.settings.withoutTexture }
        guard !stale.isEmpty else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            for clip in stale {
                guard !Task.isCancelled,
                      let frame = await ThumbnailRenderer.shared.frame(forClip: clip.id, media: clip.media) else { continue }
                let key = clip.id.uuidString
                guard let image = await ThumbnailRenderer.shared.render(frame, [(key, clip.settings)], height: 72)[key]
                else { continue }
                self?.images[clip.id] = image
                self?.rendered[clip.id] = clip.settings.withoutTexture
            }
        }
    }
}
