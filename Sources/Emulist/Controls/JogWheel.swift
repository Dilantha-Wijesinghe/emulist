import EmulistCore
import SwiftUI

/// A horizontal ribbed thumbwheel, like the master rings under a grading panel's trackballs.
/// The ribs roll with the value, so every nudge is visible. Drag or scroll sideways; ⌥ for fine.
struct JogWheel: View {
    let value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// Points of travel for the whole range.
    var pointsPerRange = 900.0
    let actions: EditActions

    @State private var session = AdjustSession()
    @State private var isHovering = false

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let body = Path(roundedRect: rect, cornerRadius: 3)
            // Cylinder shading: dark at the edges, lit in the middle.
            context.fill(body, with: .linearGradient(
                Gradient(colors: [Color(white: 0.05), Color(white: 0.22), Color(white: 0.28), Color(white: 0.22), Color(white: 0.05)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            // Ribs on the visible half of the cylinder, spaced evenly in angle.
            let radius = size.width / 2
            let phase = (value - range.lowerBound) * 2 * .pi * 3 / (range.upperBound - range.lowerBound)
            let ribs = 36
            for i in 0..<ribs {
                let turn = (Double(i) / Double(ribs) * 2 * .pi + phase).truncatingRemainder(dividingBy: 2 * .pi)
                let angle = (turn < 0 ? turn + 2 * .pi : turn) - .pi
                guard abs(angle) < .pi / 2 * 0.96 else { continue }
                let x = radius + sin(angle) * radius
                var rib = Path()
                rib.move(to: CGPoint(x: x, y: 2))
                rib.addLine(to: CGPoint(x: x, y: size.height - 2))
                let facing = cos(angle)
                context.stroke(rib, with: .color(.black.opacity(0.55 * facing)), lineWidth: 1.6)
                rib = rib.offsetBy(dx: 0.8, dy: 0)
                context.stroke(rib, with: .color(.white.opacity(0.16 * facing)), lineWidth: 0.6)
            }
            context.stroke(body, with: .color(.black.opacity(0.8)), lineWidth: 1)
            // Fixed index mark.
            var mark = Path()
            mark.move(to: CGPoint(x: radius, y: 0))
            mark.addLine(to: CGPoint(x: radius, y: 3))
            context.stroke(mark, with: .color(isHovering || session.isActive ? Theme.accent : .white.opacity(0.5)), lineWidth: 1.5)
        }
        .frame(height: 15)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { drag in
                if !session.isActive { begin() }
                session.drag(to: drag.translation.width, fine: NSEvent.modifierFlags.contains(.option), actions)
            }
            .onEnded { _ in session.end(actions) })
        .onTapGesture(count: 2) {
            actions.set(defaultValue)
            Haptics.detent()
        }
        .scrollAdjust(onBegin: begin, onEnd: { session.end(actions) }) { travel, fine in
            session.move(travel, fine: fine, actions)
        }
        .help("Master: drag or scroll sideways · ⌥ for fine control · double-click to reset")
    }

    private func begin() {
        session.begin(at: value, range: range, pointsPerRange: pointsPerRange, detent: defaultValue,
                      detentWidth: 0.008, actions)
    }
}
