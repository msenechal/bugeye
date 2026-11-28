import AppKit
import BugeyeCore
import EditorCore
import Observation
import SwiftUI

/// What the chrome shows, refreshed from the controller after every change (`EditorCanvasDelegate`), and the
/// actions it sends back. Every action commits typed text first (§5.2), in the window controller.
@MainActor @Observable
final class EditorViewModel {
    var tool: EditorTool = .default
    var options = ToolOptions()
    var rows: [EditorOption] = []
    var canUndo = false
    var canRedo = false
    var cropLabel = EditorStrings.cropLabel(nil)
    var hasCrop = false
    var frame: BackgroundFrame?
    var showingFramePopover = false

    @ObservationIgnored var onTool: (EditorTool) -> Void = { _ in }
    @ObservationIgnored var onOptions: (ToolOptions) -> Void = { _ in }
    @ObservationIgnored var onFrameEnabled: (Bool) -> Void = { _ in }
    @ObservationIgnored var onFrameDrag: (Bool) -> Void = { _ in }
    @ObservationIgnored var onFrame: (BackgroundFrame) -> Void = { _ in }
    @ObservationIgnored var onResetCrop: () -> Void = {}
    @ObservationIgnored var onUndo: () -> Void = {}
    @ObservationIgnored var onRedo: () -> Void = {}
    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onSave: () -> Void = {}
    @ObservationIgnored var onFrameButton: () -> Void = {}
    /// The drag handle's view, made by the window controller.
    @ObservationIgnored var dragHandle: () -> NSView = { NSView() }

    func update(from controller: InteractionController) {
        tool = controller.tool
        options = controller.options
        let selectedTool = controller.selection.flatMap { controller.document.state.annotation($0) }?.shape.tool
        rows = EditorOptionsStrip.rows(tool: controller.tool, selectedTool: selectedTool)
        canUndo = controller.canUndo
        canRedo = controller.canRedo
        cropLabel = EditorStrings.cropLabel(controller.displayState.crop)
        hasCrop = controller.document.state.crop != nil
        frame = controller.document.state.frame
    }
}

struct EditorToolbarView: View {
    let model: EditorViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorToolbar.items(slots: EditorSlots()), id: \.self) { item in
                view(for: item)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    @ViewBuilder
    private func view(for item: EditorToolbarItem) -> some View {
        switch item {
        case .tool(let tool):
            Button {
                model.onTool(tool)
            } label: {
                Image(systemName: tool.symbol).frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(
                    model.tool == tool ? SwiftUI.Color.accentColor.opacity(0.25) : SwiftUI.Color.clear)
            )
            .help(tool.tooltip)
        case .divider:
            Divider().frame(height: 22)
        case .frame:
            Button(EditorStrings.frameButton) { model.onFrameButton() }
                .help(EditorStrings.frameTooltip)
                .popover(
                    isPresented: Binding(
                        get: { model.showingFramePopover }, set: { model.showingFramePopover = $0 })
                ) {
                    FramePopoverView(model: model)
                }
        case .spacer:
            Spacer()
        case .undo:
            Button {
                model.onUndo()
            } label: {
                Image(systemName: EditorStrings.undoSymbol)
            }
            .disabled(!model.canUndo).help(EditorStrings.undoTooltip)
        case .redo:
            Button {
                model.onRedo()
            } label: {
                Image(systemName: EditorStrings.redoSymbol)
            }
            .disabled(!model.canRedo).help(EditorStrings.redoTooltip)
        case .copy:
            Button(EditorStrings.copyButton) { model.onCopy() }.help(EditorStrings.copyTooltip)
        case .save:
            Button(EditorStrings.saveButton) { model.onSave() }.help(EditorStrings.saveTooltip)
        case .dragHandle:
            DragHandleHost(make: model.dragHandle).frame(width: 26, height: 26).help(EditorStrings.dragTooltip)
        case .copyText, .copyForAI, .sourceChip:
            EmptyView()  // reserved (E8)
        }
    }
}

