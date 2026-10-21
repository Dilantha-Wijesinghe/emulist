import CoreVideo
import EmulistCore
import Observation

/// Live previews of every look on the current frame, so choosing a look is visual rather than by name.
/// Rendered off the main thread through the same engine as the viewer, on a coarser LUT grid, with
/// texture effects off for clarity at thumbnail size.
@MainActor @Observable
final class StockThumbnails {
    private(set) var images: [String: CGImage] = [:]

    @ObservationIgnored private var frame: CVPixelBuffer?
    @ObservationIgnored private var settings = GradeSettings()
    @ObservationIgnored private var orientation = CGAffineTransform.identity
    @ObservationIgnored private var looks: [FilmStock] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let renderer = ThumbnailRenderer()

    func reset(settings: GradeSettings, orientation: CGAffineTransform, looks: [FilmStock]) {
        frame = nil
        images = [:]
        self.settings = settings
        self.orientation = orientation
        self.looks = looks
    }

    func frameChanged(_ buffer: CVPixelBuffer) {
        frame = buffer
        schedule()
    }

    func looksChanged(_ next: [FilmStock]) {
        looks = next
        schedule()
    }

    func settingsChanged(_ next: GradeSettings) {
        let changed = ThumbnailRenderer.look(next, stock: FilmStock.builtIn[0])
            != ThumbnailRenderer.look(settings, stock: FilmStock.builtIn[0])
        settings = next
        if changed { schedule() }
    }

    private func schedule() {
        pending?.cancel()
        guard let frame else { return }
        let job = ThumbnailRenderer.Job(frame: frame, settings: settings, orientation: orientation, looks: looks)
        pending = Task { [weak self, renderer] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let images = await renderer.render(job)
            guard !Task.isCancelled else { return }
            self?.images = images
        }
    }
}

/// Owns a GPU renderer; the actor serializes jobs so the renderer is never used concurrently.
actor ThumbnailRenderer {
    struct Job: @unchecked Sendable { // CVPixelBuffer is immutable once decoded
        let frame: CVPixelBuffer
        let settings: GradeSettings
        let orientation: CGAffineTransform
        let looks: [FilmStock]
    }

    private static let height = 150.0
    private lazy var renderer: FrameRenderer? = (try? MetalContext.make())
        .map { FrameRenderer(context: $0, lutSize: 33, lutCacheCapacity: 64) }

    func render(_ job: Job) -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        if let renderer {
            let upright = job.orientation.uprightSize(
                CGSize(width: CVPixelBufferGetWidth(job.frame), height: CVPixelBufferGetHeight(job.frame)))
            let scale = min(1, Self.height / upright.height)
            for stock in job.looks {
                let look = Self.look(job.settings, stock: stock)
                guard let commandBuffer = renderer.context.queue.makeCommandBuffer(),
                      let texture = try? renderer.encode(job.frame, frameIndex: 0, settings: look,
                                                         options: .init(scale: scale, orientation: job.orientation),
                                                         into: commandBuffer)
                else { continue }
                commandBuffer.commit()
                images[stock.id] = try? renderer.makeImage(from: texture, output: look.output)
            }
        }
        return images
    }

    /// The user's grade with `stock` chosen and texture effects off.
    static func look(_ settings: GradeSettings, stock: FilmStock) -> GradeSettings {
        var look = settings
        look.select(stock)
        look.grain.enabled = false
        look.halation.enabled = false
        look.bloom.enabled = false
        return look
    }
}
