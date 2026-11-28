import BugeyeCore

/// Every user-visible string of the editor, copied from the spec (§5, E14). Tested character for character.
public enum EditorStrings {
    // Module (E2, E12)
    public static let editAction = "Edit"
    public static let openLastCapture = "Open Last Capture"

    // Opening (§5.1)
    public static let openFailedTitle = "Couldn't open capture"
    public static func openFailedBody(name: String) -> String { "\(name) is missing or unreadable." }

    // Toolbar (§5.2)
    public static let frameButton = "Frame"
    public static let frameTooltip = "Background frame"
    public static let undoTooltip = "Undo (\u{2318}Z)"
    public static let redoTooltip = "Redo (\u{21E7}\u{2318}Z)"
    public static let copyButton = "Copy"
    public static let copyTooltip = "Copy the edited image (\u{2318}C)"
    public static let saveButton = "Save"
    public static let saveTooltip = "Save (\u{2318}S)"
    public static let dragTooltip = "Drag the edited image into another app"
    public static let undoSymbol = "arrow.uturn.backward"
    public static let redoSymbol = "arrow.uturn.forward"
    public static let dragSymbol = "hand.draw"

    // Options strip (§5.5)
    public static let customColourTooltip = "Custom colour"
    /// Thin, Medium, Thick: `StrokeWidth.allCases` order.
    public static let widthNames = ["Thin", "Medium", "Thick"]
    public static let filled = "Filled"
    public static let shadow = "Shadow"
    public static let size = "Size"
    /// `ToolOptions.fontSizes` order.
    public static let fontSizeNames = ["16 pt", "24 pt", "36 pt", "48 pt"]
    /// `BlurMode.allCases` order.
    public static let blurModeNames = ["Pixelate", "Blur"]
    /// Strength 1, 2, 3.
    public static let strengthNames = ["Light", "Medium", "Strong"]
    public static let resetCrop = "Reset Crop"
    public static let selectHint = "Click an annotation to select it \u{B7} drag to move \u{B7} Delete removes it"

    /// `<W> × <H> px` (U+00D7) of the crop, or `Drag to crop`.
    public static func cropLabel(_ crop: Rect2D?) -> String {
        guard let crop else { return "Drag to crop" }
        return "\(Int(crop.width.rounded())) \u{D7} \(Int(crop.height.rounded())) px"
    }

    // Frame popover (§5.6)
    public static let frameToggle = "Background frame"
    public static let padding = "Padding"
    public static let cornerRadius = "Corner radius"
    public static let frameShadow = "Shadow"
    public static func points(_ value: Int) -> String { "\(value) pt" }

    // Output (§5.8)
    public static let goneTitle = "The original file is gone"
    public static func goneBody(name: String) -> String {
        "\u{201C}\(name)\u{201D} was moved or deleted since it was opened."
    }
    public static let saveAsButton = "Save As\u{2026}"
    public static let cancelButton = "Cancel"
    public static func saveFailedTitle(name: String) -> String { "Couldn't save \u{201C}\(name)\u{201D}" }
    public static let okButton = "OK"
    public static let copyFailedTitle = "Couldn't copy"
    public static let copyFailedBody = "The image couldn't be put on the clipboard."
    /// The save alert's message when the render itself fails (final review C, I5).
    public static let renderFailed = "The image couldn't be rendered."

    // Unsaved changes (§5.9)
    public static func unsavedTitle(name: String) -> String { "Save changes to \u{201C}\(name)\u{201D}?" }
    public static let unsavedBody = "Your annotations will be lost if you don't save them."
    public static let dontSaveButton = "Don't Save"
}

/// The `editor` log lines (§8.4). Text annotation contents are never logged.
public enum EditorLog {
    public static func open(_ name: String) -> String { "open \(name)" }
    public static func openFailed(_ name: String, reason: String) -> String { "open failed \(name): \(reason)" }
    public static func close(_ name: String) -> String { "close \(name)" }
    public static func saved(_ name: String, milliseconds: Int) -> String { "saved \(name) in \(milliseconds) ms" }
    public static func saveFailed(_ name: String, error: String) -> String { "save failed \(name): \(error)" }
    public static func dragFailed(error: String) -> String { "drag file failed: \(error)" }
}
