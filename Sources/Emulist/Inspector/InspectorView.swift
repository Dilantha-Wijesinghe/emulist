import EmulistCore
import SwiftUI

/// Right-hand grading panel, ordered like the light path: input → film → printer lights → texture → light → output.
struct InspectorView: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionView(section: Inspector.input, workspace: workspace) {
                    LabeledPicker(title: "Camera", selection: Binding(
                        get: { workspace.settings.cameraProfileID },
                        set: { id in workspace.edit { $0.cameraProfileID = id } })
                    ) {
                        ForEach(CameraProfile.all) { Text($0.name).tag($0.id) }
                    }
                }
                SectionView(section: Inspector.film, workspace: workspace) {
                    StockHeader(stock: workspace.settings.stock)
                }
                SectionView(section: Inspector.colorHead, workspace: workspace)
                SectionView(section: Inspector.grain, workspace: workspace)
                SectionView(section: Inspector.halation, workspace: workspace)
                SectionView(section: Inspector.bloom, workspace: workspace)
                OutputSection(workspace: workspace)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .frame(width: Theme.inspectorWidth)
        .background(Theme.panel)
    }
}

private struct SectionView<Header: View>: View {
    let section: InspectorSection
    @Bindable var workspace: Workspace
    @ViewBuilder var header: () -> Header
    @State private var isExpanded = true

    init(section: InspectorSection, workspace: Workspace, @ViewBuilder header: @escaping () -> Header = { EmptyView() }) {
        self.section = section
        self.workspace = workspace
        self.header = header
    }

    private var isEnabled: Bool { section.toggle.map { workspace.settings[keyPath: $0] } ?? true }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 10)
                        Image(systemName: section.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(isEnabled ? Theme.accent : Theme.tertiaryText)
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let toggle = section.toggle {
                    Toggle("", isOn: Binding(
                        get: { workspace.settings[keyPath: toggle] },
                        set: { on in workspace.edit { $0[keyPath: toggle] = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if isExpanded {
                VStack(spacing: 8) {
                    header()
                    ForEach(section.parameters) { spec in
                        slider(spec)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private func slider(_ spec: ParameterSpec) -> some View {
        FilmSlider(
            spec: spec,
            value: workspace.settings[keyPath: spec.keyPath],
            defaultValue: workspace.settings.defaultValue(spec.keyPath),
            isEnabled: isEnabled,
            onBegin: { workspace.beginContinuousEdit() },
            onChange: { value in workspace.continuousEdit { $0[keyPath: spec.keyPath] = value } },
            onEnd: { workspace.endContinuousEdit() },
            onReset: {
                workspace.edit { $0[keyPath: spec.keyPath] = $0.defaultValue(spec.keyPath) }
            })
    }
}

private struct StockHeader: View {
    let stock: FilmStock

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(stock.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Spacer()
                Text(stock.format.uppercased()).captionStyle()
            }
            Text(stock.summary)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 4)
    }
}

private struct OutputSection: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "display").font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 16)
                Text("Output").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primaryText)
            }
            .padding(.leading, 18)
            LabeledPicker(title: "Encoding", selection: Binding(
                get: { workspace.settings.output },
                set: { output in workspace.edit { $0.output = output } })
            ) {
                ForEach(OutputTransform.allCases) { Text($0.name).tag($0) }
            }
            LabeledPicker(title: "Preview", selection: $workspace.quality) {
                ForEach(PreviewQuality.allCases) { Text($0.name).tag($0) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct LabeledPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.primaryText.opacity(0.85))
            Spacer()
            Picker(title, selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
        }
    }
}
