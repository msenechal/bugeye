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
            .item(id: quitID, title: ShellStrings.quit, key: KeyCombo("q", [.command])),
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
    public static let aiPrivacyNote =
        "Bugeye only sends data to Claude for features you turn on. Each one is off until you enable it."
}
