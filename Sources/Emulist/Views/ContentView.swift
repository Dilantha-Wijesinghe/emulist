import EmulistCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let media = workspace.media {
                // The color page: looks | viewer above, grading palettes below.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        LookLibraryView(workspace: workspace)
                        separator.frame(width: 1)
                        VStack(spacing: 0) {
                            ZStack {
                                Theme.viewer
                                ViewerView(workspace: workspace)
                                CompareOverlay(workspace: workspace, contentSize: CGSize(width: media.width, height: media.height))
                            }
                            separator.frame(height: 1)
                            TransportBar(workspace: workspace)
                            clipStrip
                        }
                    }
                    separator.frame(height: 1)
                    GradingPanel(workspace: workspace)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    EmptyStateView(workspace: workspace, isTargeted: isDropTargeted)
                    clipStrip
                }
            }
        }
        .background(Theme.window)
        .background(WindowTitle(workspace: workspace))
        .toolbar { toolbar }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: drop)
        .sheet(isPresented: $workspace.isExportSheetPresented) { ExportSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.needsProfileConfirmation) { ProfileSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.isPasteSheetPresented) { PasteGradeSheet(workspace: workspace) }
        .sheet(item: $workspace.lookDraft) { SaveLookSheet(workspace: workspace, draft: $0) }
        .sheet(item: $workspace.cubeDraft) { ExportCubeSheet(workspace: workspace, draft: $0) }
        .alert(item: $workspace.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var separator: some View { Rectangle().fill(Theme.separator) }

    /// Shown once the session has more than one clip.
    @ViewBuilder private var clipStrip: some View {
        if workspace.clips.count > 1 {
            separator.frame(height: 1)
            ClipStrip(workspace: workspace)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { workspace.presentOpenPanel() } label: { Label("Add Clips", systemImage: "plus") }
                .help("Add clips, or open a project (⌘O)")
        }
        if workspace.media != nil {
            ToolbarItemGroup(placement: .principal) {
                // Latching buttons: one press shows the ungraded image, the next brings the grade back.
                Toggle(isOn: Binding(get: { workspace.compare == .before }, set: { _ in workspace.toggleBefore() })) {
                    Label("Before / After", systemImage: "circle.lefthalf.filled")
                }
                .help(workspace.compare == .before ? "Showing the ungraded image · click for the grade (B)"
                                                   : "Show the ungraded image (B)")
                Toggle(isOn: Binding(get: { workspace.compare == .split }, set: { _ in workspace.toggleSplit() })) {
                    Label("Split", systemImage: "rectangle.split.2x1")
                }
                .help("Split before / after, drag the divider to wipe (⇧B)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                SnapshotsMenu(workspace: workspace)
                Button { workspace.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!workspace.canUndo)
                    .help("Undo (⌘Z)")
                Button { workspace.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!workspace.canRedo)
                    .help("Redo (⇧⌘Z)")
                Button { workspace.presentExport(.selectedClip) } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export (⌘E)")
            }
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = try? await provider.loadURL() { urls.append(url) }
            }
            workspace.open(urls)
        }
        return true
    }
}

/// The window's title and subtitle. A separate view, so that only it (not the whole window) updates
/// when the grade changes.
private struct WindowTitle: View {
    let workspace: Workspace

    var body: some View {
        Color.clear
            .navigationTitle(workspace.title)
            .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        guard let media = workspace.media else { return "" }
        let fps = media.frameRate.rounded() == media.frameRate ? "\(Int(media.frameRate))" : String(format: "%.3f", media.frameRate)
        let edited = workspace.hasUnsavedChanges && workspace.projectURL != nil ? " · Edited" : ""
        return "\(media.resolutionLabel) · \(fps) fps · \(workspace.settings.cameraProfile.name)\(edited)"
    }
}

/// Asked when the file's metadata doesn't identify its LOG encoding: interpreting it wrongly ruins every look.
private struct ProfileSheet: View {
    @Bindable var workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How was this clip recorded?").font(.system(size: 16, weight: .semibold))
            Text("The file doesn’t say which LOG profile it uses. Pick the camera setting it was shot with — you can change this later under Input.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if workspace.media?.isAppleLog2 == true {
                Label("This clip is Apple Log 2. Apple hasn’t published its color space yet, so Apple Log is the closest match — colors may be slightly off.", systemImage: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                ForEach(CameraProfile.all) { profile in
                    let selected = workspace.settings.cameraProfileID == profile.id
                    Button {
                        workspace.edit { $0.cameraProfileID = profile.id }
                    } label: {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? Theme.accent : Theme.tertiaryText)
                            Text(profile.name)
                            Spacer()
                        }
                        .padding(10)
                        .background(Theme.raised.opacity(selected ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Continue") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

private extension NSItemProvider {
    func loadURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: url) }
            }
        }
    }
}
