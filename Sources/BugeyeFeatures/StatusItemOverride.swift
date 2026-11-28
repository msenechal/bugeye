/// What Recording shows in the status item while it records (contracts §4.2.7). The shell draws it.
public struct StatusItemOverride: Hashable, Sendable {
    public enum Badge: Hashable, Sendable {
        /// Red "● " + elapsed, monospaced digits.
        case recording(elapsed: String)
        /// "❙❙ " + elapsed.
        case paused(elapsed: String)
        /// The "hourglass" SF Symbol.
        case finishing
    }

    public struct Entry: Hashable, Sendable {
        /// nil: a separator.
        public var id: String?
        public var title: String
        public var shownKey: KeyCombo?
        /// Decides alone; the router's `isEnabled` isn't asked for override entries (K35).
        public var isEnabled: Bool

        public init(id: String?, title: String, shownKey: KeyCombo? = nil, isEnabled: Bool = true) {
            self.id = id
            self.title = title
            self.shownKey = shownKey
            self.isEnabled = isEnabled
        }

        public static let separator = Entry(id: nil, title: "")
    }

    public var badge: Badge
    public var accessibilityLabel: String
    /// Replaces the whole status menu while set. Chosen ids go to `ActionRouter.performMenuItem`.
    public var menu: [Entry]

    public init(badge: Badge, accessibilityLabel: String, menu: [Entry]) {
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
        self.menu = menu
    }
}
