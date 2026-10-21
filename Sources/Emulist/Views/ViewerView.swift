import EmulistCore
import MetalKit
import SwiftUI

/// The color-managed GPU viewer. Each display refresh it pulls the newest decoded frame and re-renders
/// only when the frame, the grade, the compare state or the view size changed.
struct ViewerView: NSViewRepresentable {
    let workspace: Workspace

    func makeCoordinator() -> ViewerCoordinator { ViewerCoordinator(workspace: workspace) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.renderer?.context.device
        view.colorPixelFormat = MetalContext.presentPixelFormat
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.clearColor = MTLClearColor(red: 0.045, green: 0.045, blue: 0.045, alpha: 1)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}
}

@MainActor
final class ViewerCoordinator: NSObject, MTKViewDelegate {
    private struct RenderState: Equatable {
        var frame: Int
        var settings: GradeSettings
        var beforeSplit: Double
        var scale: Double
        var drawableSize: CGSize
    }

    let renderer: FrameRenderer?
    private let workspace: Workspace
    private var frame: (buffer: CVPixelBuffer, frameIndex: Int)?
    private var frameSerial = 0
    private var mediaURL: URL?
    private var lastState: RenderState?
    private var wasPlaying = false

    init(workspace: Workspace) {
        self.workspace = workspace
        renderer = (try? MetalContext.make()).map { FrameRenderer(context: $0) }
        super.init()
        if renderer == nil {
            workspace.alert = AppAlert(title: "Metal unavailable", message: RenderError.noMetalDevice.localizedDescription)
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        guard let renderer, let media = workspace.media else {
            frame = nil
            return
        }
        if mediaURL != media.url {
            mediaURL = media.url
            frame = nil
            lastState = nil
        }
        let playback = workspace.playback
        if let next = playback.nextFrame(force: frame == nil) {
            frame = next
            frameSerial += 1
            if !playback.isPlaying { workspace.thumbnails.frameChanged(next.buffer) }
        }
        guard let frame else { return }
        // Stock previews follow the frame you stop on.
        if wasPlaying, !playback.isPlaying { workspace.thumbnails.frameChanged(frame.buffer) }
        wasPlaying = playback.isPlaying

        let settings = workspace.settings
        let state = RenderState(
            frame: frameSerial, settings: settings, beforeSplit: workspace.beforeSplit,
            scale: workspace.quality.scale(shortSide: min(media.width, media.height)), drawableSize: view.drawableSize)
        guard state != lastState else { return }

        let colorSpace = settings.output.colorSpace
        if view.colorspace != colorSpace { view.colorspace = colorSpace }
        guard let commandBuffer = renderer.context.queue.makeCommandBuffer() else { return }
        do {
            let image = try renderer.encode(
                frame.buffer, frameIndex: frame.frameIndex, settings: settings,
                options: .init(scale: state.scale, beforeSplit: state.beforeSplit, orientation: media.transform),
                into: commandBuffer)
            present(image, in: view, commandBuffer: commandBuffer)
            lastState = state
        } catch {
            lastState = state
            workspace.alert = AppAlert(title: "Rendering failed", message: error.localizedDescription)
        }
        commandBuffer.commit()
    }

    private func present(_ image: MTLTexture, in view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let renderer, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        let rect = aspectFitRect(content: CGSize(width: image.width, height: image.height), in: view.drawableSize)
        renderer.present(image, in: rect, pass: pass, into: commandBuffer)
        commandBuffer.present(drawable)
    }
}

/// Draggable before/after wipe drawn over the image.
struct CompareOverlay: View {
    @Bindable var workspace: Workspace
    let contentSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let rect = aspectFitRect(content: contentSize, in: geometry.size)
            ZStack(alignment: .topLeading) {
                switch workspace.compare {
                case .off:
                    EmptyView()
                case .before:
                    label("BEFORE").position(x: rect.minX + 44, y: rect.minY + 22)
                case .split:
                    let x = rect.minX + rect.width * workspace.splitPosition
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 1, height: rect.height)
                        .position(x: x, y: rect.midY)
                    Circle()
                        .fill(.black.opacity(0.55))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold)))
                        .frame(width: 28, height: 28)
                        .position(x: x, y: rect.midY)
                    label("BEFORE").position(x: rect.minX + 44, y: rect.minY + 22)
                    label("AFTER").position(x: rect.maxX - 40, y: rect.minY + 22)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard workspace.compare == .split, rect.width > 0 else { return }
                workspace.splitPosition = min(1, max(0, (value.location.x - rect.minX) / rect.width))
            }, including: workspace.compare == .split ? .all : .none)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).tracking(1.2)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
    }
}
