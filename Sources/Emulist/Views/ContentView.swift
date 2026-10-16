import EmulistCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let media = workspace.media {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ZStack {
                            Theme.viewer
                            ViewerView(workspace: workspace)
                            CompareOverlay(workspace: workspace, contentSize: CGSize(width: media.width, height: media.height))
                        }
                        Divider().overlay(Theme.separator)
                        TransportBar(workspace: workspace)
                        Divider().overlay(Theme.separator)
                        StockStrip(workspace: workspace)
                    }
                    Divider().overlay(Theme.separator)
                    InspectorView(workspace: workspace)
                }
            } else {
                EmptyStateView(workspace: workspace, isTargeted: isDropTargeted)
            }
        }
        .background(Theme.window)
        .navigationTitle(workspace.title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: drop)
        .sheet(isPresented: $workspace.isExportSheetPresented) { ExportSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.needsProfileConfirmation) { ProfileSheet(workspace: workspace) }
        .alert(item: $workspace.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var subtitle: String {
        guard let media = workspace.media else { return "" }
        let fps = media.frameRate.rounded() == media.frameRate ? "\(Int(media.frameRate))" : String(format: "%.3f", media.frameRate)
        let edited = workspace.hasUnsavedChanges && workspace.projectURL != nil ? " · Edited" : ""
        return "\(media.resolutionLabel) · \(fps) fps · \(workspace.settings.cameraProfile.name)\(edited)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { workspace.presentOpenPanel() } label: { Label("Open", systemImage: "plus") }
                .help("Open footage or a project (⌘O)")
        }
        if workspace.media != nil {
            ToolbarItem(placement: .principal) {
                Picker("Compare", selection: $workspace.compare) {
                    Image(systemName: "rectangle").help("Graded").tag(CompareMode.off)
                    Image(systemName: "rectangle.split.2x1").help("Split before / after").tag(CompareMode.split)
                    Image(systemName: "rectangle.dashed").help("Before (B)").tag(CompareMode.before)
                }
                .pickerStyle(.segmented)
                .help("Compare with the ungraded image")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { workspace.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!workspace.canUndo)
                    .help("Undo (⌘Z)")
                Button { workspace.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!workspace.canRedo)
                    .help("Redo (⇧⌘Z)")
                Button { workspace.isExportSheetPresented = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export (⌘E)")
            }
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in workspace.open(url) }
        }
        return true
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
