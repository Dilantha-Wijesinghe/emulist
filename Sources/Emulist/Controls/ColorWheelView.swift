import EmulistCore
import SwiftUI

extension ColorWheel.Kind {
    var title: String { rawValue.capitalized }

    /// Resolve-style readouts: lift and gamma rest at 0.00, gain at 1.00, offset at 25.00.
    var displayBase: Double {
        switch self {
        case .lift, .gamma: 0
        case .gain: 1
        case .offset: 25
        }
    }

    var displayScale: Double { self == .offset ? 100 : 1 }

    func display(_ value: Double) -> String { String(format: "%.2f", displayBase + value * displayScale) }
    func parse(_ text: String) -> Double? { text.typedNumber.map { ($0 - displayBase) / displayScale } }

    var help: String {
        switch self {
        case .lift: "Shadows. Push the puck toward a hue to tint the blacks; the ring below raises or lowers them."
        case .gamma: "Midtones. Tints and brightens the mids while holding black and white."
        case .gain: "Highlights. Tints and scales the brights, anchored at black."
        case .offset: "Everything at once, like printer lights: shifts the whole image evenly in log."
        }
    }

    /// The hue drawn at a point of the wheel: the same vectorscope mapping the grade uses.
    static func hue(cb: Double, cr: Double, brightness: Double = 0.62) -> Color {
        let c = ColorWheel.chroma(cb: cb, cr: cr)
        let peak = max(abs(c.x), abs(c.y), abs(c.z), 1e-9)
        let rgb = (c / peak) * 0.42 + RGB(repeating: brightness - 0.08)
        return Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}

/// A primary color wheel: a vectorscope-oriented trackball (drag the puck toward a hue), the master
/// thumbwheel beneath it and editable R G B readouts. Dragging is relative and slow by default so the
/// puck can be placed precisely; ⌥ is finer still, ⇧ faster. The center is a detent.
struct ColorWheelView: View {
    let kind: ColorWheel.Kind
    let wheel: ColorWheel
    var diameter: CGFloat = 116
    let begin: () -> Void
    let change: (ColorWheel) -> Void
    let end: () -> Void

    @State private var dragStart: SIMD2<Double>?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 7) {
            header
            face
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(puckDrag)
                .onTapGesture(count: 2) { set { $0.x = 0; $0.y = 0 } }
                .onHover { isHovering = $0 }
                .help(kind.help + "\nDrag anywhere on the wheel · ⌥ fine · ⇧ fast · double-click to center")
            JogWheel(value: wheel.master, range: kind.masterRange, defaultValue: 0,
                     actions: EditActions(begin: begin, change: { master in change(updated { $0.master = master }) }, end: end))
                .frame(width: diameter * 0.86)
            readouts
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(kind.title.uppercased())
                .font(.system(size: 9.5, weight: .bold)).tracking(1)
                .foregroundStyle(wheel.isNeutral ? Theme.secondaryText : Theme.primaryText)
            Spacer(minLength: 0)
            Button { set { $0 = ColorWheel() } } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(wheel.isNeutral ? Theme.tertiaryText.opacity(0.5) : Theme.secondaryText)
            .disabled(wheel.isNeutral)
            .help("Reset \(kind.title)")
        }
        .frame(width: diameter)
    }

    // MARK: Face

    private var face: some View {
        let ring: CGFloat = 7
        return ZStack {
            // Machined bezel.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            // Hue ring, oriented like a vectorscope (red upper left, blue right, green lower left).
            Circle()
                .strokeBorder(AngularGradient(colors: Self.ringColors, center: .center), lineWidth: ring)
                .padding(3)
                .opacity(0.9)
            // Recessed face with a crosshair and the hue a full push would give, faintly.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.06)], center: .center,
                                     startRadius: 0, endRadius: diameter / 2))
                .overlay(Circle().fill(AngularGradient(colors: Self.ringColors, center: .center)).opacity(0.07))
                .overlay(crosshair)
                .overlay(Circle().strokeBorder(.black.opacity(0.8), lineWidth: 1))
                .padding(3 + ring + 2)
            puck
        }
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1).padding(diameter * 0.18)
        }
    }

    private var travelRadius: CGFloat { diameter / 2 - 14 }

    private var puck: some View {
        let position = CGPoint(x: wheel.x * travelRadius, y: -wheel.y * travelRadius)
        let isActive = dragStart != nil
        return ZStack {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: position)
            }
            .stroke(.white.opacity(0.25), lineWidth: 1)
            .offset(x: diameter / 2, y: diameter / 2)
            Circle()
                .fill(ColorWheel.Kind.hue(cb: wheel.x, cr: wheel.y, brightness: wheel.x == 0 && wheel.y == 0 ? 0.5 : 0.7))
                .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
                .frame(width: isActive ? 13 : 11, height: isActive ? 13 : 11)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .shadow(color: isActive ? .white.opacity(0.5) : .clear, radius: 5)
                .offset(x: position.x, y: position.y)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    /// Colors around the ring, starting at 3 o'clock and running clockwise (SwiftUI's angle convention).
    static let ringColors: [Color] = (0...72).map { i in
        let angle = Double(i) / 72 * 2 * .pi
        return ColorWheel.Kind.hue(cb: cos(angle), cr: -sin(angle))
    }

    // MARK: Readouts

    private var readouts: some View {
        let rgb = wheel.rgb(kind)
        return HStack(spacing: 6) {
            channel("R", rgb.x, color: Color(red: 1, green: 0.45, blue: 0.4)) { var c = rgb; c.x = $0; return c }
            channel("G", rgb.y, color: Color(red: 0.45, green: 0.9, blue: 0.45)) { var c = rgb; c.y = $0; return c }
            channel("B", rgb.z, color: Color(red: 0.45, green: 0.6, blue: 1)) { var c = rgb; c.z = $0; return c }
        }
        .frame(width: diameter + 8)
    }

    private func channel(_ name: String, _ value: Double, color: Color, replacing: @escaping (Double) -> RGB) -> some View {
        VStack(spacing: 1) {
            Text(name).font(.system(size: 8, weight: .bold)).foregroundStyle(color.opacity(0.8))
            ValueField(text: kind.display(value), color: abs(value) > 1e-6 ? Theme.primaryText : Theme.secondaryText) { text in
                guard let typed = kind.parse(text) else { return }
                set { $0 = ColorWheel(rgb: replacing(typed), kind: kind) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Interaction

    private var puckDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                let start = dragStart ?? SIMD2(wheel.x, wheel.y)
                if dragStart == nil {
                    dragStart = start
                    begin()
                }
                let flags = NSEvent.modifierFlags
                let speed = flags.contains(.shift) ? 1.0 : 0.35
                let delta = SIMD2(drag.translation.width, -drag.translation.height) / travelRadius * speed
                let next = DragMath.puck(from: start, delta: delta, fine: flags.contains(.option))
                let wasCentered = wheel.x == 0 && wheel.y == 0
                if next == .zero, !wasCentered { Haptics.detent() }
                change(updated { $0.x = next.x; $0.y = next.y })
            }
            .onEnded { _ in
                dragStart = nil
                end()
            }
    }

    private func updated(_ modify: (inout ColorWheel) -> Void) -> ColorWheel {
        var next = wheel
        modify(&next)
        return next
    }

    private func set(_ modify: (inout ColorWheel) -> Void) {
        begin()
        change(updated(modify))
        end()
    }
}
