// Recording-owned from Wave 1 (contracts §4.1.9); reshaped by Recording (spec §3.1, V3).

/// One element read through Accessibility.
public struct AXElementInfo: Hashable, Sendable {
    public var role: String
    /// "AXSecureTextField", "AXSearchField", …
    public var subrole: String?
    /// Always nil for a secure element.
    public private(set) var title: String?
    /// Static text only. Always nil for text-entry and secure elements: typed text is never read (`design/11` §6).
    /// Not Codable on purpose: decoding would bypass the rule the initializer enforces.
    public private(set) var text: String?
    /// In global points.
    public var frame: Rect2D
    public var isTextEntry: Bool
    /// A secure field (a password): forces `title` and `text` to nil. Also true for the `AXSecureTextField`
    /// subrole, so an adapter that forgets the flag still withholds the field.
    public private(set) var isSecure: Bool

    public static let secureSubrole = "AXSecureTextField"

    public init(
        role: String, subrole: String? = nil, title: String?, text: String?, frame: Rect2D, isTextEntry: Bool,
        isSecure: Bool = false
    ) {
        let isSecure = isSecure || subrole == Self.secureSubrole
        self.role = role
        self.subrole = subrole
        self.title = isSecure ? nil : title
        self.text = isTextEntry || isSecure ? nil : text
        self.frame = frame
        self.isTextEntry = isTextEntry
        self.isSecure = isSecure
    }
}

/// The Accessibility tree (AXUIElement on macOS). Every call may be slow: never call it on the main actor.
public protocol AXReader: Sendable {
    /// `point` and the returned `frame` are Quartz global points (top-left of the primary display).
    /// Returns nil when nothing is there or Accessibility isn't granted. Reads AXRole, AXSubrole,
    /// AXTitle (else AXDescription); never AXValue, AXSelectedText or AXPlaceholderValue for text entry.
    func element(at point: Point2D) async throws -> AXElementInfo?
    func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo]
}
