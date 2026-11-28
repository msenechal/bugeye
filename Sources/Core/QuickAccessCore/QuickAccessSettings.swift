import BugeyeCore

/// Where the stack sits in the visible frame of the display under the pointer.
public enum QuickAccessPosition: String, Hashable, Sendable, CaseIterable {
    case bottomLeft, bottomRight
}

/// Quick Access's settings (spec §5.4, Q8), read fresh at each show.
public struct QuickAccessSettings: Hashable, Sendable {
    public enum Key {
        public static let autoDismissSeconds = "quickAccess.autoDismissSeconds"
        public static let position = "quickAccess.position"
    }

    public static let defaultAutoDismissSeconds = 5
    /// 0 is Never.
    public static let validAutoDismissSeconds = [0, 5, 10, 30, 60]

    public var autoDismissSeconds: Int
    public var position: QuickAccessPosition

    public init(
        autoDismissSeconds: Int = QuickAccessSettings.defaultAutoDismissSeconds,
        position: QuickAccessPosition = .bottomLeft
    ) {
        self.autoDismissSeconds = autoDismissSeconds
        self.position = position
    }

    /// Seconds until a thumbnail leaves; nil never (Auto-dismiss Never).
    public var duration: Double? {
        autoDismissSeconds == 0 ? nil : Double(autoDismissSeconds)
    }

    /// Missing, mistyped or invalid values fall back to the defaults.
    public static func load(from store: any SettingsStore) -> QuickAccessSettings {
        var settings = QuickAccessSettings()
        if case .int(let seconds)? = store.value(forKey: Key.autoDismissSeconds),
            validAutoDismissSeconds.contains(seconds)
        {
            settings.autoDismissSeconds = seconds
        }
        if case .string(let raw)? = store.value(forKey: Key.position), let position = QuickAccessPosition(rawValue: raw)
        {
            settings.position = position
        }
        return settings
    }

    public static func store(autoDismissSeconds: Int, in store: any SettingsStore) {
        store.setValue(.int(autoDismissSeconds), forKey: Key.autoDismissSeconds)
    }

    public static func store(position: QuickAccessPosition, in store: any SettingsStore) {
        store.setValue(.string(position.rawValue), forKey: Key.position)
    }

    /// The `Auto-dismiss` picker's options, in order.
    public static let autoDismissOptions: [(seconds: Int, title: String)] = validAutoDismissSeconds.map {
        ($0, $0 == 0 ? QuickAccessStrings.never : QuickAccessStrings.seconds($0))
    }

    /// The `Position` picker's options, in order.
    public static let positionOptions: [(position: QuickAccessPosition, title: String)] = [
        (.bottomLeft, QuickAccessStrings.bottomLeft), (.bottomRight, QuickAccessStrings.bottomRight),
    ]
}
