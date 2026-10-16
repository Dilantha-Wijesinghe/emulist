import EmulistCore
import SwiftUI

/// Shown before any footage is open: a drop target, or a relink prompt when a project's media is missing.
struct EmptyStateView: View {
    @Bindable var workspace: Workspace
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            if let missing = workspace.missingMedia {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(Theme.accent)
                VStack(spacing: 6) {
                    Text("Footage not found").font(.system(size: 18, weight: .semibold))
                    Text("“\(URL(fileURLWithPath: missing.media.path).lastPathComponent)” was moved or deleted.\nYour grade is safe — locate the file to continue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack {
                    Button("Close Project") { workspace.closeMissingMedia() }
                    Button("Locate Footage…") { workspace.relinkMissingMedia() }.keyboardShortcut(.defaultAction)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                        .foregroundStyle(isTargeted ? Theme.accent : .white.opacity(0.15))
                        .frame(width: 120, height: 88)
                    Image(systemName: "film.stack")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(isTargeted ? Theme.accent : Theme.secondaryText)
                }
                VStack(spacing: 6) {
                    Text("Drop your LOG footage").font(.system(size: 20, weight: .semibold))
                    Text("Apple Log, S-Log3 or V-Log · MOV or MP4")
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("Open Footage…") { workspace.presentOpenPanel() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                Text("Digital footage. Analog soul.")
                    .font(.system(size: 11, weight: .medium)).tracking(1)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.viewer)
        .overlay {
            if workspace.isLoading { ProgressView().controlSize(.large) }
        }
    }
}
