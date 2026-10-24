import SwiftUI

/// A small bat-handle toggle in a recessed slot, with a pilot lamp that glows when it's on.
struct AnalogSwitchStyle: ToggleStyle {
    /// What the switch turns on, for accessibility.
    var name = "Enabled"

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(configuration.isOn ? Theme.accent : Color(white: 0.2))
                .frame(width: 5, height: 5)
                .shadow(color: configuration.isOn ? Theme.accent.opacity(0.9) : .clear, radius: 3)
                .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 0.5))
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Theme.inset)
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.08)],
                                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: 24, height: 11)
                Capsule()
                    .fill(Theme.metal)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 13, height: 9)
                    .shadow(color: .black.opacity(0.7), radius: 1.5, x: configuration.isOn ? -1 : 1, y: 1)
                    .padding(.horizontal, 1)
            }
            .frame(width: 24, height: 11)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { configuration.isOn.toggle() }
            Haptics.toggle()
        }
        .accessibilityElement()
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isButton)
    }
}

/// A hardware-style module: engraved title, optional power switch, and its controls.
struct RackModule<Content: View>: View {
    let title: String
    var isOn: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).captionStyle()
                Spacer(minLength: 8)
                if let isOn {
                    Toggle("", isOn: isOn).toggleStyle(AnalogSwitchStyle(name: title.capitalized))
                        .help(isOn.wrappedValue ? "Turn off" : "Turn on")
                }
            }
            content()
                .opacity(isOn?.wrappedValue == false ? 0.45 : 1)
        }
        // Modules share any spare width in their row, like panels in a rack.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .moduleBackground()
    }
}

/// A small selector switch between a few named positions, drawn in SwiftUI (an AppKit segmented control
/// would be re-measured each time the grading panel lays out, on every knob tick).
struct SelectorSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Text(option.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.8) : Theme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 18)
                    .background(isSelected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isSelected else { return }
                        selection = option.value
                        Haptics.toggle()
                    }
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = option.value }
            }
        }
        .padding(2)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }
}
