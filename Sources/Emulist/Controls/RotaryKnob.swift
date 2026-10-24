import EmulistCore
import SwiftUI

/// A machined rotary knob with a 270° scale. Drag up/right (or scroll) to turn it, hold ⌥ for fine
/// control, double-click to reset, click the readout to type a value. It clicks into its default.
struct RotaryKnob: View {
    let spec: ParameterSpec
    let value: Double
    let defaultValue: Double
    var isEnabled = true
    var size: CGFloat = 34
    let actions: EditActions

    @State private var session = AdjustSession()
    @State private var isHovering = false

    /// Points of travel for a full sweep: precise but quick.
    private static let pointsPerRange = 260.0
    private static let sweep = 0.75

    var body: some View {
        VStack(spacing: 4) {
            dial
                .frame(width: size + 22, height: size + 22)
                .contentShape(Circle())
                .gesture(drag, including: isEnabled ? .all : .none)
                .onTapGesture(count: 2) { if isEnabled { reset() } }
                .onHover { isHovering = $0 }
                .scrollAdjust(isEnabled: isEnabled, onBegin: begin, onEnd: { session.end(actions) }) { travel, fine in
                    session.move(travel * 0.6, fine: fine, actions)
                }
            Text(spec.label.uppercased())
                .font(.system(size: 8.5, weight: .semibold)).tracking(0.4)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Narrower than the knob, so long neighbouring labels never touch.
                .frame(maxWidth: 56)
            ValueField(text: spec.format.string(value), color: isModified ? Theme.accent : Theme.secondaryText,
                       isEnabled: isEnabled) { text in
                guard let typed = text.typedNumber else { return }
                actions.set(min(max(typed, spec.range.lowerBound), spec.range.upperBound))
            }
            .frame(width: 52)
        }
        .frame(width: 62)
        .opacity(isEnabled ? 1 : 0.4)
        .help("\(spec.label): drag or scroll · ⌥ for fine control · double-click to reset")
    }

    private var isModified: Bool { abs(value - defaultValue) > 1e-6 }

    /// Bipolar controls (default in the middle) light the arc from the center; others from the minimum.
    private var arcOrigin: Double {
        let middle = (spec.range.lowerBound + spec.range.upperBound) / 2
        return abs(defaultValue - middle) < 1e-9 ? middle : spec.range.lowerBound
    }

    // MARK: Drawing

    private var dial: some View {
        let ring = size + 12
        return ZStack {
            ticks.frame(width: size + 22, height: size + 22)
            scaleArc.stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: ring, height: ring)
            if let gradient = spec.gradient {
                scaleArc
                    .stroke(AngularGradient(colors: gradient, center: .center,
                                            startAngle: .degrees(135), endAngle: .degrees(405)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(0.7)
                    .frame(width: ring, height: ring)
            } else {
                let (from, to) = (fraction(arcOrigin), fraction(value))
                Circle().trim(from: min(from, to) * Self.sweep, to: max(from, to) * Self.sweep)
                    .rotation(.degrees(135))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 2)
                    .frame(width: ring, height: ring)
            }
            KnobCap(angle: .degrees(135 + 270 * fraction(value)), isLit: isHovering || session.isActive)
                .frame(width: size, height: size)
        }
    }

    private var scaleArc: some Shape {
        Circle().trim(from: 0, to: Self.sweep).rotation(.degrees(135))
    }

    private var ticks: some View {
        Canvas { context, canvasSize in
            let outer = canvasSize.width / 2
            for i in 0...10 {
                let path = Path.radialTick(in: canvasSize, angle: (135 + 27 * Double(i)) * .pi / 180,
                                           from: outer - 3, to: outer)
                context.stroke(path, with: .color(.white.opacity(i % 5 == 0 ? 0.35 : 0.14)), lineWidth: 1)
            }
        }
    }

    private func fraction(_ v: Double) -> Double {
        (min(max(v, spec.range.lowerBound), spec.range.upperBound) - spec.range.lowerBound)
            / (spec.range.upperBound - spec.range.lowerBound)
    }

    // MARK: Interaction

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                if !session.isActive { begin() }
                session.drag(to: drag.translation.width - drag.translation.height,
                             fine: NSEvent.modifierFlags.contains(.option), actions)
            }
            .onEnded { _ in session.end(actions) }
    }

    private func begin() {
        session.begin(at: value, range: spec.range, pointsPerRange: Self.pointsPerRange, detent: defaultValue, actions)
    }

    private func reset() {
        actions.set(defaultValue)
        Haptics.detent()
    }
}

/// The knob itself: a knurled metal skirt, a machined cap and a pointer line. Light comes from above,
/// so only the pointer rotates.
struct KnobCap: View {
    let angle: Angle
    var isLit = false

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.09)).shadow(color: .black.opacity(0.7), radius: 3, y: 2)
            Canvas { context, size in
                let r = size.width / 2
                for i in 0..<40 {
                    let a = Double(i) / 40 * 2 * .pi
                    // Brighter ridges on the upper half, where the light falls.
                    let light = 0.1 + 0.18 * max(0, -sin(a))
                    context.stroke(Path.radialTick(in: size, angle: a, from: r - 3, to: r),
                                   with: .color(.white.opacity(light)), lineWidth: 1)
                }
            }
            Circle()
                .fill(Theme.metal)
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.18), .clear], center: UnitPoint(x: 0.4, y: 0.25),
                                                      startRadius: 0, endRadius: 14)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.4)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .padding(4)
            GeometryReader { geometry in
                let r = geometry.size.width / 2
                Capsule()
                    .fill(isLit ? Theme.accent : Color.white.opacity(0.85))
                    .frame(width: r * 0.42, height: 2)
                    .offset(x: r * 0.36)
                    .frame(width: 2 * r, height: 2 * r)
                    .rotationEffect(angle)
            }
        }
    }
}

extension Path {
    /// A short radial line at `angle` (radians, clockwise from 3 o'clock) around the center of `size`.
    static func radialTick(in size: CGSize, angle: Double, from inner: Double, to outer: Double) -> Path {
        let cx = size.width / 2, cy = size.height / 2
        var path = Path()
        path.move(to: CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner))
        path.addLine(to: CGPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer))
        return path
    }
}
