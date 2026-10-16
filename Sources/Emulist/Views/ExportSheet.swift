import EmulistCore
import SwiftUI
import UniformTypeIdentifiers

/// Runs one export off the main thread and publishes its progress.
@MainActor @Observable
final class ExportJob {
    enum State: Equatable {
        case running(Double)
        case finished(URL)
        case failed(String)
    }

    private(set) var state = State.running(0)
    @ObservationIgnored private var exporter: VideoExporter?

    func start(media: MediaInfo, settings: GradeSettings, export: ExportSettings, destination: URL) {
        do {
            let exporter = try VideoExporter(info: media, settings: settings, export: export, destination: destination)
            self.exporter = exporter
            Task { [weak self] in
                do {
                    try await exporter.run { progress in
                        Task { @MainActor in self?.update(progress) }
                    }
                    self?.state = .finished(destination)
                } catch {
                    self?.state = .failed(error.localizedDescription)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() { exporter?.cancel() }

    private func update(_ progress: Double) {
        if case .running = state { state = .running(progress) }
    }
}

struct ExportSheet: View {
    @Bindable var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var job: ExportJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export").font(.system(size: 17, weight: .semibold))
            if let job {
                progress(job)
            } else {
                options
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                ForEach(ExportSettings.Codec.allCases) { codec in
                    codecCard(codec)
                }
            }
            HStack {
                Text("Resolution").foregroundStyle(Theme.secondaryText)
                Spacer()
                Picker("Resolution", selection: $workspace.exportSettings.resolution) {
                    ForEach(ExportSettings.Resolution.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Toggle("Include audio", isOn: $workspace.exportSettings.includeAudio)
                .disabled(workspace.media?.hasAudio != true)
            Text("Output: \(workspace.settings.output.name), \(workspace.settings.stock.name). Every frame is rendered at full quality with the same engine as the viewer.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export…", action: chooseDestination).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func codecCard(_ codec: ExportSettings.Codec) -> some View {
        let selected = workspace.exportSettings.codec == codec
        return Button {
            workspace.exportSettings.codec = codec
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.tertiaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(codec.name).font(.system(size: 13, weight: .medium))
                    Text("\(codec.detail) · .\(codec.fileExtension)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
            .background(selected ? Theme.accent.opacity(0.1) : Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(selected ? Theme.accent.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func progress(_ job: ExportJob) -> some View {
        switch job.state {
        case .running(let fraction):
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: fraction).tint(Theme.accent)
                HStack {
                    Text("Rendering… \(Int(fraction * 100))%").font(Theme.monoDigits).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Stop") { job.cancel() }.keyboardShortcut(.cancelAction)
                }
            }
        case .finished(let url):
            VStack(alignment: .leading, spacing: 12) {
                Label("Exported \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.primaryText)
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.primaryText)
                HStack {
                    Spacer()
                    Button("Back") { self.job = nil }
                    Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func chooseDestination() {
        guard let media = workspace.media else { return }
        let codec = workspace.exportSettings.codec
        let panel = NSSavePanel()
        panel.allowedContentTypes = [codec.fileType == .mov ? .quickTimeMovie : .mpeg4Movie]
        panel.nameFieldStringValue = "\(workspace.title) – \(workspace.settings.stock.name).\(codec.fileExtension)"
        panel.directoryURL = media.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL != media.url.standardizedFileURL else {
            workspace.alert = AppAlert(title: "Choose a different name", message: "Exporting over the original footage isn’t allowed.")
            return
        }
        let job = ExportJob()
        job.start(media: media, settings: workspace.settings, export: workspace.exportSettings, destination: url)
        self.job = job
    }
}
