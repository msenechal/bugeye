/// The app's settings as one value. Loaded from and saved to a `SettingsStore` key by key; a missing or
/// invalid value falls back to its default, so a bad stored value never blocks launch.
public struct AppSettings: Hashable, Sendable {
    public enum Key {
        public static let saveFolder = "saveFolder"
        public static let aiModel = "ai.model"
    }

    /// Shown and stored with a leading `~` when it's inside the home folder.
    public static let defaultSaveFolder = "~/Pictures/Bugeye/"
    public static let defaultAIModel = "claude-opus-5-5"

    public var saveFolder: String
    public var aiModel: String

    public init(saveFolder: String = AppSettings.defaultSaveFolder, aiModel: String = AppSettings.defaultAIModel) {
        self.saveFolder = saveFolder
        self.aiModel = aiModel
    }

    public static func load(from store: any SettingsStore) -> AppSettings {
        var settings = AppSettings()
        if case .string(let folder)? = store.value(forKey: Key.saveFolder), isValidFolder(folder) {
            settings.saveFolder = folder
        }
        if case .string(let model)? = store.value(forKey: Key.aiModel), isValidModel(model) {
            settings.aiModel = model
        }
        return settings
    }

    /// Writes only the keys whose value changed from `old`, so a save never freezes other settings at
    /// their current defaults (`design/01` §2.10).
    public func save(to store: any SettingsStore, comparedTo old: AppSettings) {
        if saveFolder != old.saveFolder { store.setValue(.string(saveFolder), forKey: Key.saveFolder) }
        if aiModel != old.aiModel { store.setValue(.string(aiModel), forKey: Key.aiModel) }
    }

    static func isValidFolder(_ folder: String) -> Bool {
        folder.hasPrefix("/") || folder.hasPrefix("~/")
    }

    /// A model ID: `claude-` then lowercase letters, digits and hyphens.
    static func isValidModel(_ model: String) -> Bool {
        guard model.hasPrefix("claude-"), model.count > "claude-".count else { return false }
        return model.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}

/// Folder paths as the user sees them (`~/…`) and as the file system needs them (absolute).
public enum FolderPath {
    /// `~/x` → `<home>/x`; anything else unchanged.
    public static func expandingTilde(_ path: String, home: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return trimmingTrailingSlash(home) + path.dropFirst()
    }

    /// `<home>/x` → `~/x`; anything else unchanged. A folder keeps its trailing slash.
    public static func abbreviatingHome(_ path: String, home: String) -> String {
        let home = trimmingTrailingSlash(home)
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func trimmingTrailingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
