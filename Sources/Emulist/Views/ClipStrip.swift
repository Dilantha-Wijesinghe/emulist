import EmulistCore
import SwiftUI

/// The session's clips under the viewer, each with a live graded thumbnail. Click to grade a clip;
/// ⌘-click to pick several, so one paste reaches them all.
struct ClipStrip: View {
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CLIPS").captionStyle()
                Text("\(workspace.clips.count)").captionStyle()
            }
            .frame(width: 36, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(workspace.clips) { clip in
                        ClipTile(
                            name: clip.name, image: workspace.clipThumbnails.images[clip.id], isMissing: clip.media == nil,
                            isSelected: clip.id == workspace.selectedClipID,
                            isPicked: clip.id != workspace.selectedClipID && workspace.pickedClipIDs.contains(clip.id))
                        .equatable()
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) { workspace.togglePicked(clip.id) } else { workspace.selectClip(clip.id) }
                        }
                        .contextMenu { menu(for: clip) }
                    }
                    Button { workspace.presentOpenPanel() } label: {
                        Image(systemName: "plus").frame(width: 40, height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 4))
                    .help("Add clips")
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 16)
        .background(Theme.window)
    }

    @ViewBuilder private func menu(for clip: Clip) -> some View {
        Button("Grade This Clip") { workspace.selectClip(clip.id) }
        Divider()
        Button("Paste Grade Here") {
            workspace.selectClip(clip.id)
            workspace.pasteGrade()
        }
        .disabled(workspace.copiedGrade == nil)
        Divider()
        Button("Remove from Project", role: .destructive) { workspace.removeClip(clip.id) }
    }
}

private struct ClipTile: View, Equatable {
    let name: String
    let image: CGImage?
    let isMissing: Bool
    let isSelected: Bool
    let isPicked: Bool

    nonisolated static func == (a: ClipTile, b: ClipTile) -> Bool {
        a.name == b.name && a.image === b.image && a.isMissing == b.isMissing && a.isSelected == b.isSelected
            && a.isPicked == b.isPicked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Theme.inset
                .frame(width: 96, height: 54)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else if isMissing {
                        Image(systemName: "questionmark.folder").foregroundStyle(Theme.accent)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected || isPicked ? Theme.accent : .white.opacity(0.08),
                                      style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isPicked ? [3, 2] : [])))
                .overlay(alignment: .topTrailing) {
                    if isPicked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                            .padding(3)
                    }
                }
            Text(name)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
        }
        .contentShape(Rectangle())
        .help(isMissing ? "\(name) · footage not found" : "\(name) · ⌘-click to pick several clips for pasting")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
