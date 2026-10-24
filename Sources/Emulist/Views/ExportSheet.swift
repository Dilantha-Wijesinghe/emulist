import EmulistCore
import SwiftUI
import UniformTypeIdentifiers

/// One clip to export, to a destination chosen before the first export starts.
struct ExportItem {
    let media: MediaInfo
    let settings: GradeSettings
    let destination: URL
}

/// Runs a list of exports one at a time (the GPU is the bottleneck) and publishes their progress.
/// A single export is a list of one.
@MainActor @Observable
final class ExportJob {
    enum Outcome: Equatable {
        case exported
        case stopped
        case failed(String)
    }

    let items: [ExportItem]
    /// Clips left out because their footage is missing.
    let skipped: [String]
    private(set) var current = 0
    /// Progress of the current item.
    private(set) var fraction = 0.0
    /// One per item; nil while it is waiting or running, and for items never started after a stop.
    private(set) var outcomes: [Outcome?]
    private(set) var isFinished = false
    @ObservationIgnored private var exporter: VideoExporter?
    @ObservationIgnored private var isStopped = false

    /// Starts exporting at once.
    init(items: [ExportItem], skipped: [String] = [], export: ExportSettings) {
        self.items = items
        self.skipped = skipped
        outcomes = Array(repeating: nil, count: items.count)
        Task { await run(export) }
    }

    /// Stops the current export and the ones after it.
    func cancel() {
        isStopped = true
        exporter?.cancel()
    }

    /// Progress across every item, weighted by frame count.
    var overallFraction: Double {
        let frames = items.map { Double($0.media.frameCount) }
        let done = frames.prefix(current).reduce(0, +) + (frames.indices.contains(current) ? frames[current] * fraction : 0)
        return isFinished ? 1 : done / max(1, frames.reduce(0, +))
    }

    var exported: [URL] { zip(items, outcomes).compactMap { $1 == .exported ? $0.destination : nil } }

    private func run(_ export: ExportSettings) async {
        for index in items.indices {
            guard !isStopped else { break }
            current = index
            fraction = 0
            outcomes[index] = await run(items[index], index: index, export: export)
        }
        exporter = nil
        isFinished = true
    }

