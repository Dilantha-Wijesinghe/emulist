import EmulistCore
import SwiftUI

/// A switch per grade group: which parts of a grade to paste or save.
struct GradeGroupSwitches: View {
    @Binding var selection: Set<GradeGroup>

    var body: some View {
        VStack(spacing: 0) {
            ForEach(GradeGroup.allCases) { group in
                HStack {
                    Text(group.name).font(.system(size: 12))
                    Spacer()
                    Toggle(group.name, isOn: Binding(
                        get: { selection.contains(group) },
                        set: { isOn in if isOn { selection.insert(group) } else { selection.remove(group) } }))
                        .toggleStyle(AnalogSwitchStyle(name: group.name))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if group != GradeGroup.allCases.last { Rectangle().fill(Theme.separator).frame(height: 1) }
            }
        }
        .moduleBackground()
    }
}

/// Paste Grade…: choose which parts of the copied grade go onto the picked clips (or every clip).
struct PasteGradeSheet: View {
    @Bindable var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var toAllClips = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste Grade").font(.system(size: 16, weight: .semibold))
            Text("Choose what to paste. Each clip keeps everything else, and each paste can be undone on its clip.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            GradeGroupSwitches(selection: $workspace.pasteGroups)
            HStack {
                Text(toAllClips ? "Onto all \(workspace.clips.count) clips" : "Onto \(targetDescription)")
                    .font(.system(size: 12))
                Spacer()
                Toggle("All clips", isOn: $toAllClips).toggleStyle(AnalogSwitchStyle(name: "All clips"))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Paste") {
                    workspace.pasteGrade(toAllClips: toAllClips)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workspace.pasteGroups.isEmpty || workspace.copiedGrade == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var targetDescription: String {
        let count = workspace.pickedClipIDs.count
        return count > 1 ? "the \(count) picked clips" : "this clip"
    }
}

/// Save Look…: name a grade and choose which parts it carries, for "My Looks".
struct SaveLookSheet: View {
    let workspace: Workspace
    @State var draft: LookDraft
    @State private var groups = GradeGroup.creative
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Look").font(.system(size: 16, weight: .semibold))
            TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
            Text("A look applies only the parts you choose, so a clip keeps its own exposure and white balance.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            GradeGroupSwitches(selection: $groups)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    workspace.savePreset(name: name, groups: groups, settings: draft.settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(groups.isEmpty || name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var name: String { draft.name.trimmingCharacters(in: .whitespaces) }
}

/// Export Look as .cube…: bakes a grade into a 3D LUT for other apps, e.g. DaVinci Resolve.
struct ExportCubeSheet: View {
    let workspace: Workspace
    let draft: LookDraft
    @State private var inputID: String
    @State private var output = OutputTransform.rec709Gamma24
    @State private var size = 33
    @State private var isExporting = false
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, draft: LookDraft) {
        self.workspace = workspace
        self.draft = draft
        _inputID = State(initialValue: draft.settings.cameraProfileID)
    }

    private var input: CameraProfile { CameraProfile.with(id: inputID) ?? .appleLog }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Look as .cube").font(.system(size: 16, weight: .semibold))
            Text(draft.name).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            row("Input") {
                Picker("Input", selection: $inputID) {
                    ForEach(CameraProfile.all) { Text($0.name).tag($0.id) }
                }
            }
            row("Output") {
                Picker("Output", selection: $output) {
                    ForEach(OutputTransform.allCases) { Text($0.name).tag($0) }
                }
            }
            row("Grid") {
                Picker("Grid", selection: $size) {
                    Text("33").tag(33)
                    Text("65").tag(65)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Text("Maps \(input.name) footage to \(output.name) with the look’s film, primaries and printer lights. Grain, halation and bloom work across neighboring pixels, so no LUT can carry them. The clip’s exposure and white balance are left out.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if isExporting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export…", action: export).keyboardShortcut(.defaultAction)
            }
            .disabled(isExporting)
        }
        .padding(24)
        .frame(width: 420)
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondaryText)
            Spacer()
            control().labelsHidden()
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Workspace.cubeType]
        panel.nameFieldStringValue = "\(draft.name).cube"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var settings = draft.settings
        settings.output = output
        let (input, size, title) = (input, size, draft.name)
        isExporting = true
        Task {
            // A 65-point LUT is 275k lines of text: bake and write off the main thread.
            let result = await Task.detached { [settings] in
                Result { try CubeLUT(baking: settings, input: input, size: size, title: title).cubeData().write(to: url, options: .atomic) }
            }.value
            isExporting = false
            if case .failure(let error) = result {
                workspace.alert = AppAlert(title: "Couldn’t export “\(url.lastPathComponent)”", message: error.localizedDescription)
            }
            dismiss()
        }
    }
}

/// Toolbar button: click to snapshot the grade, or open the menu of this clip's snapshots.
struct SnapshotsMenu: View {
    let workspace: Workspace

    var body: some View {
        Menu {
            Button("Take Snapshot") { workspace.takeSnapshot() }
            if !workspace.snapshots.isEmpty {
                Divider()
                ForEach(workspace.snapshots.reversed()) { snapshot in
                    Menu("\(snapshot.name) · \(snapshot.createdAt.formatted(date: .omitted, time: .shortened))") {
                        Button("Restore") { workspace.restore(snapshot) }
                        Button("Save as Look…") { workspace.saveLook(from: snapshot.settings, name: snapshot.name) }
                        Divider()
                        Button("Delete", role: .destructive) { workspace.delete(snapshot) }
                    }
                }
            }
        } label: {
            Label("Snapshots", systemImage: "camera.shutter.button")
        } primaryAction: {
            workspace.takeSnapshot()
        }
        // Toolbar menus keep their first items; a new identity rebuilds them when the list changes.
        .id(workspace.snapshots.map(\.id))
        .help("Snapshot this grade (⌥⌘S) · hold for this clip’s snapshots")
    }
}
