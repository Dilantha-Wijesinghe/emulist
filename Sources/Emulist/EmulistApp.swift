import AppKit
import SwiftUI

@main
struct EmulistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Emulist", id: "main") {
            ContentView(workspace: appDelegate.workspace)
                .frame(minWidth: 1100, minHeight: 800)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands(workspace: appDelegate.workspace) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspace = Workspace()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also allows running the bare executable (e.g. `swift run`) as a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        ClickAwayEndsEditing.install()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        workspace.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    let workspace: Workspace
    @FocusedValue(\.isTypingValue) private var isTyping

    private var noClip: Bool { workspace.media == nil }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Clips or Open Project…") { workspace.presentOpenPanel() }.keyboardShortcut("o")
            Button("Close Project") { workspace.closeProject() }.disabled(workspace.clips.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Project") { workspace.save() }.keyboardShortcut("s").disabled(workspace.clips.isEmpty)
            Button("Save Project As…") { workspace.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspace.clips.isEmpty)
            Divider()
            Button("Export…") { workspace.isExportSheetPresented = true }.keyboardShortcut("e")
                .disabled(workspace.media == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { workspace.undo() }.keyboardShortcut("z").disabled(!workspace.canUndo)
            Button("Redo") { workspace.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.canRedo)
        }
        CommandMenu("Grade") {
            Button("Copy Grade") { workspace.copyGrade() }.keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(noClip)
            Button("Paste Grade") { workspace.pasteGrade() }.keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(workspace.copiedGrade == nil || noClip)
            Button("Paste Grade…") { workspace.isPasteSheetPresented = true }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
                .disabled(workspace.copiedGrade == nil || noClip)
            Button("Apply Grade to All Clips") { workspace.applyGradeToAllClips() }.disabled(workspace.clips.count < 2)
            Divider()
            Button("Take Snapshot") { workspace.takeSnapshot() }.keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(noClip)
            Button("Save Look…") { workspace.saveLook() }.disabled(noClip)
        }
        CommandMenu("Clip") {
            Button("Previous Clip") { workspace.selectAdjacentClip(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(workspace.clips.count < 2)
            Button("Next Clip") { workspace.selectAdjacentClip(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(workspace.clips.count < 2)
            Divider()
            Button("Remove Clip from Project") { workspace.selectedClipID.map(workspace.removeClip) }.disabled(noClip)
        }
        CommandMenu("Playback") {
            Button(workspace.playback.isPlaying ? "Pause" : "Play") { workspace.playback.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(isTyping == true)
            Button("Previous Frame") { workspace.playback.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(isTyping == true)
            Button("Next Frame") { workspace.playback.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(isTyping == true)
            Button("Go to Start") { workspace.playback.seek(to: 0) }.keyboardShortcut(.home, modifiers: [])
                .disabled(isTyping == true)
            Divider()
            Toggle("Loop", isOn: Binding(get: { workspace.playback.isLooping }, set: { workspace.playback.isLooping = $0 }))
        }
        CommandGroup(before: .toolbar) {
            Button("Before / After") { workspace.toggleBefore() }.keyboardShortcut("b", modifiers: [])
                .disabled(workspace.media == nil || isTyping == true)
            Button("Split Before / After") { workspace.toggleSplit() }
                .keyboardShortcut("b", modifiers: [.shift])
                .disabled(workspace.media == nil || isTyping == true)
            Divider()
        }
    }
}
