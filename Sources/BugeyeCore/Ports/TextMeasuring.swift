public struct TextLineMetrics: Hashable, Sendable {
    public var width: Double
    public var ascent: Double
    public var descent: Double

    public init(width: Double, ascent: Double, descent: Double) {
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }
}

/// Measures one line of text, no wrapping, in pixels at `font.size` (Core Text on macOS). Called on the main actor:
/// under 1 ms for 64 characters on the user's Mac (K38). Editor (text annotations, step numbers), Recording
/// (keystroke badge).
public protocol TextMeasuring: Sendable {
    func measure(_ line: String, font: FontDescriptor) -> TextLineMetrics
}
