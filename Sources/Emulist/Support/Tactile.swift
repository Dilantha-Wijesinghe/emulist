import AppKit
import EmulistCore
import SwiftUI

/// Force Touch trackpad feedback: controls click when they land on their default, like a detent.
@MainActor
enum Haptics {
    static func detent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func toggle() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// The three phases of one continuous adjustment, so a whole drag (or scroll) is a single undo step.
struct EditActions {
    let begin: () -> Void
    let change: (Double) -> Void
    let end: () -> Void

    /// A one-step change (reset, typed value).
    func set(_ value: Double) {
        begin()
        change(value)
        end()
    }
}

/// One drag or scroll of a single-value control: relative travel from where it started, a sticky
/// detent at the default (with a haptic click), and one undo step. A reference type, so rapid events
/// never read a value SwiftUI hasn't re-rendered yet.
@MainActor
final class AdjustSession {
    private var dial: DragMath.Dial?
    /// The drag's total translation at the previous event (drags report totals; scrolls report steps).
    private var lastTranslation = 0.0

    var isActive: Bool { dial != nil }

    func begin(at value: Double, range: ClosedRange<Double>, pointsPerRange: Double, detent: Double,
               detentWidth: Double = 0.015, _ actions: EditActions) {
        dial = DragMath.Dial(value: value, range: range, pointsPerRange: pointsPerRange, detent: detent,
                             detentWidth: detentWidth)
        lastTranslation = 0
        actions.begin()
    }

    /// A drag's cumulative translation since it began.
    func drag(to translation: Double, fine: Bool, _ actions: EditActions) {
        move(translation - lastTranslation, fine: fine, actions)
        lastTranslation = translation
    }

    /// An incremental movement, e.g. one scroll event.
    func move(_ points: Double, fine: Bool, _ actions: EditActions) {
        guard var dial else { return }
        let last = dial.value
        dial.move(points, fine: fine)
        self.dial = dial
        if let detent = dial.detent, DragMath.reached(detent, from: last, to: dial.value) { Haptics.detent() }
        if dial.value != last { actions.change(dial.value) }
    }

    func end(_ actions: EditActions) {
        guard isActive else { return }
        dial = nil
        actions.end()
    }
}

/// Trackpad / mouse-wheel adjustment of the hovered control. Scrolls that pause for a moment end the
/// edit, so each burst of scrolling is one undo step. Momentum is ignored for precision.
private struct ScrollAdjust: ViewModifier {
    let isEnabled: Bool
    /// Receives the scroll travel in points (up / right positive) and whether ⌥ is held.
    let onScroll: (Double, Bool) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    @State private var monitor: Monitor = Monitor()

    func body(content: Content) -> some View {
        monitor.handlers = (onScroll, onBegin, onEnd)
        return content
            .onHover { hovering in
                if hovering, isEnabled { monitor.start() } else { monitor.stop() }
            }
            .onDisappear { monitor.stop() }
    }

    @MainActor
    final class Monitor {
        var handlers: ((Double, Bool) -> Void, () -> Void, () -> Void)?
        private var token: Any?
        private var isActive = false
        private var endTask: Task<Void, Never>?

        func start() {
            guard token == nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.momentumPhase.isEmpty else { return nil }
                MainActor.assumeIsolated { self.handle(event) }
                return nil
            }
        }

        func stop() {
            if let token { NSEvent.removeMonitor(token) }
            token = nil
            finish()
        }

        private func handle(_ event: NSEvent) {
            guard let handlers else { return }
            let scale = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
            let travel = (event.scrollingDeltaY - event.scrollingDeltaX) * scale
            guard travel != 0 else { return }
            if !isActive {
                isActive = true
                handlers.1()
            }
            handlers.0(travel, event.modifierFlags.contains(.option))
            endTask?.cancel()
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }

        private func finish() {
            endTask?.cancel()
            guard isActive else { return }
            isActive = false
            handlers?.2()
        }
    }
}

extension View {
    func scrollAdjust(isEnabled: Bool = true, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void,
                      onScroll: @escaping (Double, Bool) -> Void) -> some View {
        modifier(ScrollAdjust(isEnabled: isEnabled, onScroll: onScroll, onBegin: onBegin, onEnd: onEnd))
    }
}

/// A number that turns into a text field on click, for typing an exact value.
struct ValueField: View {
    let text: String
    var color: Color = Theme.secondaryText
    var isEnabled = true
    /// Receives the typed text; the caller ignores entries it can't parse.
    let onCommit: (String) -> Void

    // A plain string, never an optional binding: the field may read it once more after editing ends.
    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand { isEditing = false }
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                    .padding(.horizontal, 2)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 3))
                    .onAppear {
                        // Focus once the field is in the window, then select the old value so typing replaces it.
                        DispatchQueue.main.async {
                            isFocused = true
                            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                        }
                    }
                    .focusedValue(\.isTypingValue, true)
            } else {
                Text(text)
                    .foregroundStyle(color)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEnabled else { return }
                        draft = text
                        isEditing = true
                    }
                    .help("Click to type a value")
            }
        }
        .font(Theme.monoDigits)
        .lineLimit(1)
    }

    /// Return and losing focus both commit; Escape has already ended editing, so it cancels.
    private func commit() {
        guard isEditing else { return }
        isEditing = false
        onCommit(draft)
    }
}

extension String {
    /// Parses a typed number, tolerating units and signs the formatter adds ("+0.50", "35%").
    var typedNumber: Double? {
        Double(trimmingCharacters(in: CharacterSet(charactersIn: "+% ").union(.whitespaces)))
    }
}

extension FocusedValues {
    /// True while a value is being typed, so bare-key shortcuts (Space, arrows, B) leave the keys to the field.
    var isTypingValue: Bool? {
        get { self[TypingValueKey.self] }
        set { self[TypingValueKey.self] = newValue }
    }

    private struct TypingValueKey: FocusedValueKey { typealias Value = Bool }
}

/// Clicking anywhere that isn't a text field ends typing, as in a grading app: knobs, wheels and the
/// viewer don't take keyboard focus themselves, so without this a value field would stay open.
@MainActor
enum ClickAwayEndsEditing {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if let window = event.window, window.firstResponder is NSText,
               !(window.contentView?.hitTest(event.locationInWindow).map(isTextInput) ?? false) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private static func isTextInput(_ view: NSView) -> Bool {
        sequence(first: view, next: \.superview).contains { $0 is NSTextField || $0 is NSText }
    }
}