/// Hosts the AppKit drag handle (dragging needs an `NSView` and its mouse events).
struct DragHandleHost: NSViewRepresentable {
    let make: () -> NSView
    func makeNSView(context: Context) -> NSView { make() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct EditorOptionsStripView: View {
    let model: EditorViewModel

    private func set(_ change: (inout ToolOptions) -> Void) {
        var options = model.options
        change(&options)
        model.onOptions(options)
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(model.rows, id: \.self) { row in
                view(for: row)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    @ViewBuilder
    private func view(for row: EditorOption) -> some View {
        switch row {
        case .color:
            HStack(spacing: 4) {
                ForEach(EditorPalette.swatches, id: \.name) { swatch in
                    Button {
                        set { $0.color = swatch.color }
                    } label: {
                        Circle().fill(Self.color(swatch.color)).frame(width: 16, height: 16)
                            .overlay(
                                Circle().strokeBorder(
                                    model.options.color == swatch.color ? SwiftUI.Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain).help(swatch.name)
                }
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Self.color(model.options.color) },
                        set: { new in set { $0.color = Self.rgba(new) } }), supportsOpacity: false
                )
                .labelsHidden().help(EditorStrings.customColourTooltip)
            }
        case .width:
            Picker(
                "", selection: Binding(get: { model.options.width }, set: { new in set { $0.width = new } })
            ) {
                ForEach(Array(StrokeWidth.allCases.enumerated()), id: \.element) { index, width in
                    Text(EditorStrings.widthNames[index]).tag(width)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        case .filled:
            Toggle(
                EditorStrings.filled,
                isOn: Binding(get: { model.options.filled }, set: { new in set { $0.filled = new } }))
        case .shadow:
            Toggle(
                EditorStrings.shadow,
                isOn: Binding(get: { model.options.shadow }, set: { new in set { $0.shadow = new } }))
        case .size:
            HStack(spacing: 4) {
                Text(EditorStrings.size)
                Picker(
                    "", selection: Binding(get: { model.options.fontSize }, set: { new in set { $0.fontSize = new } })
                ) {
                    ForEach(Array(ToolOptions.fontSizes.enumerated()), id: \.element) { index, size in
                        Text(EditorStrings.fontSizeNames[index]).tag(size)
                    }
                }
                .labelsHidden().fixedSize()
            }
        case .blur:
            Picker(
                "", selection: Binding(get: { model.options.blurMode }, set: { new in set { $0.blurMode = new } })
            ) {
                ForEach(Array(BlurMode.allCases.enumerated()), id: \.element) { index, mode in
                    Text(EditorStrings.blurModeNames[index]).tag(mode)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker(
                "",
                selection: Binding(get: { model.options.blurStrength }, set: { new in set { $0.blurStrength = new } })
            ) {
                ForEach(1...3, id: \.self) { strength in
                    Text(EditorStrings.strengthNames[strength - 1]).tag(strength)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        case .crop:
            Text(model.cropLabel).monospacedDigit()
            Button(EditorStrings.resetCrop) { model.onResetCrop() }.disabled(!model.hasCrop)
        case .selectHint:
            Text(EditorStrings.selectHint).foregroundStyle(.secondary)
        }
    }

    static func color(_ c: RGBAColor) -> SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    static func rgba(_ color: SwiftUI.Color) -> RGBAColor {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return RGBAColor(
            red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent), alpha: 1)
    }
}

/// The Frame popover (§5.6). A slider drag is one step; keyboard steps on a slider form a run (U5).
struct FramePopoverView: View {
    let model: EditorViewModel

    private func set(_ change: (inout BackgroundFrame) -> Void) {
        guard var frame = model.frame else { return }
        change(&frame)
        model.onFrame(frame)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                EditorStrings.frameToggle,
                isOn: Binding(get: { model.frame != nil }, set: { model.onFrameEnabled($0) }))
            if let frame = model.frame {
                HStack(spacing: 6) {
                    ForEach(EditorPalette.fills, id: \.name) { fill in
                        Button {
                            set { $0.fill = fill.fill }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Self.fillStyle(fill.fill))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4).strokeBorder(
                                        frame.fill == fill.fill ? SwiftUI.Color.accentColor : .secondary.opacity(0.4),
                                        lineWidth: frame.fill == fill.fill ? 2 : 1))
                        }
                        .buttonStyle(.plain).help(fill.name)
                    }
                }
                slider(
                    EditorStrings.padding, value: frame.padding, range: BackgroundFrame.paddingRange,
                    apply: { value in set { $0.padding = value } })
                slider(
                    EditorStrings.cornerRadius, value: frame.cornerRadius, range: BackgroundFrame.cornerRadiusRange,
                    apply: { value in set { $0.cornerRadius = value } })
                Toggle(
                    EditorStrings.frameShadow,
                    isOn: Binding(get: { frame.shadow }, set: { new in set { $0.shadow = new } }))
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func slider(
        _ title: String, value: Double, range: ClosedRange<Double>, apply: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(title).frame(width: 96, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { apply($0.rounded()) }), in: range, step: 1,
                onEditingChanged: { model.onFrameDrag($0) })
            Text(EditorStrings.points(Int(value))).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    static func fillStyle(_ fill: FrameFill) -> AnyShapeStyle {
        let colors = EditorPalette.fillColors(fill).map(EditorOptionsStripView.color)
        if colors.count == 1 { return AnyShapeStyle(colors[0]) }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
