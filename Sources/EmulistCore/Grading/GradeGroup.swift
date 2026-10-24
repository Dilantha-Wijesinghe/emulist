import Foundation

/// The parts of a grade that travel together. Pasting a grade onto another clip, applying a preset and
/// restoring part of a snapshot all copy a set of groups through `GradeSettings.copy(_:from:)`.
public enum GradeGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case input, primaries, look, printerLights, texture, output

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .input: "Input, Exposure & White Balance"
        case .primaries: "Primaries"
        case .look: "Look & Film"
        case .printerLights: "Printer Lights"
        case .texture: "Grain, Halation & Bloom"
        case .output: "Output"
        }
    }

    /// The creative grade: everything except what belongs to a clip itself (its camera, exposure and
    /// white balance) and the delivery format.
    public static let creative: Set<GradeGroup> = [.primaries, .look, .printerLights, .texture]
}

extension GradeSettings {
    /// Copies the given groups from `source`, leaving everything else as it is.
    public mutating func copy(_ groups: Set<GradeGroup>, from source: GradeSettings) {
        for group in groups { copy(group, from: source) }
    }

    private mutating func copy(_ group: GradeGroup, from s: GradeSettings) {
        switch group {
        case .input:
            cameraProfileID = s.cameraProfileID
            exposure = s.exposure
            temperature = s.temperature
            tint = s.tint
        case .primaries:
            lift = s.lift
            gamma = s.gamma
            gain = s.gain
            offset = s.offset
            contrast = s.contrast
            pivot = s.pivot
            saturation = s.saturation
            colorBoost = s.colorBoost
            density = s.density
            shadows = s.shadows
            highlights = s.highlights
            hueVectors = s.hueVectors
        case .look:
            stockID = s.stockID
            intensity = s.intensity
            push = s.push
            fade = s.fade
        case .printerLights:
            cyanRed = s.cyanRed
            magentaGreen = s.magentaGreen
            yellowBlue = s.yellowBlue
        case .texture:
            grain = s.grain
            halation = s.halation
            bloom = s.bloom
        case .output:
            output = s.output
        }
    }
}
