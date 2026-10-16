import CoreVideo
import EmulistCore
import Observation

/// Live previews of every stock on the current frame, so choosing a look is visual rather than by name.
/// Rendered through the same engine as the viewer (texture effects off for clarity at thumbnail size).
@MainActor @Observable
final class StockThumbnails {
    private(set) var images: [String: CGImage] = [:]

    @ObservationIgnored private var frame: CVPixelBuffer?
    @ObservationIgnored private var settings = GradeSettings()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private lazy var renderer: FrameRenderer? = (try? MetalContext.make()).map(FrameRenderer.init)

    private static let height = 150.0

    func reset(settings: GradeSettings) {
        frame = nil
        images = [:]
        self.settings = settings
    }

    func frameChanged(_ buffer: CVPixelBuffer) {
        frame = buffer
        schedule()
    }

    func settingsChanged(_ next: GradeSettings) {
        let changed = Self.thumbnailLook(next, stock: FilmStock.builtIn[0]) != Self.thumbnailLook(settings, stock: FilmStock.builtIn[0])
        settings = next
        if changed { schedule() }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    private func render() {
        guard let frame, let renderer else { return }
        let scale = min(1, Self.height / Double(CVPixelBufferGetHeight(frame)))
        for stock in FilmStock.builtIn {
            let look = Self.thumbnailLook(settings, stock: stock)
            guard let commandBuffer = renderer.context.queue.makeCommandBuffer(),
                  let texture = try? renderer.encode(frame, frameIndex: 0, settings: look,
                                                     options: .init(scale: scale), into: commandBuffer)
            else { continue }
            commandBuffer.commit()
            images[stock.id] = try? renderer.makeImage(from: texture, output: look.output)
        }
    }

    /// The user's grade with `stock` chosen and texture effects off.
    private static func thumbnailLook(_ settings: GradeSettings, stock: FilmStock) -> GradeSettings {
        var look = settings
        look.select(stock)
        look.grain.enabled = false
        look.halation.enabled = false
        look.bloom.enabled = false
        return look
    }
}
