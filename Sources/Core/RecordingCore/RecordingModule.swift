import BugeyeFeatures

/// Recording's registrations (spec §3.1): Record Screen in the menu's record group (order 10 stays free for
/// Record Guide), ⇧⌘5, and the Recording pane. Added to `RecordingWiring.modules` by the wiring PR only.
public struct RecordingModule: FeatureModule {
    public static let toggleHotkey = HotkeySpec(
        id: "recording.toggle", title: RecordingStrings.recordScreen, defaultKey: KeyCombo("5", [.shift, .command]),
        settingKey: RecordingSettings.Key.hotkeyToggle)
    public static let recordMenuItem = "recording.record"

    public init() {}

    public var id: String { "recording" }

    public func menuItems() -> [MenuItemSpec] {
        [
            MenuItemSpec(
                id: Self.recordMenuItem, title: RecordingStrings.recordScreen, slot: MenuSlot(.record, order: 0),
                hotkeyID: Self.toggleHotkey.id)
        ]
    }

    public func hotkeys() -> [HotkeySpec] { [Self.toggleHotkey] }

    public func settingsSection() -> SettingsSectionSpec? {
        SettingsSectionSpec(id: id, title: RecordingStrings.paneTitle, order: 30)
    }
}
