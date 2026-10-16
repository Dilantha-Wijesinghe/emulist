import SwiftUI

/// Play/pause, frame stepping, scrubbing, timecode and loop.
struct TransportBar: View {
    @Bindable var workspace: Workspace
    @State private var scrubPosition: Double?

    private var playback: PlaybackController { workspace.playback }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                transportButton("backward.frame.fill", help: "Previous frame (←)") { playback.step(-1) }
                transportButton(playback.isPlaying ? "pause.fill" : "play.fill", help: "Play / Pause (Space)", size: 15) {
                    playback.togglePlayback()
                }
                transportButton("forward.frame.fill", help: "Next frame (→)") { playback.step(1) }
            }

            Text((scrubPosition ?? playback.currentTime).timecode(frameRate: playback.frameRate))
                .font(Theme.monoDigits)
                .foregroundStyle(Theme.primaryText)

            Slider(
                value: Binding(
                    get: { scrubPosition ?? playback.currentTime },
                    set: { value in
                        scrubPosition = value
                        playback.seek(to: value)
                    }),
                in: 0...max(playback.duration, 0.01),
                onEditingChanged: { editing in
                    if editing { playback.pause() } else { scrubPosition = nil }
                })
                .controlSize(.small)
                .tint(Theme.accent)

            Text(playback.duration.timecode(frameRate: playback.frameRate))
                .font(Theme.monoDigits)
                .foregroundStyle(Theme.tertiaryText)

            Toggle(isOn: Binding(get: { playback.isLooping }, set: { playback.isLooping = $0 })) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .foregroundStyle(playback.isLooping ? Theme.accent : Theme.secondaryText)
            .help("Loop playback")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Theme.window)
    }

    private func transportButton(_ symbol: String, help: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryText)
        .help(help)
    }
}
