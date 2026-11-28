/// Every string of the Shortcuts pane and the launch notices, exactly as Capture §5.6 settles them.
public enum ShortcutStrings {
    public static let none = "None"
    public static let typeAShortcut = "Type a shortcut"
    public static let footer = "Click a shortcut, then type the new keys. Delete clears it; Esc keeps the old one."
    public static let restoreDefaults = "Restore Defaults"
    public static let tryAgain = "Try Again"
    public static let keyboardShortcuts = "Keyboard Shortcuts\u{2026}"
    public static let keyboardSettingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    public static func taken(_ key: String) -> String {
        "\(key) is taken by another app, so this action has no shortcut. Quit that app and press Try Again, or choose another shortcut."
    }

    public static func macOSConflict(_ key: String) -> String {
        "macOS also uses \(key) for its own screenshots and gets it first. Turn it off in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots."
    }

    public static func duplicate(_ key: String, title: String) -> String {
        "\(key) is already used by \(title)."
    }

    public static let invalid = "Use a letter or digit with at least one of \u{2318}, \u{2325} or \u{2303}."

    public static let macOSNoticeTitle = "macOS screenshot shortcuts are still on"

    public static func macOSNoticeBody(_ keys: [String]) -> String {
        "Disable \(join(keys)) in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots, so Bugeye receives them."
    }

    public static let takenNoticeTitle = "Some Bugeye shortcuts are taken"

    public static func takenNoticeBody(_ keys: [String]) -> String {
        keys.count == 1
            ? "\(join(keys)) is taken by another app. Choose another in Bugeye Settings \u{2192} Shortcuts."
            : "\(join(keys)) are taken by other apps. Choose others in Bugeye Settings \u{2192} Shortcuts."
    }

    /// `A`, `A and B`, `A, B and C`.
    public static func join(_ keys: [String]) -> String {
        guard keys.count > 1 else { return keys.first ?? "" }
        return keys.dropLast().joined(separator: ", ") + " and " + keys.last!
    }
}
