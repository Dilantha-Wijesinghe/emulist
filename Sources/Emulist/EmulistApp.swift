import AppKit
import SwiftUI

@main
struct EmulistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Emulist", id: "main") {
            ContentView(workspace: appDelegate.workspace)
                .frame(minWidth: 1040, minHeight: 660)
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
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { workspace.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    let workspace: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { workspace.presentOpenPanel() }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Project") { workspace.save() }.keyboardShortcut("s").disabled(workspace.media == nil)
            Button("Save Project As…") { workspace.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspace.media == nil)
            Divider()
            Button("Export…") { workspace.isExportSheetPresented = true }.keyboardShortcut("e")
                .disabled(workspace.media == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { workspace.undo() }.keyboardShortcut("z").disabled(!workspace.canUndo)
            Button("Redo") { workspace.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.canRedo)
        }
        CommandMenu("Playback") {
            Button(workspace.playback.isPlaying ? "Pause" : "Play") { workspace.playback.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Previous Frame") { workspace.playback.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Frame") { workspace.playback.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Go to Start") { workspace.playback.seek(to: 0) }.keyboardShortcut(.home, modifiers: [])
            Divider()
            Toggle("Loop", isOn: Binding(get: { workspace.playback.isLooping }, set: { workspace.playback.isLooping = $0 }))
        }
        CommandGroup(before: .toolbar) {
            Button("Toggle Before / After") { workspace.toggleBefore() }.keyboardShortcut("b", modifiers: [])
                .disabled(workspace.media == nil)
            Button("Split Compare") { workspace.compare = workspace.compare == .split ? .off : .split }
                .keyboardShortcut("b", modifiers: [.shift])
                .disabled(workspace.media == nil)
            Divider()
        }
    }
}
