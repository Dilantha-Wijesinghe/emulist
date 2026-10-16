import Foundation

/// Original film-inspired looks. These are creative interpretations, not measurements of commercial stocks.
extension FilmStock {
    public static let builtIn: [FilmStock] = [solstice400, nocturne800, chrome100, verdant200, silver400]

    static let solstice400 = FilmStock(
        id: "solstice-400", name: "Solstice 400", format: "Color Negative",
        summary: "Warm, gentle and forgiving. Honest skin, golden highlights, soft shadows.",
        response: FilmResponse(
            exposure: 0.15,
            crosstalk: [1.06, -0.04, -0.02, -0.02, 1.05, -0.03, -0.01, -0.06, 1.07],
            separation: 1.08, shoulderStart: 2.6, shoulderRange: 4.5,
            balance: [0.10, 0.02, -0.14],
            contrast: 1.32, channelContrast: [1.0, 1.0, 0.93], toe: 0.72, rolloff: 1.25, midGrey: 0.165,
            black: [0.010, 0.008, 0.010], white: [1.0, 0.985, 0.95], printSaturation: 0.96),
        grain: GrainSettings(amount: 30, size: 30), halation: HalationSettings(amount: 30, radius: 35),
        bloom: BloomSettings(amount: 20, radius: 40))

    static let nocturne800 = FilmStock(
        id: "nocturne-800", name: "Nocturne 800", format: "Cinema Negative",
        summary: "Moody and cinematic. Cool shadows, dense midtones, restrained color.",
        response: FilmResponse(
            exposure: -0.1,
            crosstalk: [1.04, -0.02, -0.02, -0.03, 1.06, -0.03, 0.02, -0.08, 1.06],
            separation: 0.95, shoulderStart: 2.8, shoulderRange: 4.5,
            balance: [0.04, 0.0, -0.06],
            contrast: 1.6, channelContrast: [1.04, 1.0, 0.88], toe: 0.78, rolloff: 1.4, midGrey: 0.14,
            black: [0.004, 0.008, 0.014], white: [1.0, 0.99, 0.96], printSaturation: 0.9),
        grain: GrainSettings(amount: 45, size: 45, chroma: 45), halation: HalationSettings(amount: 45, radius: 40),
        bloom: BloomSettings(amount: 25, radius: 45))

    static let chrome100 = FilmStock(
        id: "chrome-100", name: "Chrome 100", format: "Color Reversal",
        summary: "Punchy slide film. Deep blacks, vivid separation, crisp highlights.",
        response: FilmResponse(
            exposure: -0.2,
            crosstalk: [1.08, -0.05, -0.03, -0.04, 1.08, -0.04, -0.02, -0.06, 1.08],
            separation: 1.22, shoulderStart: 2.2, shoulderRange: 3.2,
            balance: [0.0, 0.0, 0.03],
            contrast: 1.95, channelContrast: [1.0, 1.0, 1.02], toe: 0.95, rolloff: 1.9, midGrey: 0.15,
            black: [0.0, 0.0, 0.002], white: [1.0, 1.0, 1.0], printSaturation: 1.05),
        grain: GrainSettings(amount: 22, size: 20, chroma: 30), halation: HalationSettings(amount: 15, radius: 25),
        bloom: BloomSettings(amount: 15, radius: 35))

    static let verdant200 = FilmStock(
        id: "verdant-200", name: "Verdant 200", format: "Color Negative",
        summary: "Cool everyday film. Minty greens, crisp skies, clean neutral skin.",
        response: FilmResponse(
            exposure: 0.1,
            crosstalk: [1.05, -0.03, -0.02, -0.05, 1.08, -0.03, 0.0, -0.07, 1.07],
            separation: 1.1, shoulderStart: 2.6, shoulderRange: 4.0,
            balance: [-0.04, 0.03, 0.02],
            contrast: 1.45, channelContrast: [1.0, 0.97, 0.97], toe: 0.75, rolloff: 1.35, midGrey: 0.16,
            black: [0.006, 0.012, 0.012], white: [0.98, 1.0, 0.99], printSaturation: 0.97),
        grain: GrainSettings(amount: 35, size: 32), halation: HalationSettings(amount: 25, radius: 35),
        bloom: BloomSettings(amount: 18, radius: 40))

    static let silver400 = FilmStock(
        id: "silver-400", name: "Silver 400", format: "Black & White",
        summary: "Classic panchromatic black and white with a faint warm paper tone.",
        response: FilmResponse(
            exposure: 0.0,
            crosstalk: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            separation: 0, shoulderStart: 2.8, shoulderRange: 4.5,
            balance: [0.02, 0.0, -0.03],
            contrast: 1.7, channelContrast: [1, 1, 1], toe: 0.8, rolloff: 1.5, midGrey: 0.15,
            black: [0.006, 0.005, 0.004], white: [1.0, 0.99, 0.965], printSaturation: 1),
        grain: GrainSettings(amount: 50, size: 40, chroma: 0), halation: HalationSettings(amount: 0, radius: 30),
        bloom: BloomSettings(amount: 20, radius: 40))
}
