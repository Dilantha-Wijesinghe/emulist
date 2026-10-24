import EmulistCore
import Foundation
import Observation

/// One entry of the looks library: a film look, a saved look or a recipe. Applying it, previewing it and
/// its thumbnail all go through `applied(to:)`, so they always agree.
struct LibraryItem: Identifiable, Equatable {
    enum Source: Equatable {
        case look(FilmStock)
        case preset(GradePreset)
        case recipe(RecipeLook)
    }

    let source: Source

    /// Also the item's thumbnail key in `LibraryThumbnails`.
    var id: String {
        switch source {
        case .look(let look): look.id
        case .preset(let preset): LibraryThumbnails.id(for: preset)
        case .recipe(let recipe): LibraryThumbnails.id(for: recipe.preset)
        }
    }

    var name: String {
        switch source {
        case .look(let look): look.name
        case .preset(let preset): preset.name
        case .recipe(let recipe): recipe.recipe.name
        }
    }

    /// The grade with this item applied, as its thumbnail shows it.
    func applied(to settings: GradeSettings) -> GradeSettings {
        switch source {
        case .look(let look):
            var settings = settings
            settings.select(look)
            return settings
        case .preset(let preset): return preset.applied(to: settings)
        case .recipe(let recipe): return recipe.preset.applied(to: settings)
        }
    }

    /// Whether a search for `query` finds it: by name, collection, format or the look it builds on.
    func matches(_ query: String) -> Bool {
        let terms: [String] = switch source {
        case .look(let look): [look.name, look.collection, look.format]
        case .preset(let preset): [preset.name, "My Looks", preset.settings.stock.name]
        case .recipe(let recipe): [recipe.recipe.name, FilmRecipe.fujiXWeeklyCollection, recipe.preset.settings.stock.name]
        }
        return terms.contains { $0.localizedStandardContains(query) }
    }
}

extension RecipeLook: Equatable {
    static func == (a: RecipeLook, b: RecipeLook) -> Bool { a.preset == b.preset }
}

/// Favorite and recently used library items (by id), remembered between launches.
@MainActor @Observable
final class LibraryMarks {
    static let recentCount = 4

    private(set) var favorites = Set(UserDefaults.standard.stringArray(forKey: "favoriteLooks") ?? []) {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favoriteLooks") }
    }
    /// Most recent first.
    private(set) var recent = UserDefaults.standard.stringArray(forKey: "recentLooks") ?? [] {
        didSet { UserDefaults.standard.set(recent, forKey: "recentLooks") }
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    func used(_ id: String) {
        recent = Array(([id] + recent.filter { $0 != id }).prefix(Self.recentCount))
    }
}
