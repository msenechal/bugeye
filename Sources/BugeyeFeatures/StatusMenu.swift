/// One line of the status-bar menu.
public enum StatusMenuEntry: Hashable, Sendable {
    case item(id: String, title: String, key: KeyCombo?)
    case separator
}

/// The status-bar menu: the shell's fixed items around the modules' items (spec §5.3).
public enum StatusMenu {
    public static let aboutID = "app.about"
    public static let settingsID = "app.settings"
    public static let quitID = "app.quit"

    public static func entries(for registry: FeatureRegistry) -> [StatusMenuEntry] {
        var entries: [StatusMenuEntry] = [.item(id: aboutID, title: ShellStrings.about, key: nil), .separator]
        let items = registry.menuItems
        for group in MenuSlot.Group.allCases {
            let inGroup = items.filter { $0.slot.group == group }
            guard !inGroup.isEmpty else { continue }
            entries += inGroup.map { .item(id: $0.id, title: $0.title, key: $0.shownKey) }
            entries.append(.separator)
        }
        entries += [
            .item(id: settingsID, title: ShellStrings.settings, key: KeyCombo(",", [.command])),
            .separator,
            .item(id: quitID, title: ShellStrings.quit, key: ShellStrings.quitKey),
        ]
        return entries
    }
}

/// The Settings window's panes: the modules' sections, then the AI pane, which the shell owns because
/// the key it holds serves every AI feature.
public enum SettingsLayout {
    public static let aiPane = SettingsSectionSpec(id: "ai", title: ShellStrings.aiPane, order: 1000)

    public static func panes(for registry: FeatureRegistry) -> [SettingsSectionSpec] {
        registry.settingsSections + [aiPane]
    }
}

/// The `general` module: in Wave 0 it only contributes the General pane.
public struct GeneralModule: FeatureModule {
    public init() {}
    public var id: String { "general" }

    public func settingsSection() -> SettingsSectionSpec? {
        SettingsSectionSpec(id: "general", title: ShellStrings.generalPane, order: 0)
    }
}

/// Every user-visible string of the shell, exactly as spec §5.3 settles them.
public enum ShellStrings {
    public static let about = "About Bugeye"
    public static let settings = "Settings…"
    public static let quit = "Quit Bugeye"
    public static let settingsWindowTitle = "Bugeye Settings"
    public static let generalPane = "General"
    public static let aiPane = "AI"
    public static let saveCapturesTo = "Save captures to"
    public static let choose = "Choose…"
    public static let apiKeyField = "Anthropic API key"
    public static let saveKey = "Save"
    public static let testKey = "Test key"
    public static let quitKey = KeyCombo("q", [.command])

    // The main menu (contracts §4.2.5, from the Editor spec).
    public static let appMenu = "Bugeye"
    public static let fileMenu = "File"
    public static let editMenu = "Edit"
    public static let viewMenu = "View"
    public static let menuSave = "Save"
    public static let menuSaveAs = "Save As\u{2026}"
    public static let menuClose = "Close"
    public static let menuUndo = "Undo"
    public static let menuRedo = "Redo"
    public static let menuCut = "Cut"
    public static let menuCopy = "Copy"
    public static let menuPaste = "Paste"
    public static let menuDelete = "Delete"
    public static let menuSelectAll = "Select All"
    public static let menuZoomIn = "Zoom In"
    public static let menuZoomOut = "Zoom Out"
    public static let menuActualSize = "Actual Size"
    public static let menuZoomToFit = "Zoom to Fit"
    public static let saveMenuKey = KeyCombo("s", [.command])
    public static let saveAsMenuKey = KeyCombo("s", [.shift, .command])
    public static let closeMenuKey = KeyCombo("w", [.command])
    public static let undoMenuKey = KeyCombo("z", [.command])
    public static let redoMenuKey = KeyCombo("z", [.shift, .command])
    public static let cutMenuKey = KeyCombo("x", [.command])
    public static let copyMenuKey = KeyCombo("c", [.command])
    public static let pasteMenuKey = KeyCombo("v", [.command])
    public static let selectAllMenuKey = KeyCombo("a", [.command])
    public static let zoomInMenuKey = KeyCombo("=", [.command])
    public static let zoomOutMenuKey = KeyCombo("-", [.command])
    public static let actualSizeMenuKey = KeyCombo("1", [.command])
    public static let zoomToFitMenuKey = KeyCombo("0", [.command])

    public static let aiPrivacyNote =
        "Bugeye only sends data to Claude for features you turn on. Each one is off until you enable it."
}
