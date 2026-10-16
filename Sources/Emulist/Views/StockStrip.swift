import EmulistCore
import SwiftUI

/// The film stock browser: every look rendered live on the current frame.
struct StockStrip: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(FilmStock.builtIn) { stock in
                    StockCard(
                        stock: stock,
                        image: workspace.thumbnails.images[stock.id],
                        aspect: workspace.media.map { Double($0.width) / Double($0.height) } ?? 16 / 9,
                        isSelected: workspace.settings.stockID == stock.id
                    ) {
                        workspace.select(stock)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .background(Theme.window)
    }
}

private struct StockCard: View {
    let stock: FilmStock
    let image: CGImage?
    let aspect: Double
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private let height: CGFloat = 76

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    Theme.raised
                    if let image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: height * aspect, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Theme.accent : .white.opacity(isHovering ? 0.25 : 0.06),
                                      lineWidth: isSelected ? 2 : 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
                    Text(stock.format).font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(stock.summary)
    }
}