    private func run(_ item: ExportItem, index: Int, export: ExportSettings) async -> Outcome {
        do {
            let exporter = try VideoExporter(info: item.media, settings: item.settings, export: export, destination: item.destination)
            self.exporter = exporter
            try await exporter.run { progress in
                Task { @MainActor [weak self] in self?.update(progress, item: index) }
            }
            return .exported
        } catch ExportError.cancelled {
            return .stopped
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Progress hops to the main actor, so a late update from the previous item is dropped.
    private func update(_ progress: Double, item: Int) {
        if item == current, !isFinished { fraction = progress }
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
                if job.isFinished { summary(job) } else { progress(job) }
            } else {
                options
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(job?.isFinished == false)
    }

    private var exportsAll: Bool { workspace.clips.count > 1 && workspace.exportScope == .allClips }

    /// The clips the export would include, before missing footage is left out.
    private var scopeClips: [Clip] {
        exportsAll ? workspace.clips : workspace.selectedClip.map { [$0] } ?? []
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 18) {
            if workspace.clips.count > 1 {
                Picker("Export", selection: $workspace.exportScope) {
                    Text("This Clip").tag(ExportScope.selectedClip)
                    Text("All \(workspace.clips.count) Clips").tag(ExportScope.allClips)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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
                .disabled(!scopeClips.contains { $0.media?.hasAudio == true })
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export…") { if exportsAll { chooseFolder() } else { chooseDestination() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!scopeClips.contains { $0.media != nil })
            }
        }
    }

    private var note: String {
        let quality = "Every frame is rendered at full quality with the same engine as the viewer."
        guard exportsAll else { return "Output: \(workspace.settings.output.name), \(workspace.settings.stock.name). \(quality)" }
        let missing = workspace.clips.filter { $0.media == nil }.map(\.name)
        let skipped = missing.isEmpty ? "" : " Footage missing, so skipped: \(missing.joined(separator: ", "))."
        return "Each clip is exported with its own grade, one after another, as “clip – look” in a folder you choose. Existing files are never replaced. \(quality)\(skipped)"
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

    private func progress(_ job: ExportJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if job.items.count > 1 {
                Text("Clip \(job.current + 1) of \(job.items.count): \(job.items[job.current].destination.lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.secondaryText)
            }
            ProgressView(value: job.fraction).tint(Theme.accent)
            if job.items.count > 1 {
                ProgressView(value: job.overallFraction).tint(Theme.secondaryText)
            }
            HStack {
                Text(job.items.count > 1 ? "Rendering… \(percent(job.fraction)) · all clips \(percent(job.overallFraction))"
                                         : "Rendering… \(percent(job.fraction))")
                    .font(Theme.monoDigits).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Stop") { job.cancel() }.keyboardShortcut(.cancelAction)
            }
        }
    }

    private func percent(_ fraction: Double) -> String { "\(Int(fraction * 100))%" }

    private func summary(_ job: ExportJob) -> some View {
        let exported = job.exported
        let total = job.items.count + job.skipped.count
        return VStack(alignment: .leading, spacing: 12) {
            Label(headline(job, exported: exported.count, total: total),
                  systemImage: exported.count == total ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.primaryText)
            if total > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(job.items.indices, id: \.self) { index in
                        row(job.items[index].destination.lastPathComponent, outcome: job.outcomes[index])
                    }
                    ForEach(job.skipped.indices, id: \.self) { index in
                        summaryRow(job.skipped[index], detail: "Footage missing, skipped", systemImage: "questionmark.folder")
                    }
                }
            }
            HStack {
                Spacer()
                if exported.isEmpty {
                    Button("Back") { self.job = nil }
                } else {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(exported) }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func headline(_ job: ExportJob, exported: Int, total: Int) -> String {
        if total == 1, let outcome = job.outcomes.first {
            switch outcome {
            case .exported: return "Exported \(job.items[0].destination.lastPathComponent)"
            case .stopped: return "Export stopped"
            case .failed(let message): return message
            case nil: break
            }
        }
        return exported == total ? "Exported all \(total) clips" : "Exported \(exported) of \(total) clips"
    }

    @ViewBuilder
    private func row(_ name: String, outcome: ExportJob.Outcome?) -> some View {
        switch outcome {
        case .exported: summaryRow(name, detail: nil, systemImage: "checkmark.circle")
        case .stopped: summaryRow(name, detail: "Stopped", systemImage: "stop.circle")
        case .failed(let message): summaryRow(name, detail: message, systemImage: "exclamationmark.triangle")
        case nil: summaryRow(name, detail: "Not started", systemImage: "circle.dashed")
        }
    }

    private func summaryRow(_ name: String, detail: String?, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1).truncationMode(.middle)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondaryText) }
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.secondaryText)
        }
        .font(.system(size: 12))
    }

    private func chooseDestination() {
        guard let clip = workspace.selectedClip, let media = workspace.media else { return }
        let codec = workspace.exportSettings.codec
        let panel = NSSavePanel()
        panel.allowedContentTypes = [codec.fileType == .mov ? .quickTimeMovie : .mpeg4Movie]
        panel.nameFieldStringValue = "\(ExportNaming.baseName(clip: clip.name, look: workspace.settings.stock.name)).\(codec.fileExtension)"
        panel.directoryURL = media.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL != media.url.standardizedFileURL else {
            workspace.alert = AppAlert(title: "Choose a different name", message: "Exporting over the original footage isn’t allowed.")
            return
        }
        job = ExportJob(items: [ExportItem(media: media, settings: workspace.settings, destination: url)], export: workspace.exportSettings)
    }

    /// Every clip with footage goes into one folder, named "<clip> – <look>" and never over an existing file.
    private func chooseFolder() {
        let clips = workspace.clipsForExport()
        let ready = clips.filter { $0.media != nil }
        guard let folder = ready.first?.media?.url.deletingLastPathComponent() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the \(ready.count) exported clips"
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let destinations = try ExportNaming.destinations(
                for: ready.map { ExportNaming.baseName(clip: $0.name, look: $0.settings.stock.name) },
                in: folder, fileExtension: workspace.exportSettings.codec.fileExtension)
            let items = zip(ready, destinations).compactMap { clip, destination in
                clip.media.map { ExportItem(media: $0, settings: clip.settings, destination: destination) }
            }
            job = ExportJob(items: items, skipped: clips.filter { $0.media == nil }.map(\.name), export: workspace.exportSettings)
        } catch {
            workspace.alert = AppAlert(title: "Couldn’t export to “\(folder.lastPathComponent)”", message: error.localizedDescription)
        }
    }
}
