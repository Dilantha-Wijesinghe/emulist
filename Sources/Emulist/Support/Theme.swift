import SwiftUI

/// Visual constants. Dark charcoal surfaces, one warm accent, the footage always the brightest thing on screen.
enum Theme {
    static let accent = Color(red: 0.96, green: 0.63, blue: 0.29)
    static let window = Color(white: 0.085)
    static let viewer = Color(white: 0.045)
    static let panel = Color(white: 0.115)
    static let raised = Color(white: 0.16)
    static let separator = Color.white.opacity(0.07)
    static let primaryText = Color.white.opacity(0.9)
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.32)

    static let inspectorWidth: CGFloat = 300
    static let cornerRadius: CGFloat = 8

    static let monoDigits = Font.system(size: 11, weight: .medium).monospacedDigit()
}

extension View {
    /// The look of a quiet secondary label (section captions, units).
    func captionStyle() -> some View {
        font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiaryText)
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
