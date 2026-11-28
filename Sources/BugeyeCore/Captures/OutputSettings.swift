/// The Capture pane's "After capture" toggles that recordings follow too (Recording V12). Capture writes the
/// keys; Recording reads them through this type, never by key (contracts §3).
public struct OutputSettings: Hashable, Sendable {
    public enum Key {
        public static let copyToClipboard = "capture.copyToClipboard"
        public static let saveToFolder = "capture.saveToFolder"
    }

    /// Default true.
    public var copyToClipboard: Bool
    /// Default true.
    public var saveToFolder: Bool

    public init(copyToClipboard: Bool = true, saveToFolder: Bool = true) {
        self.copyToClipboard = copyToClipboard
        self.saveToFolder = saveToFolder
    }

    /// Missing or non-Bool values fall back to the defaults.
    public static func load(from store: any SettingsStore) -> OutputSettings {
        var settings = OutputSettings()
        if case .bool(let value)? = store.value(forKey: Key.copyToClipboard) { settings.copyToClipboard = value }
        if case .bool(let value)? = store.value(forKey: Key.saveToFolder) { settings.saveToFolder = value }
        return settings
    }
}

/// Capture §5.4's notice when the save folder is unusable, also posted by Recording (§5.6).
public enum OutputStrings {
    public static let folderUnavailableTitle = "Couldn't save to folder"

    /// "<path> is unavailable. The capture is kept temporarily; use Save in Quick Access."
    public static func folderUnavailableBody(path: String) -> String {
        "\(path) is unavailable. The capture is kept temporarily; use Save in Quick Access."
    }
}
