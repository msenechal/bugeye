import BugeyeCore

/// Later features' places in the editor, empty in Wave 1 (E8, §8.3): each later epic sets its flag and adds rows,
/// not rewrites.
public struct EditorSlots: Hashable, Sendable {
    /// Toolbar buttons before Copy.
    public var copyText: Bool
    public var copyForAI: Bool
    /// After the drag handle.
    public var sourceChip: Bool
    /// Bars between the toolbar and the canvas; each reserves its height while shown.
    public var findBar: Bool
    public var sweepBar: Bool

    public static let barHeight = 34.0

    public init(
        copyText: Bool = false, copyForAI: Bool = false, sourceChip: Bool = false, findBar: Bool = false,
        sweepBar: Bool = false
    ) {
        self.copyText = copyText
        self.copyForAI = copyForAI
        self.sourceChip = sourceChip
        self.findBar = findBar
        self.sweepBar = sweepBar
    }

    public var barsHeight: Double {
        (findBar ? Self.barHeight : 0) + (sweepBar ? Self.barHeight : 0)
    }
}

/// The optional services later features plug in (§8.3); all nil in Wave 1.
public struct EditorServices: Sendable {
    public var textReader: (any TextReader)?
    public var faceFinder: (any FaceFinder)?
    public var rectangleFinder: (any RectangleFinder)?

    public init(
        textReader: (any TextReader)? = nil, faceFinder: (any FaceFinder)? = nil,
        rectangleFinder: (any RectangleFinder)? = nil
    ) {
        self.textReader = textReader
        self.faceFinder = faceFinder
        self.rectangleFinder = rectangleFinder
    }
}

public enum EditorToolbarItem: Hashable, Sendable {
    case tool(EditorTool)
    case divider, frame, spacer, undo, redo, copyText, copyForAI, copy, save, dragHandle, sourceChip
}

/// The toolbar left to right (§5.2).
public enum EditorToolbar {
    public static func items(slots: EditorSlots) -> [EditorToolbarItem] {
        var items: [EditorToolbarItem] = EditorTool.allCases.map { .tool($0) }
        items += [.divider, .frame, .spacer, .undo, .redo]
        if slots.copyText { items.append(.copyText) }
        if slots.copyForAI { items.append(.copyForAI) }
        items += [.copy, .save, .dragHandle]
        if slots.sourceChip { items.append(.sourceChip) }
        return items
    }
}

/// Which option rows the strip shows (§5.5): the tool's, or in Select mode the selected annotation's tool's.
public enum EditorOptionsStrip {
    static let order: [EditorOption] = [.color, .width, .filled, .shadow, .size, .blur, .crop, .selectHint]

    public static func rows(tool: EditorTool, selectedTool: EditorTool?) -> [EditorOption] {
        let shown = tool == .select ? (selectedTool ?? .select) : tool
        let options = shown.options
        return order.filter { options.contains($0) }
    }
}
