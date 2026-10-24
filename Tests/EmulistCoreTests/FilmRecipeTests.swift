import Foundation
import Testing
@testable import EmulistCore

@Suite struct FilmRecipeTests {
    /// A Fujifilm look as the library discovers it (no file is read).
    static func fujifilmLook(_ key: String) -> FilmStock {
        let root = URL(fileURLWithPath: "/looks")
        return LookLibrary.look(for: root.appending(path: "Fujifilm/FLog2_to_\(key)_65grid_V.1.00.cube"), root: root)!
    }

    static let classicChrome = fujifilmLook("CLASSIC-CHROME")
    static let recipe = FilmRecipe(name: "Test", simulationKey: "CLASSIC-CHROME", url: URL(string: "https://example.com")!)

    @Test func neutralRecipeIsTheSimulationWithGrainOff() {
        var expected = GradeSettings()
        expected.select(Self.classicChrome)
        expected.grain.enabled = false
        #expect(Self.recipe.settings(on: Self.classicChrome) == expected)
    }

    @Test func toneFlipsShadowSignAndAddsDynamicRange() {
        var recipe = Self.recipe
        recipe.highlight = 1
        recipe.shadow = 2
        recipe.dynamicRange = .dr400
        let settings = recipe.settings(on: Self.classicChrome)
        #expect(settings.highlights == 15 - 20)
        #expect(settings.shadows == -30)
        recipe.dynamicRange = .dr200
        #expect(recipe.settings(on: Self.classicChrome).highlights == 15 - 10)
    }

    @Test func whiteBalanceShiftBecomesPrinterLights() {
        var recipe = Self.recipe
        recipe.red = 2
        recipe.blue = -4
        let settings = recipe.settings(on: Self.classicChrome)
        #expect(settings.cyanRed == 12)
        #expect(settings.yellowBlue == -24)
        #expect(settings.magentaGreen == 0)
        // The clip's own white balance is untouched.
        #expect(settings.temperature == 0 && settings.tint == 0)
    }

    @Test func colorChromeAndGrain() {
        var recipe = Self.recipe
        recipe.color = 3
        recipe.colorChrome = .strong
        recipe.grain = .weak
        recipe.grainSize = .large
        let settings = recipe.settings(on: Self.classicChrome)
        #expect(settings.saturation == 124)
        #expect(settings.density == 50)
        #expect(settings.grain.enabled && settings.grain.amount == 20 && settings.grain.size == 55)
        // Softness and color stay the simulation's.
        #expect(settings.grain.softness == Self.classicChrome.grain.softness)
    }

    @Test func everyRecipeResolvesToAnInstalledSimulation() {
        let keys = Set(FujifilmLooks.simulations.map(\.key))
        let looks = FujifilmLooks.simulations.map { Self.fujifilmLook($0.key) }
        #expect(FilmRecipe.fujiXWeekly.count == 14)
        for recipe in FilmRecipe.fujiXWeekly {
            #expect(keys.contains(recipe.simulationKey), "\(recipe.name)")
            let preset = recipe.preset(in: looks)
            #expect(preset?.settings.stockID == looks.first { FujifilmLooks.simulationKey(of: $0) == recipe.simulationKey }?.id)
            #expect(recipe.url.host() == "fujixweekly.com")
        }
        #expect(Set(FilmRecipe.fujiXWeekly.map(\.id)).count == FilmRecipe.fujiXWeekly.count)
    }

    @Test func recipesNeedTheirSimulation() {
        #expect(Self.recipe.preset(in: FilmStock.builtIn) == nil)
        #expect(Self.recipe.preset(in: [Self.fujifilmLook("ACROS")]) == nil)
    }

    @Test func presetIDsAreStable() {
        let a = Self.recipe.preset(in: [Self.classicChrome])
        let b = Self.recipe.preset(in: [Self.classicChrome])
        #expect(a?.id == b?.id && a?.id == Self.recipe.id)
        #expect(a?.groups == FilmRecipe.groups)
    }

    @Test func fxBlueDeepensOnlyBlues() {
        var recipe = Self.recipe
        recipe.colorChromeFXBlue = .strong
        let vectors = recipe.settings(on: Self.classicChrome).hueVectors
        #expect(vectors.blue == HueVectors.Adjustment(density: 50))
        #expect(HueVectors.Vector.allCases.filter { $0 != .blue }.allSatisfy { vectors[$0].isNeutral })
    }

    @Test func ignoredSettingsAreNamed() {
        var recipe = Self.recipe
        #expect(recipe.ignoredSettings.isEmpty)
        recipe.clarity = -3
        recipe.colorChromeFXBlue = .weak
        #expect(recipe.ignoredSettings == ["Clarity -3"])
    }
}
