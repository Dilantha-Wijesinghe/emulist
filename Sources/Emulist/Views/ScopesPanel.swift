import EmulistCore
import MetalKit
import SwiftUI

/// Waveform or RGB parade above a vectorscope, beside the viewer. They read the image exactly as the
/// viewer shows it (a split or a wipe included), so the parade's columns line up with the picture.
struct ScopesPanel: View {
    @Bindable var layout: WindowLayout
    let displays: ScopeDisplays

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SCOPES").captionStyle()
                Spacer()
                SelectorSwitch(selection: $layout.traceScope, options: [("Waveform", .waveform), ("Parade", .parade)])
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            separator
            scope(layout.traceScope) { WaveformGraticule(isParade: layout.traceScope == .parade) }
                .help("\(layout.traceScope.name): brightness (0–1023) across the picture, left to right")
            separator
            scope(.vectorscope) { VectorscopeGraticule() }
                .help("Vectorscope: hue around the circle, saturation outward. Boxes are 75% color bars; the line is skin tone.")
        }
        .frame(width: Theme.scopesWidth)
        .background(Theme.panel)
    }

    private var separator: some View { Rectangle().fill(Theme.separator).frame(height: 1) }

    private func scope<Graticule: View>(_ kind: ScopeKind, @ViewBuilder graticule: () -> Graticule) -> some View {
        ZStack {
            ScopeView(kind: kind, displays: displays)
            graticule()
        }
        .background(Theme.viewer)
        .padding(10)
        .frame(maxHeight: .infinity)
    }
}

/// The scope views on screen. Each time the viewer renders a new image it draws them from that image,
/// in the same command buffer, so hidden scopes cost nothing.
@MainActor
final class ScopeDisplays {
    private final class Weak {
        weak var view: MTKView?
        init(_ view: MTKView) { self.view = view }
    }

    private var views: [ScopeKind: Weak] = [:]
    private lazy var renderer: ScopeRenderer? = (try? MetalContext.make()).flatMap { try? ScopeRenderer(context: $0) }

    /// Registers `view` as the `kind` scope. Views are held weakly: a view that leaves the window drops out.
    func attach(_ view: MTKView, as kind: ScopeKind) {
        views = views.filter { $0.value.view !== view && $0.value.view != nil }
        views[kind] = Weak(view)
    }

    /// The drawable size of each scope on screen: part of what a viewer render depends on.
    var sizes: [ScopeKind: CGSize] {
        views.compactMapValues { $0.view.flatMap { $0.window == nil ? nil : $0.drawableSize } }
    }

    /// Analyzes `image` and draws every scope on screen from it.
    func draw(_ image: MTLTexture, into commandBuffer: MTLCommandBuffer) throws {
        guard let renderer else { return }
        renderer.analyze(image, into: commandBuffer)
        for (kind, entry) in views {
            guard let view = entry.view, view.window != nil, let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else { continue }
            let size = (drawable.texture.width, drawable.texture.height)
            let scope = try renderer.draw(kind, width: size.0, height: size.1, into: commandBuffer)
            renderer.context.present(scope, in: CGRect(x: 0, y: 0, width: size.0, height: size.1), pass: pass,
                                     into: commandBuffer)
            commandBuffer.present(drawable)
        }
    }
}

/// One scope's Metal surface. It never draws itself: the viewer draws into it (see `ScopeDisplays`).
private struct ScopeView: NSViewRepresentable {
    let kind: ScopeKind
    let displays: ScopeDisplays

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = (try? MetalContext.make())?.device
        view.colorPixelFormat = MetalContext.presentPixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        displays.attach(view, as: kind)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) { displays.attach(view, as: kind) }
}

// MARK: Graticules

private let graticuleLine = Color.white.opacity(0.13)
private let graticuleText = Color.white.opacity(0.42)

/// Levels in 10-bit code values like Resolve's scopes, a line every 128 and a label every 256.
private struct WaveformGraticule: View {
    let isParade: Bool

    var body: some View {
        Canvas { context, size in
            for step in 0...8 {
                let y = (1 - Double(step) / 8) * size.height
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(graticuleLine.opacity(step % 4 == 0 ? 1.6 : 1)), lineWidth: 0.5)
                guard step % 2 == 0 else { continue }
                let label = Text("\(step == 8 ? 1023 : step * 128)").font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(graticuleText)
                context.draw(label, at: CGPoint(x: size.width - 3, y: step == 8 ? y + 2 : y - 2),
                             anchor: step == 8 ? .topTrailing : .bottomTrailing)
            }
            guard isParade else { return }
            for third in 1...2 {
                let x = size.width * Double(third) / 3
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(graticuleLine.opacity(2)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The scope's edge, axes, 75% color bar targets and the skin-tone line.
private struct VectorscopeGraticule: View {
    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func position(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: center.x + p.x * radius, y: center.y - p.y * radius) }

            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                           with: .color(graticuleLine.opacity(1.6)), lineWidth: 0.75)
            var axes = Path()
            axes.move(to: CGPoint(x: center.x - radius, y: center.y))
            axes.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: center.y - radius))
            axes.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(axes, with: .color(graticuleLine), lineWidth: 0.5)

            var skin = Path()
            skin.move(to: center)
            skin.addLine(to: position(ScopeGeometry.skinToneDirection))
            context.stroke(skin, with: .color(Theme.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            for target in ScopeGeometry.targets {
                let p = position(target.point)
                context.stroke(Path(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(graticuleText), lineWidth: 0.75)
                let outward = simd_normalize(target.point) * 13
                context.draw(Text(target.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(graticuleText),
                             at: CGPoint(x: p.x + outward.x, y: p.y - outward.y))
            }
        }
        .allowsHitTesting(false)
    }
}
