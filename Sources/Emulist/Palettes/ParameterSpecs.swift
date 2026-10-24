import EmulistCore
import SwiftUI

/// One adjustable number. Every knob in the app is generated from these specs.
struct ParameterSpec: Identifiable, Sendable {
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
    let keyPath: WritableKeyPath<GradeSettings, Double> & Sendable
    let range: ClosedRange<Double>
    var format = Format.plain
    /// Colors along the knob's arc, for controls whose meaning is a color direction.
    var gradient: [Color]? = nil

    var id: String { label }
}

/// A group of knobs that reads as one hardware module, optionally with a power switch.
struct ModuleSpec: Identifiable {
    let title: String
    var toggle: WritableKeyPath<GradeSettings, Bool>? = nil
    let parameters: [ParameterSpec]

    var id: String { title }
}

@MainActor
enum Controls {
    private static let coolWarm = [Color(red: 0.35, green: 0.55, blue: 1), Color(white: 0.7), Color(red: 1, green: 0.7, blue: 0.3)]
    private static let greenMagenta = [Color(red: 0.35, green: 0.85, blue: 0.4), Color(white: 0.7), Color(red: 0.95, green: 0.4, blue: 0.85)]

    /// The adjustment row under the color wheels, like Resolve's primaries bars.
    static let primaries: [ParameterSpec] = [
        .init(label: "Contrast", keyPath: \.contrast, range: -100...100, format: .signed),
        .init(label: "Pivot", keyPath: \.pivot, range: -3...3, format: .stops),
        .init(label: "Saturation", keyPath: \.saturation, range: 0...200, format: .percent),
        .init(label: "Color Boost", keyPath: \.colorBoost, range: 0...100),
        .init(label: "Density", keyPath: \.density, range: 0...100),
        .init(label: "Shadows", keyPath: \.shadows, range: -100...100, format: .signed),
        .init(label: "Highlights", keyPath: \.highlights, range: -100...100, format: .signed),
    ]

    static let input: [ParameterSpec] = [
        .init(label: "Exposure", keyPath: \.exposure, range: -4...4, format: .stops),
        .init(label: "Temp", keyPath: \.temperature, range: -100...100, format: .signed, gradient: coolWarm),
        .init(label: "Tint", keyPath: \.tint, range: -100...100, format: .signed, gradient: greenMagenta),
    ]

    static let film = ModuleSpec(title: "FILM", parameters: [
        .init(label: "Intensity", keyPath: \.intensity, range: 0...100, format: .percent),
        .init(label: "Push / Pull", keyPath: \.push, range: -2...2, format: .stops),
        .init(label: "Fade", keyPath: \.fade, range: 0...100),
    ])

    static let printerLights = ModuleSpec(title: "PRINTER LIGHTS", parameters: [
        .init(label: "Cyan · Red", keyPath: \.cyanRed, range: -100...100, format: .signed,
              gradient: [Color(red: 0.2, green: 0.8, blue: 0.85), Color(white: 0.7), Color(red: 0.95, green: 0.3, blue: 0.25)]),
        .init(label: "Mag · Green", keyPath: \.magentaGreen, range: -100...100, format: .signed,
              gradient: [Color(red: 0.9, green: 0.3, blue: 0.8), Color(white: 0.7), Color(red: 0.3, green: 0.8, blue: 0.35)]),
        .init(label: "Yel · Blue", keyPath: \.yellowBlue, range: -100...100, format: .signed,
              gradient: [Color(red: 0.95, green: 0.85, blue: 0.25), Color(white: 0.7), Color(red: 0.3, green: 0.45, blue: 0.95)]),
    ])

    static let grain = ModuleSpec(title: "GRAIN", toggle: \.grain.enabled, parameters: [
        .init(label: "Amount", keyPath: \.grain.amount, range: 0...100),
        .init(label: "Size", keyPath: \.grain.size, range: 0...100),
        .init(label: "Color", keyPath: \.grain.chroma, range: 0...100),
        .init(label: "Softness", keyPath: \.grain.softness, range: 0...100),
    ])

    static let halation = ModuleSpec(title: "HALATION", toggle: \.halation.enabled, parameters: [
        .init(label: "Amount", keyPath: \.halation.amount, range: 0...100),
        .init(label: "Radius", keyPath: \.halation.radius, range: 0...100),
        .init(label: "Threshold", keyPath: \.halation.threshold, range: 0...100),
        .init(label: "Warmth", keyPath: \.halation.warmth, range: 0...100,
              gradient: [Color(red: 0.85, green: 0.12, blue: 0.1), Color(red: 1, green: 0.6, blue: 0.15)]),
    ])

    static let bloom = ModuleSpec(title: "BLOOM", toggle: \.bloom.enabled, parameters: [
        .init(label: "Amount", keyPath: \.bloom.amount, range: 0...100),
        .init(label: "Radius", keyPath: \.bloom.radius, range: 0...100),
        .init(label: "Threshold", keyPath: \.bloom.threshold, range: 0...100),
    ])
}
