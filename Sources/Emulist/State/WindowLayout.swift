import AppKit
import EmulistCore
import Observation

/// What the window shows around the viewer. Remembered between launches, except the cinema viewer.
@MainActor @Observable
final class WindowLayout {
    var showsLibrary = WindowLayout.saved("showsLibrary", default: true) {
        didSet { UserDefaults.standard.set(showsLibrary, forKey: "showsLibrary") }
    }
    var showsScopes = WindowLayout.saved("showsScopes", default: false) {
        didSet { UserDefaults.standard.set(showsScopes, forKey: "showsScopes") }
    }
    /// The scope above the vectorscope: the waveform or the RGB parade.
    var traceScope = ScopeKind(rawValue: UserDefaults.standard.string(forKey: "traceScope") ?? "") ?? .parade {
        didSet { UserDefaults.standard.set(traceScope.rawValue, forKey: "traceScope") }
    }
    /// Only the image, full screen.
    private(set) var isCinema = false
    /// Whether entering the cinema viewer put the window into full screen (so leaving it should undo that).
    @ObservationIgnored private var cinemaEnteredFullScreen = false
    @ObservationIgnored private var fullScreenObserver: NSObjectProtocol?

    func toggleCinema() { isCinema ? endCinema() : beginCinema() }

    func beginCinema() {
        guard !isCinema, let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        isCinema = true
        cinemaEnteredFullScreen = !window.styleMask.contains(.fullScreen)
        if cinemaEnteredFullScreen { window.toggleFullScreen(nil) }
        // Leaving full screen any other way (the green button, ⌃⌘F) leaves the cinema viewer too.
        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cinemaEnteredFullScreen = false
                self?.endCinema()
            }
        }
    }

    func endCinema() {
        guard isCinema else { return }
        isCinema = false
        fullScreenObserver.map(NotificationCenter.default.removeObserver)
        fullScreenObserver = nil
        if cinemaEnteredFullScreen, let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) {
            window.toggleFullScreen(nil)
        }
        cinemaEnteredFullScreen = false
    }

    private static func saved(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
