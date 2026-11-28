import BugeyeCore
import Foundation

/// The Capture pane's settings, read fresh before each capture (Capture §5.7, C6).
public struct CaptureSettings: Hashable, Sendable {
    public enum Key {
        public static let copyToClipboard = OutputSettings.Key.copyToClipboard
        public static let saveToFolder = OutputSettings.Key.saveToFolder
        public static let downscaleToPoints = "capture.downscaleToPoints"
        /// `StoredArea` as JSON (C9).
        public static let lastArea = "capture.lastArea"
    }

    public var copyToClipboard: Bool
    public var saveToFolder: Bool
    public var downscaleToPoints: Bool

    public init(copyToClipboard: Bool = true, saveToFolder: Bool = true, downscaleToPoints: Bool = false) {
        self.copyToClipboard = copyToClipboard
        self.saveToFolder = saveToFolder
        self.downscaleToPoints = downscaleToPoints
    }

    /// Missing or non-Bool values fall back to the defaults.
    public static func load(from store: any SettingsStore) -> CaptureSettings {
        let output = OutputSettings.load(from: store)
        var settings = CaptureSettings(copyToClipboard: output.copyToClipboard, saveToFolder: output.saveToFolder)
        if case .bool(let downscale)? = store.value(forKey: Key.downscaleToPoints) {
            settings.downscaleToPoints = downscale
        }
        return settings
    }
}

/// The last area for Return, persisted across restarts (C9).
public enum LastAreaStore {
    public static func load(from store: any SettingsStore) -> StoredArea? {
        guard case .string(let json)? = store.value(forKey: CaptureSettings.Key.lastArea), !json.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(StoredArea.self, from: Data(json.utf8))
    }

    public static func save(_ area: StoredArea, to store: any SettingsStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(area), let json = String(data: data, encoding: .utf8) else { return }
        store.setValue(.string(json), forKey: CaptureSettings.Key.lastArea)
    }
}
