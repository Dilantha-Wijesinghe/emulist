import Foundation

/// Original film-inspired looks. These are creative interpretations, not measurements of commercial stocks.
///
/// Reading the numbers: `crosstalk` rows mix log exposure between layers (hue character), `channelContrast`
/// below 1 on blue gives warm highlights over cool shadows, `black`/`white` tint the print's extremes.
extension FilmStock {
    public static let builtIn: [FilmStock] = [
        solstice400, nocturne800, aurora50, golden200, verdant200, chrome100, silver400,
    ]

    static let solstice400 = FilmStock(
        id: "solstice-400", name: "Solstice 400", format: "Color Negative",
        summary: "Warm, gentle and forgiving. Honest skin, golden highlights, soft open shadows.",
        response: FilmResponse(
            exposure: 0.2,
            crosstalk: [1.04, -0.02, -0.02, -0.02, 1.04, -0.02, 0.0, -0.04, 1.04],
            separation: 0.98, shoulderStart: 2.8, shoulderRange: 5,
            balance: [0.05, 0.015, -0.06],
            contrast: 1.5, channelContrast: [1.0, 1.0, 0.95], toe: 0.7, rolloff: 0.9, midGrey: 0.17,
            black: [0.012, 0.011, 0.011], white: [1.0, 0.98, 0.92], printSaturation: 0.95),
        grain: GrainSettings(amount: 28, size: 30, softness: 30, chroma: 40),
        halation: HalationSettings(amount: 30, radius: 35), bloom: BloomSettings(amount: 22, radius: 40))

    static let nocturne800 = FilmStock(
        id: "nocturne-800", name: "Nocturne 800", format: "Cinema Negative",
        summary: "Moody and cinematic. Teal shadows, dense warm midtones, restrained color.",
        response: FilmResponse(
            exposure: -0.05,
            crosstalk: [1.05, -0.03, -0.02, -0.02, 1.04, -0.02, -0.02, 0.07, 0.95],
            separation: 0.93, shoulderStart: 3.0, shoulderRange: 5,
            balance: [0.02, 0.0, -0.02],
            contrast: 1.85, channelContrast: [1.03, 1.0, 0.9], toe: 0.8, rolloff: 1.05, midGrey: 0.145,
            black: [0.004, 0.009, 0.014], white: [1.0, 0.985, 0.95], printSaturation: 0.92),
        grain: GrainSettings(amount: 42, size: 45, softness: 35, chroma: 45),
        halation: HalationSettings(amount: 45, radius: 40), bloom: BloomSettings(amount: 25, radius: 45))

    static let aurora50 = FilmStock(
        id: "aurora-50", name: "Aurora 50", format: "Cinema Daylight",
        summary: "Clean, rich and precise. Fine grain, natural color, a polished feature-film print.",
        response: FilmResponse(
            exposure: 0.0,
            crosstalk: [1.03, -0.02, -0.01, -0.02, 1.03, -0.01, -0.01, -0.02, 1.03],
            separation: 1.04, shoulderStart: 3.0, shoulderRange: 5,
            balance: [0.01, 0.0, -0.01],
            contrast: 1.78, channelContrast: [1.0, 1.0, 0.96], toe: 0.85, rolloff: 1.0, midGrey: 0.155,
            black: [0.003, 0.004, 0.006], white: [1.0, 0.99, 0.97], printSaturation: 1.0),
        grain: GrainSettings(amount: 15, size: 18, softness: 20, chroma: 35),
        halation: HalationSettings(amount: 22, radius: 30), bloom: BloomSettings(amount: 15, radius: 40))

    static let golden200 = FilmStock(
        id: "golden-200", name: "Golden 200", format: "Color Negative",
        summary: "Sunny and nostalgic. Buttery yellows, warm blacks, holiday-snapshot color.",
        response: FilmResponse(
            exposure: 0.1,
            crosstalk: [1.05, 0.0, -0.05, 0.03, 1.0, -0.03, 0.0, -0.03, 1.03],
            separation: 1.08, shoulderStart: 2.7, shoulderRange: 4.5,
            balance: [0.07, 0.035, -0.11],
            contrast: 1.6, channelContrast: [1.0, 1.0, 0.94], toe: 0.75, rolloff: 0.95, midGrey: 0.165,
            black: [0.012, 0.009, 0.004], white: [1.0, 0.97, 0.87], printSaturation: 1.0),
        grain: GrainSettings(amount: 35, size: 35, softness: 30, chroma: 45),
        halation: HalationSettings(amount: 30, radius: 35, warmth: 60), bloom: BloomSettings(amount: 20, radius: 40))

    static let verdant200 = FilmStock(
        id: "verdant-200", name: "Verdant 200", format: "Color Negative",
        summary: "Cool everyday film. Emerald greens, crisp skies, clean neutral skin.",
        response: FilmResponse(
            exposure: 0.1,
            crosstalk: [1.04, -0.02, -0.02, -0.04, 1.06, -0.02, -0.01, 0.04, 0.97],
            separation: 1.05, shoulderStart: 2.7, shoulderRange: 4.5,
            balance: [-0.03, 0.015, 0.015],
            contrast: 1.62, channelContrast: [1.0, 0.98, 0.97], toe: 0.78, rolloff: 1.0, midGrey: 0.16,
            black: [0.005, 0.008, 0.008], white: [0.97, 1.0, 0.99], printSaturation: 0.97),
        grain: GrainSettings(amount: 32, size: 32, softness: 30, chroma: 40),
        halation: HalationSettings(amount: 25, radius: 35), bloom: BloomSettings(amount: 18, radius: 40))

    static let chrome100 = FilmStock(
        id: "chrome-100", name: "Chrome 100", format: "Color Reversal",
        summary: "Punchy slide film. Deep blacks, vivid separation, crisp highlights.",
        response: FilmResponse(
            exposure: -0.15,
            crosstalk: [1.03, -0.02, -0.01, -0.02, 1.03, -0.01, -0.01, -0.02, 1.03],
            separation: 1.06, shoulderStart: 2.5, shoulderRange: 3.6,
            balance: [-0.01, 0.0, 0.02],
            contrast: 2.05, channelContrast: [1.0, 1.0, 1.02], toe: 0.95, rolloff: 1.25, midGrey: 0.14,
            black: [0.0, 0.0, 0.002], white: [1.0, 1.0, 1.0], printSaturation: 1.0),
        grain: GrainSettings(amount: 18, size: 20, softness: 20, chroma: 30),
        halation: HalationSettings(amount: 15, radius: 25), bloom: BloomSettings(amount: 12, radius: 35))

    static let silver400 = FilmStock(
        id: "silver-400", name: "Silver 400", format: "Black & White",
        summary: "Classic panchromatic black and white on a faintly warm paper.",
        response: FilmResponse(
            exposure: 0.0,
            crosstalk: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            separation: 0, shoulderStart: 2.8, shoulderRange: 4.5,
            balance: [0.015, 0.0, -0.02],
            contrast: 1.8, channelContrast: [1, 1, 1], toe: 0.8, rolloff: 1.05, midGrey: 0.15,
            black: [0.006, 0.005, 0.004], white: [1.0, 0.99, 0.965], printSaturation: 1),
        grain: GrainSettings(amount: 38, size: 35, softness: 30, chroma: 0),
        halation: HalationSettings(amount: 0, radius: 30), bloom: BloomSettings(amount: 20, radius: 40))
}
