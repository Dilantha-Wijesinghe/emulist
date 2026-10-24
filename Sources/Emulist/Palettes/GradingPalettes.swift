import EmulistCore
import SwiftUI

/// The bottom of the color page: primaries on the left, the film rack on the right.
struct GradingPanel: View {
    @Bindable var workspace: Workspace
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        // Fills the window when it fits; scrolls sideways in narrow windows. Inside the scroll view the
        // panel is laid out only when it changes (ViewThatFits re-measured it on every timecode tick).
        ScrollView(.horizontal) {
            FillOrOverflow(width: viewportWidth, contentKey: workspace.settings.stockID) { palettes }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .background(Theme.panel)
    }

    private var palettes: some View {
        HStack(alignment: .top, spacing: 10) {
            PrimariesPalette(workspace: workspace).fixedSize(horizontal: true, vertical: false)
            FilmRack(workspace: workspace)
        }
        .padding(10)
    }
}

/// Offers its content the larger of `width` and the content's natural width: stretched to fill a wide
/// container, at natural size (overflowing, to scroll) in a narrow one.
///
/// Measuring the natural width lays out the whole panel, so it is cached and only re-measured when
/// `width` or `contentKey` (whatever changes the content's natural width) changes, not on every knob tick.
private struct FillOrOverflow: Layout {
    let width: CGFloat
    let contentKey: String

    struct Cache {
        var naturalWidth: CGFloat?
        var key = ""
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        let key = "\(width)|\(contentKey)|\(subviews.count)"
        if cache.key != key { cache = Cache(key: key) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(childProposal(proposal, child, &cache))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, proposal: childProposal(proposal, child, &cache))
    }

    private func childProposal(_ proposal: ProposedViewSize, _ child: LayoutSubview, _ cache: inout Cache) -> ProposedViewSize {
        let natural = cache.naturalWidth ?? child.sizeThatFits(.unspecified).width
        cache.naturalWidth = natural
        return ProposedViewSize(width: max(width, natural), height: proposal.height)
    }
}

/// A knob bound to one grade parameter through the workspace (one undo step per gesture).
/// `defaults` are the settings controls reset to, worked out once per palette rather than per knob.
struct ParameterKnob: View {
    let spec: ParameterSpec
    let defaults: GradeSettings
    @Bindable var workspace: Workspace

    var body: some View {
        RotaryKnob(
            spec: spec, value: workspace.settings[keyPath: spec.keyPath], defaultValue: defaults[keyPath: spec.keyPath],
            actions: EditActions(
                begin: { workspace.beginContinuousEdit() },
                change: { value in workspace.continuousEdit { $0[keyPath: spec.keyPath] = value } },
                end: { workspace.endContinuousEdit() }))
        // Only the knob whose value (or default) changed redraws.
        .equatable()
    }
}

// MARK: Primaries

struct PrimariesPalette: View {
    @Bindable var workspace: Workspace

    var body: some View {
        let defaults = workspace.settings.defaults
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRIMARIES · WHEELS").captionStyle()
                Spacer()
                Button("Reset Primaries") { workspace.resetPrimaries() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .help("Reset the wheels and adjustments below them")
            }
            HStack(alignment: .top, spacing: 18) {
                ForEach(ColorWheel.Kind.allCases) { kind in
                    ColorWheelView(
                        kind: kind, wheel: workspace.settings[wheel: kind],
                        begin: { workspace.beginContinuousEdit() },
                        change: { wheel in workspace.continuousEdit { $0[wheel: kind] = wheel } },
                        end: { workspace.endContinuousEdit() })
                    .equatable()
                }
            }
            .padding(.horizontal, 4)
            HStack(alignment: .top, spacing: 2) {
                ForEach(Controls.primaries) { ParameterKnob(spec: $0, defaults: defaults, workspace: workspace) }
                Rectangle().fill(Theme.separator).frame(width: 1, height: 64).padding(.horizontal, 4)
                ForEach(Controls.input) { ParameterKnob(spec: $0, defaults: defaults, workspace: workspace) }
            }
        }
        .padding(12)
        .moduleBackground(cornerRadius: 9)
    }
}

// MARK: Film rack

struct FilmRack: View {
    @Bindable var workspace: Workspace

    var body: some View {
        let defaults = workspace.settings.defaults
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RackModule(title: "LOOK") { LookPlate(stock: workspace.settings.stock) }
                    .frame(minWidth: 210)
                module(Controls.film, defaults)
                module(Controls.printerLights, defaults)
            }
            HStack(alignment: .top, spacing: 10) {
                module(Controls.grain, defaults)
                module(Controls.halation, defaults)
                module(Controls.bloom, defaults)
            }
            ColorPathModule(workspace: workspace)
        }
    }

    private func module(_ spec: ModuleSpec, _ defaults: GradeSettings) -> some View {
        RackModule(title: spec.title, isOn: spec.toggle.map { toggle in
            Binding(get: { workspace.settings[keyPath: toggle] },
                    set: { on in workspace.edit { $0[keyPath: toggle] = on } })
        }) {
            HStack(spacing: 2) {
                ForEach(spec.parameters) { ParameterKnob(spec: $0, defaults: defaults, workspace: workspace) }
            }
        }
    }
}

/// The selected look's name plate.
private struct LookPlate: View {
    let stock: FilmStock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(stock.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Spacer(minLength: 4)
            }
            Text("\(stock.collection.uppercased()) · \(stock.format.uppercased())")
                .font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.accent.opacity(0.85))
                .lineLimit(1)
            Text(stock.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
    }
}

/// Input interpretation, output encoding and preview quality: the signal path in and out.
private struct ColorPathModule: View {
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 18) {
            Text("SIGNAL").captionStyle()
            labeledPicker("Input", selection: Binding(
                get: { workspace.settings.cameraProfileID },
                set: { id in workspace.edit { $0.cameraProfileID = id } })) {
                    ForEach(CameraProfile.all) { Text($0.name).tag($0.id) }
                }
            labeledPicker("Output", selection: Binding(
                get: { workspace.settings.output },
                set: { output in workspace.edit { $0.output = output } })) {
                    ForEach(OutputTransform.allCases) { Text($0.name).tag($0) }
                }
                .help(workspace.settings.output.detail)
            labeledPicker("Preview", selection: $workspace.quality) {
                ForEach(PreviewQuality.allCases) { Text($0.name).tag($0) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .moduleBackground()
    }

    private func labeledPicker<Value: Hashable, Content: View>(
        _ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText).fixedSize()
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
        }
    }
}
