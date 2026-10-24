import EmulistCore
import MetalKit
import SwiftUI

/// The color-managed GPU viewer. Each display refresh it pulls the newest decoded frame and re-renders
/// only when the frame, the grade, the compare state, the view size or the scopes on screen changed.
struct ViewerView: NSViewRepresentable {
    let workspace: Workspace
    let scopes: ScopeDisplays

    func makeCoordinator() -> ViewerCoordinator { ViewerCoordinator(workspace: workspace, scopes: scopes) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.renderer?.context.device
        view.colorPixelFormat = MetalContext.presentPixelFormat
        view.framebufferOnly = true
        // Driven by our own display link rather than MTKView's internal timer, which can stay stopped
        // after the window is hidden and shown again (e.g. opening a clip while the app is hidden).
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 0.045, green: 0.045, blue: 0.045, alpha: 1)
        view.delegate = context.coordinator
        context.coordinator.drive(view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    static func dismantleNSView(_ view: MTKView, coordinator: ViewerCoordinator) { coordinator.stop() }
}

@MainActor
final class ViewerCoordinator: NSObject, MTKViewDelegate {
    private struct RenderState: Equatable {
        var frame: Int
        var settings: GradeSettings
        var beforeSplit: Double
        var scale: Double
        var draft: Bool
        var drawableSize: CGSize
        var reference: Reference?
        var scopes: [ScopeKind: CGSize]
    }

    /// What the left of a wipe against another clip shows.
    private struct Reference: Equatable {
        var clipID: UUID
        var settings: GradeSettings
        var split: Double
    }

    /// What the cached reference render depends on.
    private struct ReferenceKey: Equatable {
        var clipID: UUID
        var settings: GradeSettings
        var height: Int
    }

    let renderer: FrameRenderer?
    private let workspace: Workspace
    private let scopes: ScopeDisplays
    private var frame: (buffer: CVPixelBuffer, frameIndex: Int)?
    private var frameSerial = 0
    /// The clip on screen: switching clips resets the frame, even between two clips of the same file.
    private var clipID: UUID?
    private var lastState: RenderState?
    private var wasPlaying = false
    private var displayLink: CADisplayLink?
    private weak var view: MTKView?

    // A wipe against another clip: its frame (the clip strip's, decoded once), a renderer of its own (the
    // viewer's reuses its output texture every frame) and its last render, redone only when it changes.
    private var referenceFrame: (clipID: UUID, frame: ThumbnailRenderer.Frame)?
    private var loadingReferenceID: UUID?
    private lazy var referenceRenderer = renderer.map { FrameRenderer(context: $0.context, lutCacheCapacity: 2) }
    private var referenceImage: (key: ReferenceKey, texture: MTLTexture)?

    init(workspace: Workspace, scopes: ScopeDisplays) {
        self.workspace = workspace
        self.scopes = scopes
        renderer = (try? MetalContext.make()).map { FrameRenderer(context: $0) }
        super.init()
        if renderer == nil {
            workspace.alert = AppAlert(title: "Metal unavailable", message: RenderError.noMetalDevice.localizedDescription)
        }
    }

