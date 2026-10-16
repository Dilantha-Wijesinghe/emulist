import SwiftUI

/// A compact grading slider: label and value on one line, a thin track below that fills from the default.
/// Drag to adjust (one undo step per drag), double-click to reset, hover to reveal a reset button.
struct FilmSlider: View {
    let spec: ParameterSpec
    let value: Double
    let defaultValue: Double
    var isEnabled = true
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragStartValue = 0.0

    private var isModified: Bool { abs(value - defaultValue) > 1e-6 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(spec.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isEnabled ? Theme.primaryText.opacity(0.85) : Theme.tertiaryText)
                Spacer(minLength: 4)
                if isModified, isHovering {
                    Button(action: onReset) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to \(spec.format.string(defaultValue))")
                }
                Text(spec.format.string(value))
                    .font(Theme.monoDigits)
                    .foregroundStyle(isModified ? Theme.accent : Theme.secondaryText)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            track
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onReset)
        .opacity(isEnabled ? 1 : 0.45)
        .help("Drag to adjust · ⌥-drag for fine control · double-click to reset")
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let position = fraction(value) * width
            let origin = fraction(defaultValue) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(spec.gradient.map { AnyShapeStyle(LinearGradient(colors: $0.map { $0.opacity(0.55) }, startPoint: .leading, endPoint: .trailing)) }
                          ?? AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(height: 3)
                if spec.gradient == nil {
                    Capsule()
                        .fill(Theme.accent.opacity(0.85))
                        .frame(width: abs(position - origin), height: 3)
                        .offset(x: min(position, origin))
                }
                Circle()
                    .fill(Color(white: isDragging ? 1 : 0.88))
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .frame(width: 11, height: 11)
                    .offset(x: position - 5.5)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                            onBegin()
                        }
                        onChange(newValue(drag, width: width))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEnd()
                    })
        }
        .frame(height: 14)
    }

    private func fraction(_ v: Double) -> Double {
        (min(max(v, spec.range.lowerBound), spec.range.upperBound) - spec.range.lowerBound)
            / (spec.range.upperBound - spec.range.lowerBound)
    }

    /// The knob follows the pointer; with ⌥ held it moves relative to the drag start at one tenth the speed.
    private func newValue(_ drag: DragGesture.Value, width: Double) -> Double {
        let span = spec.range.upperBound - spec.range.lowerBound
        let raw = NSEvent.modifierFlags.contains(.option)
            ? dragStartValue + drag.translation.width / width * span * 0.1
            : spec.range.lowerBound + drag.location.x / width * span
        return min(max(raw, spec.range.lowerBound), spec.range.upperBound)
    }
}
