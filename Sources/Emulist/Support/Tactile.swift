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
    private(set) var isActive = false
    private var start = 0.0
    private var travel = 0.0
    private var last = 0.0

    func begin(at value: Double, _ actions: EditActions) {
        isActive = true
        start = value
        travel = 0
        last = value
        actions.begin()
    }

    /// `absolute` replaces the travel (drags report total translation); otherwise it accumulates (scrolls).
    func move(_ points: Double, absolute: Bool, fine: Bool, range: ClosedRange<Double>, pointsPerRange: Double,
              detent: Double, detentWidth: Double = 0.015, _ actions: EditActions) {
        travel = absolute ? points : travel + points
        let next = DragMath.value(from: start, travel: travel, range: range, pointsPerRange: pointsPerRange,
                                  fine: fine, detent: detent, detentWidth: detentWidth)
        if DragMath.reached(detent, from: last, to: next) { Haptics.detent() }
        last = next
        actions.change(next)
    }

    func end(_ actions: EditActions) {
        guard isActive else { return }
        isActive = false
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

    @State private var draft: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let binding = Binding($draft) {
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand { draft = nil }
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                    .padding(.horizontal, 2)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 3))
                    .onAppear { isFocused = true }
            } else {
                Text(text)
                    .foregroundStyle(color)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEnabled else { return }
                        draft = text
                    }
                    .help("Click to type a value")
            }
        }
        .font(Theme.monoDigits)
        .lineLimit(1)
    }

    private func commit() {
        guard let value = draft else { return }
        draft = nil
        onCommit(value)
    }
}

extension String {
    /// Parses a typed number, tolerating units and signs the formatter adds ("+0.50", "35%").
    var typedNumber: Double? {
        Double(trimmingCharacters(in: CharacterSet(charactersIn: "+% ").union(.whitespaces)))
    }
}
