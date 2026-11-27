import BugeyeCore

/// What the fixture app shows (spec §5.5). Smoke and end-to-end tests drive the fixture, not the user's
/// desktop, and assert against these values.
public enum FixtureContent {
    public static let windowTitle = "Bugeye Fixture"

    /// "Line 1" … "Line 300", in a scrollable list.
    public static let lines = (1...300).map { "Line \($0)" }

    public static let buttons = ["Save", "Open Settings", "Delete"]
    public static let checkboxes = ["Remember me", "Send reports"]
    public static let textFieldPlaceholder = "Type here"
    public static let secretsTitle = "Fake secrets"

    public struct FakeSecret: Hashable, Sendable {
        public let label: String
        public let value: String
    }

    /// Shaped like real secrets so the sensitive sweep finds them, but none works anywhere. Each value is
    /// assembled from parts so secret scanners don't flag this public repository.
    public static let secrets: [FakeSecret] = [
        FakeSecret(label: "AWS access key", value: "AKIA" + "IOSFODNN7" + "EXAMPLE"),
        FakeSecret(label: "GitHub token", value: "gh" + "p_" + "Fixture" + String(repeating: "0", count: 29)),
        FakeSecret(label: "Email", value: "fixture" + "@" + "example.invalid"),
        FakeSecret(label: "Card number", value: ["4242", "4242", "4242", "4242"].joined(separator: " ")),
    ]

    public struct Swatch: Hashable, Sendable {
        public let name: String
        public let color: RGBA8
    }

    /// Exact sRGB values, for pixel checks.
    public static let swatches: [Swatch] = [
        Swatch(name: "Red", color: RGBA8(red: 255, green: 0, blue: 0)),
        Swatch(name: "Green", color: RGBA8(red: 0, green: 255, blue: 0)),
        Swatch(name: "Blue", color: RGBA8(red: 0, green: 0, blue: 255)),
        Swatch(name: "Grey", color: RGBA8(red: 128, green: 128, blue: 128)),
    ]
}
