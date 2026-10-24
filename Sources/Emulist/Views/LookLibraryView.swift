import EmulistCore
import SwiftUI

/// The look browser (like Resolve's LUT gallery): your saved looks and every film look, rendered live on
/// the current frame with the current grade, grouped by collection, with Fujifilm's simulations a click away.
struct LookLibraryView: View {
    @Bindable var workspace: Workspace
    @State private var renaming: GradePreset?
    @State private var newName = ""

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS").captionStyle()
                Spacer()
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
            Rectangle().fill(Theme.separator).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !workspace.presets.isEmpty {
                        section("My Looks", count: workspace.presets.count) {
                            ForEach(workspace.presets) { preset in
                                LookTile(name: preset.name, help: "\(preset.name)\nApplies: \(groupList(preset))",
                                         image: workspace.thumbnails.images[LibraryThumbnails.id(for: preset)],
                                         isSelected: false) {
                                    workspace.apply(preset)
                                }
                                .equatable()
                                .contextMenu {
                                    Button("Apply") { workspace.apply(preset) }
                                    Button("Rename…") {
                                        newName = preset.name
                                        renaming = preset
                                    }
                                    Button("Export as .cube…") { workspace.exportCube(preset) }
                                    Divider()
                                    Button("Delete", role: .destructive) { workspace.delete(preset) }
                                }
                            }
                        }
                    }
                    ForEach(workspace.looks.groupedByCollection, id: \.name) { collection in
                        section(collection.name, count: collection.looks.count) {
                            ForEach(collection.looks) { look in
                                LookTile(name: look.name, help: "\(look.name) · \(look.format)\n\(look.summary)",
                                         image: workspace.thumbnails.images[look.id],
                                         isSelected: workspace.settings.stockID == look.id) {
                                    workspace.select(look)
                                }
                                .equatable()
                            }
                        }
                        if collection.name == FujifilmLooks.collection && !workspace.recipes.isEmpty { recipes }
                    }
                    if !workspace.hasFujifilmLooks { FujifilmOffer(workspace: workspace) }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
        }
        .frame(width: Theme.libraryWidth)
        .background(Theme.panel)
        .alert("Rename Look", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let renaming, !name.isEmpty { workspace.rename(renaming, to: name) }
            }
        }
    }

    /// Recipes on Fujifilm's simulations, right after them.
    private var recipes: some View {
        section(FilmRecipe.fujiXWeeklyCollection, count: workspace.recipes.count) {
            ForEach(workspace.recipes) { look in
                LookTile(name: look.recipe.name, help: help(look),
                         image: workspace.thumbnails.images[LibraryThumbnails.id(for: look.preset)], isSelected: false) {
                    workspace.apply(look.preset)
                }
                .equatable()
                .contextMenu {
                    Button("Apply") { workspace.apply(look.preset) }
                    Button("Export as .cube…") { workspace.exportCube(look.preset) }
                    Button("Open Recipe Page") { NSWorkspace.shared.open(look.recipe.url) }
                }
            }
        }
    }

    private func help(_ look: RecipeLook) -> String {
        let ignored = look.recipe.ignoredSettings
        return """
            \(look.recipe.name) · on \(look.preset.settings.stock.name)
            A Fuji X Weekly recipe, approximated: its white balance shift becomes printer lights, and its tone, \
            color, Color Chrome and grain become Emulist’s controls. Your clip’s exposure and white balance stay.
            \(ignored.isEmpty ? "" : "Not applied yet: \(ignored.joined(separator: ", ")).\n")Right-click for the recipe page.
            """
    }

    private func section<Tiles: View>(_ title: String, count: Int, @ViewBuilder tiles: () -> Tiles) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).captionStyle()
                Spacer()
                Text("\(count)").captionStyle()
            }
            LazyVGrid(columns: columns, spacing: 10, content: tiles)
        }
    }

    private func groupList(_ preset: GradePreset) -> String {
        GradeGroup.allCases.filter(preset.groups.contains).map(\.name).joined(separator: ", ")
    }
}

/// One look or saved look: its live thumbnail and name.
private struct LookTile: View, Equatable {
    let name: String
    let help: String
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    nonisolated static func == (a: LookTile, b: LookTile) -> Bool {
        a.name == b.name && a.help == b.help && a.image === b.image && a.isSelected == b.isSelected
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
        .onHover { isHovering = $0 }
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
