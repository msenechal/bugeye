import BugeyeCore
import BugeyeFeatures

/// The Capture feature's menu items, hotkeys and pane (Capture §5.1, §5.7, C26).
public struct CaptureModule: FeatureModule {
    public enum ID {
        public static let module = "capture"
        public static let fullscreen = "capture.fullscreen"
        public static let allDisplays = "capture.allDisplays"
        public static let area = "capture.area"
        public static let window = "capture.window"
        /// The temporary Esc hotkey while an overlay is up (§5.6); never in the Shortcuts pane.
        public static let escape = "capture.escape"
    }

    public init() {}

    public var id: String { ID.module }

    public func menuItems() -> [MenuItemSpec] {
        [
            MenuItemSpec(
                id: ID.area, title: CaptureStrings.captureArea, slot: MenuSlot(.capture, order: 0), hotkeyID: ID.area),
            MenuItemSpec(id: ID.window, title: CaptureStrings.captureWindow, slot: MenuSlot(.capture, order: 30)),
            MenuItemSpec(
                id: ID.fullscreen, title: CaptureStrings.captureFullscreen, slot: MenuSlot(.capture, order: 40),
                hotkeyID: ID.fullscreen),
        ]
    }

    public func hotkeys() -> [HotkeySpec] {
        [
            HotkeySpec(
                id: ID.fullscreen, title: CaptureStrings.captureFullscreen,
                defaultKey: KeyCombo("3", [.shift, .command]),
                settingKey: "capture.hotkey.fullscreen"),
            HotkeySpec(
                id: ID.allDisplays, title: CaptureStrings.captureAllDisplays,
                defaultKey: KeyCombo("3", [.option, .shift, .command]), settingKey: "capture.hotkey.allDisplays"),
            HotkeySpec(
                id: ID.area, title: CaptureStrings.captureArea, defaultKey: KeyCombo("4", [.shift, .command]),
                settingKey: "capture.hotkey.area"),
        ]
    }

    public func settingsSection() -> SettingsSectionSpec? {
        SettingsSectionSpec(id: ID.module, title: CaptureStrings.paneTitle, order: 10)
    }
}
