import BugeyeFeatures

/// The 11 tools in toolbar order (§5.3).
public enum EditorTool: String, Hashable, Codable, Sendable, CaseIterable {
    case select, crop, arrow, rectangle, ellipse, line, text, pen, highlighter, blur, step

    /// The tool an editor opens with (§5.1).
    public static let `default`: EditorTool = .arrow

    /// The letter that selects it, as shown in the tooltip.
    public var key: String {
        switch self {
        case .select: "V"
        case .crop: "C"
        case .arrow: "A"
        case .rectangle: "R"
        case .ellipse: "O"
        case .line: "L"
        case .text: "T"
        case .pen: "P"
        case .highlighter: "H"
        case .blur: "B"
        case .step: "N"
        }
    }

    /// The SF Symbol on its toolbar button.
    public var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .blur: "square.grid.3x3"
        case .step: "1.circle"
        }
    }

    /// The name in its tooltip.
    public var name: String {
        switch self {
        case .select: "Select"
        case .crop: "Crop"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .text: "Text"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .blur: "Blur / Pixelate"
        case .step: "Numbered step"
        }
    }

    /// `<Tool> (<Key>)`, e.g. `Arrow (A)`.
    public var tooltip: String { "\(name) (\(key))" }

    /// The rows of the options strip it shows (§5.5).
    public var options: Set<EditorOption> {
        switch self {
        case .select: [.selectHint]
        case .crop: [.crop]
        case .arrow, .line, .pen, .step: [.color, .width, .shadow]
        case .rectangle, .ellipse: [.color, .width, .filled, .shadow]
        case .text: [.color, .shadow, .size]
        case .highlighter: [.color, .width]
        case .blur: [.blur]
        }
    }

    public var cursor: EditorCursor {
        switch self {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
    }
}

/// A row of the options strip.
public enum EditorOption: String, Hashable, Sendable, CaseIterable {
    case color, width, filled, shadow, size, blur, crop, selectHint
}

public enum EditorCursor: Hashable, Sendable { case arrow, iBeam, crosshair }

/// What a key pressed on the canvas does.
public enum EditorKeyAction: Hashable, Sendable {
    case tool(EditorTool)
    /// Cancels a drag in progress, else deselects (E15).
    case escape
    /// Deletes the selected annotation.
    case delete
}

/// Canvas keys (§5.3): plain letters switch tools (no modifier, ⇧ included, either case); Esc (53), Backspace (51)
/// and forward Delete (117). Everything else returns nil and passes up the responder chain.
public enum EditorShortcuts {
    public static let escapeKeyCode: UInt16 = 53
    public static let backspaceKeyCode: UInt16 = 51
    public static let forwardDeleteKeyCode: UInt16 = 117

    public static func action(keyCode: UInt16, characters: String, modifiers: Set<KeyModifier>) -> EditorKeyAction? {
        guard modifiers.isEmpty else { return nil }
        switch keyCode {
        case escapeKeyCode: return .escape
        case backspaceKeyCode, forwardDeleteKeyCode: return .delete
        default: break
        }
        let letter = characters.uppercased()
        return EditorTool.allCases.first { $0.key == letter }.map { .tool($0) }
    }
}
