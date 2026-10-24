import Foundation

extension FilmRecipe {
    public static let fujiXWeeklyCollection = "Fuji X Weekly Recipes"

    /// Popular recipes published at Fuji X Weekly (fujixweekly.com), X-Trans V versions where available,
    /// on the simulations in Fujifilm's LUT package. Settings only; each links to its page.
    public static let fujiXWeekly: [FilmRecipe] = [
        FilmRecipe(name: "Reggie’s Portra", simulationKey: "CLASSIC-CHROME",
                   url: page("2022/06/11/fujifilm-x-trans-iv-film-simulation-recipe-reggies-portra"),
                   red: 2, blue: -4, highlight: -1, shadow: -1, color: 2, colorChrome: .strong, grain: .weak),
        FilmRecipe(name: "Kodachrome 64", simulationKey: "CLASSIC-CHROME",
                   url: page("2022/11/28/kodachrome-64-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: 2, blue: -5, shadow: 0.5, color: 2, colorChrome: .strong, grain: .weak,
                   dynamicRange: .dr200, clarity: 3),
        FilmRecipe(name: "Kodak Gold 200", simulationKey: "CLASSIC-CHROME",
                   url: page("2023/10/24/kodak-gold-200-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: 4, blue: -5, highlight: -1.5, shadow: 0.5, color: 3, colorChrome: .weak, grain: .strong,
                   dynamicRange: .dr400, clarity: -2),
        FilmRecipe(name: "Kodak Portra 400 v2", simulationKey: "CLASSIC-CHROME",
                   url: page("2022/12/16/kodak-portra-400-v2-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: 1, blue: -6, shadow: -2, color: 2, colorChrome: .strong, grain: .strong,
                   dynamicRange: .dr400, clarity: -2),
        FilmRecipe(name: "Kodak Portra 800 v3", simulationKey: "CLASSIC-CHROME",
                   url: page("2024/02/14/kodak-portra-800-v3-fujifilm-x-t5-x-trans-v-x-e4-x-trans-iv-film-simulation-recipe"),
                   red: -1, blue: -3, highlight: -2, shadow: -0.5, color: 3, colorChrome: .strong, grain: .strong,
                   grainSize: .large, dynamicRange: .dr400, clarity: -3),
        FilmRecipe(name: "Vibrant Arizona", simulationKey: "CLASSIC-CHROME",
                   url: page("2023/04/25/getting-a-wes-anderson-look-from-your-fujifilm-camera-4-new-film-simulation-recipes"),
                   red: 6, blue: -8, color: 4, grain: .weak, dynamicRange: .priorityStrong,
                   colorChromeFXBlue: .weak, clarity: -3),
        FilmRecipe(name: "Vintage Kodachrome", simulationKey: "CLASSIC-CHROME",
                   url: page("2017/10/21/my-fujifilm-x100f-vintage-kodachrome-film-simulation-recipe"),
                   red: 2, blue: -4, highlight: 4, shadow: -2, color: 4, grain: .strong, dynamicRange: .dr200),
        FilmRecipe(name: "Pacific Blues", simulationKey: "CLASSIC-Neg.",
                   url: page("2022/12/06/pacific-blues-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: 1, blue: -3, highlight: -2, shadow: 3, color: 4, colorChrome: .strong, grain: .strong,
                   grainSize: .large, dynamicRange: .dr400, colorChromeFXBlue: .weak, clarity: -3),
        FilmRecipe(name: "Reggie’s Superia", simulationKey: "CLASSIC-Neg.",
                   url: page("2026/03/12/reggies-superia-a-fujifilm-recipe-for-x-trans-iv-v-cameras"),
                   red: 1, blue: -3, highlight: -2, shadow: -1, color: 1, colorChrome: .strong, grain: .strong,
                   grainSize: .large, colorChromeFXBlue: .strong),
        FilmRecipe(name: "Fujicolor Super HG v2", simulationKey: "CLASSIC-Neg.",
                   url: page("2023/07/20/fujicolor-super-hg-v2-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: -3, blue: -1, highlight: -1, shadow: 1, color: 2, colorChrome: .weak, grain: .weak,
                   grainSize: .large, dynamicRange: .dr400, colorChromeFXBlue: .weak, clarity: 2),
        FilmRecipe(name: "Fujifilm Negative", simulationKey: "REALA-ACE",
                   url: page("2024/10/31/fujifilm-negative-fujifilm-x-t5-x-trans-v-film-simulation-recipe"),
                   red: 0, blue: -2, highlight: -1, shadow: -0.5, color: 2, colorChrome: .strong, grain: .weak,
                   dynamicRange: .dr400, clarity: -2),
        FilmRecipe(name: "PRO Negative 160C", simulationKey: "REALA-ACE",
                   url: page("2024/03/27/pro-negative-160c-fujifilm-x100vi-film-simulation-recipe"),
                   red: 1, blue: -2, highlight: -1, shadow: -1, color: 4, colorChrome: .strong, grain: .weak,
                   dynamicRange: .dr200, clarity: -2),
        FilmRecipe(name: "CineStill 800T", simulationKey: "ETERNA",
                   url: page("2024/04/16/cinestill-800t-fujifilm-x-trans-v-film-simulation-recipe"),
                   red: -6, blue: -4, shadow: 2, color: 4, colorChrome: .strong, grain: .strong, grainSize: .large,
                   dynamicRange: .dr400, colorChromeFXBlue: .weak, clarity: -5),
        FilmRecipe(name: "Kodak Tri-X 400", simulationKey: "ACROS",
                   url: page("2020/06/18/fujifilm-x100v-film-simulation-recipe-kodak-tri-x-400"),
                   red: 9, blue: -9, shadow: 3, colorChrome: .strong, grain: .strong, grainSize: .large,
                   dynamicRange: .dr200, clarity: 4),
    ]

    private static func page(_ path: String) -> URL {
        URL(string: "https://fujixweekly.com/\(path)/")!
    }
}
