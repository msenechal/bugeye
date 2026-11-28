/// A modifier key in a shortcut.
public enum KeyModifier: String, Hashable, Sendable, CaseIterable, Comparable {
    case control, option, shift, command

    public static func < (a: KeyModifier, b: KeyModifier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// The symbol macOS shows in menus.
    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}

/// A key and its modifiers. `key` is what `NSMenuItem.keyEquivalent` takes: one lowercase character.
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    public var key: String
    public var modifiers: Set<KeyModifier>

    public init(_ key: String, _ modifiers: Set<KeyModifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Menu-style text, modifiers in macOS order: "⇧⌘4".
    public var description: String {
        modifiers.sorted().map(\.symbol).joined() + key.uppercased()
    }
}

/// Where a module's menu items go: a group of the status menu, and an order within it.
public struct MenuSlot: Hashable, Sendable {
    public enum Group: Int, Hashable, Sendable, Comparable, CaseIterable {
        case capture, record, library

        public static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }
    }

    public var group: Group
    public var order: Int

    public init(_ group: Group, order: Int) {
        self.group = group
        self.order = order
    }
}

public struct MenuItemSpec: Hashable, Sendable {
    /// Unique across all modules, e.g. "capture.area".
    public var id: String
    public var title: String
    /// Shown in the menu only; global hotkeys are registered from `HotkeySpec`.
    public var shownKey: KeyCombo?
    public var slot: MenuSlot

    public init(id: String, title: String, shownKey: KeyCombo? = nil, slot: MenuSlot) {
        self.id = id
        self.title = title
        self.shownKey = shownKey
        self.slot = slot
    }
}

public struct HotkeySpec: Hashable, Sendable {
    public var id: String
    public var defaultKey: KeyCombo
    /// The settings key the user's own binding is stored under.
    public var settingKey: String

    public init(id: String, defaultKey: KeyCombo, settingKey: String) {
        self.id = id
        self.defaultKey = defaultKey
        self.settingKey = settingKey
    }
}

/// A Settings pane. The app shell maps `id` to its view.
public struct SettingsSectionSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var order: Int

    public init(id: String, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

public struct QuickAccessActionSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var order: Int

    public init(id: String, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

/// A feature plugs into the app by describing itself. The app shell turns the specs into menu items,
/// hotkey registrations and Settings panes, so no feature edits a shared file (`design/14` R1).
public protocol FeatureModule: Sendable {
    var id: String { get }  // "capture", "editor", …
    func menuItems() -> [MenuItemSpec]  // where and what
    func hotkeys() -> [HotkeySpec]  // default keys, setting key
    func settingsSection() -> SettingsSectionSpec?
    func quickAccessActions() -> [QuickAccessActionSpec]
}

extension FeatureModule {
    public func menuItems() -> [MenuItemSpec] { [] }
    public func hotkeys() -> [HotkeySpec] { [] }
    public func settingsSection() -> SettingsSectionSpec? { nil }
    public func quickAccessActions() -> [QuickAccessActionSpec] { [] }
}
