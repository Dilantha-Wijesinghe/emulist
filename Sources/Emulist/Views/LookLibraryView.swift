import EmulistCore
import SwiftUI

/// The look browser (like Resolve's LUT gallery): favorites, recently used and saved looks, then every film
/// look and recipe, rendered live on the current frame with the current grade. Resting the pointer on a
/// tile previews it in the viewer; a click applies it. A search narrows every section.
struct LookLibraryView: View {
    @Bindable var workspace: Workspace
    @State private var renaming: GradePreset?
    @State private var newName = ""
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            SearchField(text: $query)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            Rectangle().fill(Theme.separator).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let sections = self.sections
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(section.title, count: section.count)
                            ForEach(section.groups, id: \.title) { group in
                                if let title = group.title {
                                    Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.secondaryText)
                                        .padding(.top, 2)
                                }
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(group.items) { tile($0) }
                                }
                            }
                        }
                    }
                    if sections.isEmpty {
                        Text("No looks match “\(query)”.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                    if !workspace.hasFujifilmLooks && query.isEmpty { FujifilmOffer(workspace: workspace) }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
        }
        .frame(width: Theme.libraryWidth)
        .background(Theme.panel)
        .onDisappear { workspace.endPreview() }
        .alert("Rename Look", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let renaming, !name.isEmpty { workspace.rename(renaming, to: name) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("LOOKS").captionStyle()
            Spacer()
            Toggle(isOn: Binding(get: { workspace.layout.previewsLooksOnHover },
                                 set: { workspace.layout.previewsLooksOnHover = $0 })) {
                Image(systemName: workspace.layout.previewsLooksOnHover ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .foregroundStyle(workspace.layout.previewsLooksOnHover ? Theme.accent : Theme.secondaryText)
            .help(workspace.layout.previewsLooksOnHover
                  ? "Live preview is on: rest the pointer on a look to see it in the viewer, click to apply"
                  : "Live preview is off: click a look to apply it")
            Menu {
                Button("Save Current Look…") { workspace.saveLook() }
                Button("Import .cube LUTs…") { workspace.presentImportLUT() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Save the current grade as a look, or import .cube LUTs (you can also drop them on the window)")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    // MARK: Sections

    private struct Section: Identifiable {
        struct Group {
            var title: String?
            var items: [LibraryItem]
        }

        let title: String
        var groups: [Group]
        var id: String { title }
        var count: Int { groups.reduce(0) { $0 + $1.items.count } }
    }

    /// Top to bottom, narrowed by the search: favorites, recent (when not searching), my looks, then each
    /// collection, with the recipes after the Fujifilm simulations they build on, grouped by simulation.
    private var sections: [Section] {
        let looks = workspace.looks.map { LibraryItem(source: .look($0)) }
        let presets = workspace.presets.map { LibraryItem(source: .preset($0)) }
        let recipes = workspace.recipes.map { LibraryItem(source: .recipe($0)) }
        let byID = Dictionary((presets + looks + recipes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func found(_ items: [LibraryItem]) -> [LibraryItem] { query.isEmpty ? items : items.filter { $0.matches(query) } }
        func section(_ title: String, _ items: [LibraryItem]) -> Section? {
            let items = found(items)
            return items.isEmpty ? nil : Section(title: title, groups: [.init(items: items)])
        }

        let favorites = (presets + looks + recipes).filter { workspace.marks.favorites.contains($0.id) }
        var sections = [
            section("Favorites", favorites),
            query.isEmpty ? section("Recent", workspace.marks.recent.compactMap { byID[$0] }) : nil,
            section("My Looks", presets),
        ]
        for collection in workspace.looks.groupedByCollection {
            sections.append(section(collection.name, collection.looks.map { LibraryItem(source: .look($0)) }))
            if collection.name == FujifilmLooks.collection { sections.append(recipeSection(recipes, found: found)) }
        }
        return sections.compactMap { $0 }
    }

    /// Recipes under the name of the simulation each one is built on, in the simulations' order.
    private func recipeSection(_ recipes: [LibraryItem], found: ([LibraryItem]) -> [LibraryItem]) -> Section? {
        let simulations = workspace.looks.filter { $0.collection == FujifilmLooks.collection }
        let groups: [Section.Group] = simulations.compactMap { simulation in
            let items = found(recipes.filter { item in
                if case .recipe(let recipe) = item.source { recipe.preset.settings.stockID == simulation.id } else { false }
            })
            return items.isEmpty ? nil : .init(title: "on \(simulation.name)", items: items)
        }
        return groups.isEmpty ? nil : Section(title: FilmRecipe.fujiXWeeklyCollection, groups: groups)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased()).captionStyle()
            Spacer()
            Text("\(count)").captionStyle()
        }
    }

    // MARK: Tiles

    private func tile(_ item: LibraryItem) -> some View {
        LookTile(name: item.name, help: help(item), image: workspace.thumbnails.images[item.id],
                 isSelected: isSelected(item), isFavorite: workspace.marks.favorites.contains(item.id),
                 action: { workspace.apply(item) },
                 hover: { inside in
                     guard workspace.layout.previewsLooksOnHover else { return }
                     inside ? workspace.beginPreview(item) : workspace.endPreview(item)
                 })
            .equatable()
            .contextMenu { menu(item) }
    }

    private func isSelected(_ item: LibraryItem) -> Bool {
        if case .look(let look) = item.source { workspace.settings.stockID == look.id } else { false }
    }

    @ViewBuilder
    private func menu(_ item: LibraryItem) -> some View {
        Button("Apply") { workspace.apply(item) }
        Button(workspace.marks.favorites.contains(item.id) ? "Remove from Favorites" : "Add to Favorites") {
            workspace.marks.toggleFavorite(item.id)
        }
        Button("Export as .cube…") { workspace.exportCube(item) }
        switch item.source {
        case .look: EmptyView()
        case .preset(let preset):
            Button("Rename…") {
                newName = preset.name
                renaming = preset
            }
            Divider()
            Button("Delete", role: .destructive) { workspace.delete(preset) }
        case .recipe(let recipe):
            Button("Open Recipe Page") { NSWorkspace.shared.open(recipe.recipe.url) }
        }
    }

    private func help(_ item: LibraryItem) -> String {
        switch item.source {
        case .look(let look):
            return "\(look.name) · \(look.format)\n\(look.summary)"
        case .preset(let preset):
            return "\(preset.name)\nApplies: \(GradeGroup.allCases.filter(preset.groups.contains).map(\.name).joined(separator: ", "))"
        case .recipe(let look):
            let ignored = look.recipe.ignoredSettings
            return """
                \(look.recipe.name) · on \(look.preset.settings.stock.name)
                A Fuji X Weekly recipe, approximated: its white balance shift becomes printer lights, and its tone, \
                color, Color Chrome and grain become Emulist’s controls. Your clip’s exposure and white balance stay.
                \(ignored.isEmpty ? "" : "Not applied yet: \(ignored.joined(separator: ", ")).\n")Right-click for the recipe page.
                """
        }
    }
}

/// The library's search field. Typing in it never triggers the viewer's single-key shortcuts.
private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
            TextField("Search looks", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isFocused)
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
                .focusedValue(\.isTypingValue, true)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Clear the search")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// One look or saved look: its live thumbnail and name.
private struct LookTile: View, Equatable {
    let name: String
    let help: String
    let image: CGImage?
    let isSelected: Bool
    let isFavorite: Bool
    let action: () -> Void
    let hover: (Bool) -> Void
    @State private var isHovering = false

    nonisolated static func == (a: LookTile, b: LookTile) -> Bool {
        a.name == b.name && a.help == b.help && a.image === b.image && a.isSelected == b.isSelected
            && a.isFavorite == b.isFavorite
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                // The tile sets the size; the image fills it from an overlay, so it can never widen the column.
                Theme.inset
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(3)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Theme.accent : .white.opacity(isHovering ? 0.3 : 0.07),
                                      lineWidth: isSelected ? 2 : 1))
                .shadow(color: isSelected ? Theme.accent.opacity(0.35) : .clear, radius: 4)
                Text(name)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovering = inside
            hover(inside)
        }
        .help(help)
    }
}

/// Offers Fujifilm's official film simulation LUTs, downloaded from Fujifilm on request.
private struct FujifilmOffer: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FUJIFILM").captionStyle()
            Text("Classic Chrome, Classic Neg., Eterna, Velvia, Acros and more: Fujifilm’s official film simulation LUTs, bridged from your footage.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                workspace.installFujifilm()
            } label: {
                HStack(spacing: 6) {
                    if workspace.isInstallingFujifilm { ProgressView().controlSize(.mini) }
                    Text(workspace.isInstallingFujifilm ? "Downloading…" : "Download from Fujifilm (\(FujifilmLooks.packageSize))")
                }
            }
            .controlSize(.small)
            .disabled(workspace.isInstallingFujifilm)
        }
        .padding(10)
        .moduleBackground()
    }
}
