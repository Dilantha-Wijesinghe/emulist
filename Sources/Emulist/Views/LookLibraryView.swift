import EmulistCore
import SwiftUI

/// The look browser (like Resolve's LUT gallery): every look rendered live on the current frame,
/// grouped by collection, with Fujifilm's simulations a click away.
struct LookLibraryView: View {
    @Bindable var workspace: Workspace

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS").captionStyle()
                Spacer()
                Button { workspace.presentImportLUT() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Import .cube LUTs (or drop them on the window)")
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            Rectangle().fill(Theme.separator).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(workspace.looks.groupedByCollection, id: \.name) { collection in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(collection.name.uppercased()).captionStyle()
                                Spacer()
                                Text("\(collection.looks.count)").captionStyle()
                            }
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(collection.looks) { look in
                                    LookTile(look: look, image: workspace.thumbnails.images[look.id],
                                             isSelected: workspace.settings.stockID == look.id) {
                                        workspace.select(look)
                                    }
                                }
                            }
                        }
                    }
                    if !workspace.hasFujifilmLooks { FujifilmOffer(workspace: workspace) }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
        }
        .frame(width: Theme.libraryWidth)
        .background(Theme.panel)
    }
}

private struct LookTile: View {
    let look: FilmStock
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Theme.inset
                    if let image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Theme.accent : .white.opacity(isHovering ? 0.3 : 0.07),
                                      lineWidth: isSelected ? 2 : 1))
                .shadow(color: isSelected ? Theme.accent.opacity(0.35) : .clear, radius: 4)
                Text(look.name)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(look.name) · \(look.format)\n\(look.summary)")
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
