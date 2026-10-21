import SwiftUI

/// Visual constants. Neutral grading-suite greys (so they never bias color judgment), machined
/// surfaces for the controls, one warm amber accent like a lit VU meter.
enum Theme {
    static let accent = Color(red: 0.96, green: 0.63, blue: 0.29)
    static let window = Color(white: 0.105)
    static let viewer = Color(white: 0.045)
    static let panel = Color(white: 0.125)
    static let raised = Color(white: 0.16)
    /// Recessed wells: knob tracks, wheel faces, switch slots.
    static let inset = Color(white: 0.065)
    static let separator = Color.black.opacity(0.55)
    /// The 1px light edge along the top of raised surfaces.
    static let bevel = Color.white.opacity(0.06)
    static let primaryText = Color.white.opacity(0.88)
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.32)

    static let libraryWidth: CGFloat = 240
    static let cornerRadius: CGFloat = 8

    static let monoDigits = Font.system(size: 10.5, weight: .medium).monospacedDigit()

    /// Brushed-metal face of a knob or lever.
    static let metal = LinearGradient(
        colors: [Color(white: 0.42), Color(white: 0.24), Color(white: 0.17)], startPoint: .top, endPoint: .bottom)
}

extension View {
    /// The look of a quiet engraved label (module titles, units).
    func captionStyle() -> some View {
        font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.tertiaryText)
    }

    /// A raised panel like a module in a hardware rack.
    func moduleBackground(cornerRadius: CGFloat = 7) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [Color(white: 0.155), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.bevel, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1))
    }
}

/// Aspect-fit placement of content inside a container. Used by both the Metal viewport and SwiftUI overlays
/// so the compare wipe lines up exactly with the image.
func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return .zero }
    let scale = min(container.width / content.width, container.height / content.height)
    let size = CGSize(width: content.width * scale, height: content.height * scale)
    return CGRect(
        x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
        width: size.width, height: size.height)
}
