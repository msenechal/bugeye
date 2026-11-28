// Recording-owned from Wave 1 (contracts §4.1.9): moved here unchanged; Recording reshapes it (V3).

/// One element read through Accessibility.
public struct AXElementInfo: Hashable, Sendable {
    public var role: String
    public var title: String?
    /// Static text only. Always nil for text-entry and secure roles: typed text is never read (`design/11` §6).
    /// Not Codable on purpose: decoding would bypass the rule the initializer enforces.
    public var text: String?
    /// In global points.
    public var frame: Rect2D
    public var isTextEntry: Bool

    public init(role: String, title: String?, text: String?, frame: Rect2D, isTextEntry: Bool) {
        self.role = role
        self.title = title
        self.text = isTextEntry ? nil : text
        self.frame = frame
        self.isTextEntry = isTextEntry
    }
}

/// The Accessibility tree (AXUIElement on macOS). Every call may be slow: never call it on the main actor.
public protocol AXReader: Sendable {
    func element(at point: Point2D) async throws -> AXElementInfo?
    func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo]
}
