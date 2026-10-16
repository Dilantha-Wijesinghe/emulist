import EmulistCore
import SwiftUI

/// One adjustable number in the inspector. The whole inspector is generated from these specs.
struct ParameterSpec: Identifiable {
    enum Format {
        case stops, percent, signed, plain

        func string(_ value: Double) -> String {
            switch self {
            case .stops: String(format: "%+.2f", value)
            case .percent: "\(Int(value.rounded()))%"
            case .signed: value.rounded() == 0 ? "0" : String(format: "%+d", Int(value.rounded()))
            case .plain: "\(Int(value.rounded()))"
            }
        }
    }

    let label: String
    let keyPath: WritableKeyPath<GradeSettings, Double>
    let range: ClosedRange<Double>
    var format = Format.plain
    /// Colors along the track, for controls whose meaning is a color direction.
    var gradient: [Color]? = nil

    var id: String { label }
}

struct InspectorSection: Identifiable {
    let title: String
    let symbol: String
    var toggle: WritableKeyPath<GradeSettings, Bool>? = nil
    let parameters: [ParameterSpec]

    var id: String { title }
}

@MainActor
enum Inspector {
    static let input = InspectorSection(title: "Input", symbol: "camera.aperture", parameters: [
        .init(label: "Exposure", keyPath: \.exposure, range: -4...4, format: .stops),
        .init(label: "Temperature", keyPath: \.temperature, range: -100...100, format: .signed,
              gradient: [Color(red: 0.35, green: 0.55, blue: 1), Color(white: 0.75), Color(red: 1, green: 0.72, blue: 0.3)]),
        .init(label: "Tint", keyPath: \.tint, range: -100...100, format: .signed,
              gradient: [Color(red: 0.35, green: 0.85, blue: 0.4), Color(white: 0.75), Color(red: 0.95, green: 0.4, blue: 0.85)]),
    ])

    static let film = InspectorSection(title: "Film", symbol: "film", parameters: [
        .init(label: "Intensity", keyPath: \.intensity, range: 0...100, format: .percent),
        .init(label: "Push / Pull", keyPath: \.push, range: -2...2, format: .stops),
        .init(label: "Contrast", keyPath: \.contrast, range: -100...100, format: .signed),
        .init(label: "Saturation", keyPath: \.saturation, range: 0...200, format: .percent),
        .init(label: "Highlight Roll-off", keyPath: \.highlights, range: -100...100, format: .signed),
        .init(label: "Fade", keyPath: \.fade, range: 0...100, format: .plain),
    ])

    static let colorHead = InspectorSection(title: "Printer Lights", symbol: "circle.lefthalf.filled", parameters: [
        .init(label: "Cyan · Red", keyPath: \.cyanRed, range: -100...100, format: .signed,
              gradient: [Color(red: 0.2, green: 0.8, blue: 0.85), Color(white: 0.75), Color(red: 0.95, green: 0.3, blue: 0.25)]),
        .init(label: "Magenta · Green", keyPath: \.magentaGreen, range: -100...100, format: .signed,
              gradient: [Color(red: 0.9, green: 0.3, blue: 0.8), Color(white: 0.75), Color(red: 0.3, green: 0.8, blue: 0.35)]),
        .init(label: "Yellow · Blue", keyPath: \.yellowBlue, range: -100...100, format: .signed,
              gradient: [Color(red: 0.95, green: 0.85, blue: 0.25), Color(white: 0.75), Color(red: 0.3, green: 0.45, blue: 0.95)]),
    ])

    static let grain = InspectorSection(title: "Grain & Texture", symbol: "circle.dotted", toggle: \.grain.enabled, parameters: [
        .init(label: "Amount", keyPath: \.grain.amount, range: 0...100),
        .init(label: "Size", keyPath: \.grain.size, range: 0...100),
        .init(label: "Color", keyPath: \.grain.chroma, range: 0...100),
        .init(label: "Softness", keyPath: \.grain.softness, range: 0...100),
    ])

    static let halation = InspectorSection(title: "Halation", symbol: "sun.max", toggle: \.halation.enabled, parameters: [
        .init(label: "Amount", keyPath: \.halation.amount, range: 0...100),
        .init(label: "Radius", keyPath: \.halation.radius, range: 0...100),
        .init(label: "Threshold", keyPath: \.halation.threshold, range: 0...100),
        .init(label: "Warmth", keyPath: \.halation.warmth, range: 0...100,
              gradient: [Color(red: 0.85, green: 0.12, blue: 0.1), Color(red: 1, green: 0.6, blue: 0.15)]),
    ])

    static let bloom = InspectorSection(title: "Bloom", symbol: "sparkle", toggle: \.bloom.enabled, parameters: [
        .init(label: "Amount", keyPath: \.bloom.amount, range: 0...100),
        .init(label: "Radius", keyPath: \.bloom.radius, range: 0...100),
        .init(label: "Threshold", keyPath: \.bloom.threshold, range: 0...100),
    ])
}

extension GradeSettings {
    /// The value a parameter returns to on reset: the factory default with the current stock's recommendations.
    func defaultValue(_ keyPath: WritableKeyPath<GradeSettings, Double>) -> Double {
        var defaults = GradeSettings()
        defaults.select(stock)
        return defaults[keyPath: keyPath]
    }
}