    /// Draws `view` on every refresh of its display while it is visible, including during menu and
    /// slider tracking (common run loop modes).
    func drive(_ view: MTKView) {
        self.view = view
        let link = view.displayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        workspace.flushContinuousEdit()
        guard let view, view.window?.occlusionState.contains(.visible) == true else { return }
        view.draw()
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
        if clipID != workspace.selectedClipID {
            clipID = workspace.selectedClipID
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

        // A previewed look bakes on the draft grid, so resting on tile after tile stays quick.
        let settings = workspace.viewedSettings
        let state = RenderState(
            frame: frameSerial, settings: settings, beforeSplit: workspace.beforeSplit,
            scale: workspace.quality.scale(shortSide: min(media.width, media.height)),
            draft: workspace.isContinuousEdit || workspace.preview != nil,
            drawableSize: view.drawableSize,
            reference: workspace.referenceClip.map { Reference(clipID: $0.id, settings: $0.settings, split: workspace.splitPosition) },
            scopes: scopes.sizes)
        guard state != lastState else { return }

        let colorSpace = settings.output.colorSpace
        if view.colorspace != colorSpace { view.colorspace = colorSpace }
        // No drawable while the window is hidden: try again next refresh rather than marking it drawn.
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commandBuffer = renderer.context.queue.makeCommandBuffer() else { return }
        do {
            var image = try renderer.encode(
                frame.buffer, frameIndex: frame.frameIndex, settings: settings,
                options: .init(scale: state.scale, beforeSplit: state.beforeSplit, orientation: media.transform,
                               draft: state.draft),
                into: commandBuffer)
            if let reference = state.reference,
               let referenceTexture = try referenceTexture(reference, height: image.height, into: commandBuffer) {
                image = try renderer.wipe(image, reference: referenceTexture, split: reference.split, into: commandBuffer)
            }
            let rect = aspectFitRect(content: CGSize(width: image.width, height: image.height), in: view.drawableSize)
            renderer.context.present(image, in: rect, pass: pass, into: commandBuffer)
            commandBuffer.present(drawable)
            if !state.scopes.isEmpty { try scopes.draw(image, into: commandBuffer) }
            lastState = state
        } catch {
            lastState = state
            workspace.alert = AppAlert(title: "Rendering failed", message: error.localizedDescription)
        }
        commandBuffer.commit()
    }
}

extension ViewerCoordinator {
    /// The reference clip's graded frame, about as tall as the viewer's image. Nil until its frame is decoded.
    private func referenceTexture(_ reference: Reference, height: Int,
                                  into commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        guard let loaded = referenceFrame, loaded.clipID == reference.clipID else {
            loadReferenceFrame(reference.clipID)
            return nil
        }
        let key = ReferenceKey(clipID: reference.clipID, settings: reference.settings, height: height)
        if let referenceImage, referenceImage.key == key { return referenceImage.texture }
        guard let referenceRenderer else { return nil }
        let frame = loaded.frame
        let upright = frame.orientation.uprightSize(
            CGSize(width: CVPixelBufferGetWidth(frame.buffer), height: CVPixelBufferGetHeight(frame.buffer)))
        let texture = try referenceRenderer.encode(
            frame.buffer, frameIndex: 0, settings: reference.settings,
            options: .init(scale: min(1, Double(height) / upright.height), orientation: frame.orientation),
            into: commandBuffer)
        referenceImage = (key, texture)
        return texture
    }

    private func loadReferenceFrame(_ clipID: UUID) {
        guard loadingReferenceID != clipID, let media = workspace.clips.first(where: { $0.id == clipID })?.media else { return }
        loadingReferenceID = clipID
        Task { [weak self] in
            guard let frame = await ThumbnailRenderer.shared.frame(forClip: clipID, media: media), let self else { return }
            referenceFrame = (clipID, frame)
            lastState = nil // draw again, now with the reference
        }
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
                    divider(in: rect, left: "BEFORE", right: "AFTER")
                case .reference:
                    divider(in: rect, left: workspace.referenceClip?.name.uppercased() ?? "", right: "THIS CLIP")
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isWipe, rect.width > 0 else { return }
                workspace.splitPosition = min(1, max(0, (value.location.x - rect.minX) / rect.width))
            }, including: isWipe ? .all : .none)
        }
    }

    private var isWipe: Bool { workspace.compare == .split || workspace.compare == .reference }

    @ViewBuilder
    private func divider(in rect: CGRect, left: String, right: String) -> some View {
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
        HStack {
            label(left)
            Spacer()
            label(right)
        }
        .padding(.horizontal, 12)
        .frame(width: rect.width)
        .position(x: rect.midX, y: rect.minY + 22)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).tracking(1.2)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
    }
}
