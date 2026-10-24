import CryptoKit
import Foundation

/// An in-camera film simulation recipe: the settings a Fujifilm camera stacks on one of its film
/// simulations. Emulist renders it as a look (the installed Fujifilm LUT) plus primaries, printer lights
/// and grain, through `settings(on:)`. Only the settings are stored; each recipe links to its source.
///
/// Recipes are tuned for in-camera JPEGs, so the result is an approximation to refine by eye.
public struct FilmRecipe: Sendable, Identifiable {
    public enum Strength: Sendable { case off, weak, strong }
    public enum GrainSize: Sendable { case small, large }
    public enum DynamicRange: Sendable {
        case auto, dr200, dr400
        /// D-Range Priority Strong: Fujifilm's automatic low-contrast mode, roughly DR400 with lifted
        /// shadows and softened highlights.
        case priorityStrong
    }

    public let name: String
    /// The film simulation, as `FujifilmLooks` keys it (e.g. "CLASSIC-CHROME").
    public let simulationKey: String
    public let url: URL
    /// White balance shift, in Fujifilm's steps (−9…+9; +red / +blue).
    public var red = 0
    public var blue = 0
    /// Fujifilm's Highlight and Shadow tone (−2…+4, in half steps; + is harder on both).
    public var highlight = 0.0
    public var shadow = 0.0
    /// Fujifilm's Color (−4…+4).
    public var color = 0
    public var colorChrome = Strength.off
    public var grain = Strength.off
    public var grainSize = GrainSize.small
    public var dynamicRange = DynamicRange.auto
    /// Settings Emulist doesn't model yet; kept so the library can say they're left out.
    public var colorChromeFXBlue = Strength.off
    public var clarity = 0

    public var id: UUID {
        SHA256.hash(data: Data("recipe:\(name)".utf8)).withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    /// The grade groups a recipe sets. Input (the clip's own exposure and white balance) and Output stay
    /// the clip's.
    public static let groups: Set<GradeGroup> = [.look, .primaries, .printerLights, .texture]

    /// The recipe on `simulation` (its Fujifilm look), starting from neutral settings.
    public func settings(on simulation: FilmStock) -> GradeSettings {
        var settings = GradeSettings()
        settings.select(simulation)
        // The size of one Fujifilm WB shift step is unpublished; 6 printer points is a starting point.
        settings.cyanRed = Double(red) * 6
        settings.yellowBlue = Double(blue) * 6
        // On Fujifilm, +Shadow means darker, harder shadows; Emulist's Shadows + lifts them.
        settings.highlights = highlight * 15 + dynamicRange.highlights
        settings.shadows = -shadow * 15 + dynamicRange.shadows
        settings.saturation = 100 + Double(color) * 8
        settings.density = colorChrome.density
        settings.grain.enabled = grain != .off
        if grain != .off {
            settings.grain.amount = grain == .strong ? 40 : 20
            settings.grain.size = grainSize == .large ? 55 : 25
        }
        return settings
    }

    /// The recipe as a look to apply, or nil when its simulation isn't among `looks`.
    public func preset(in looks: [FilmStock]) -> GradePreset? {
        guard let simulation = looks.first(where: { FujifilmLooks.simulationKey(of: $0) == simulationKey }) else { return nil }
        var preset = GradePreset(name: name, groups: Self.groups, settings: settings(on: simulation))
        preset.id = id
        return preset
    }

    /// What the recipe sets that Emulist leaves out for now.
    public var ignoredSettings: [String] {
        var ignored: [String] = []
        if colorChromeFXBlue != .off { ignored.append("Color Chrome FX Blue \(colorChromeFXBlue.name)") }
        if clarity != 0 { ignored.append("Clarity \(clarity > 0 ? "+" : "")\(clarity)") }
        return ignored
    }
}

extension FilmRecipe.Strength {
    var name: String {
        switch self {
        case .off: "Off"
        case .weak: "Weak"
        case .strong: "Strong"
        }
    }

    /// Color Chrome Effect deepens saturated colors without adding saturation: Emulist's Density.
    var density: Double {
        switch self {
        case .off: 0
        case .weak: 25
        case .strong: 50
        }
    }
}

extension FilmRecipe.DynamicRange {
    var highlights: Double {
        switch self {
        case .auto: 0
        case .dr200: -10
        case .dr400, .priorityStrong: -20
        }
    }

    var shadows: Double { self == .priorityStrong ? 15 : 0 }
}
