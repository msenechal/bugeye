import BugeyeCore

/// One boxed word of a `TextLine` (OCR §4).
public struct TextWord: Hashable, Codable, Sendable {
    /// The slice of the line's text that `range` covers.
    public var text: String
    /// `Character` offsets in the line's text.
    public var range: Range<Int>
    /// In the map's pixel space.
    public var box: Rect2D

    public init(text: String, range: Range<Int>, box: Rect2D) {
        self.text = text
        self.range = range
        self.box = box
    }
}

/// One recognised line, normalised (OCR §4.1).
public struct TextLine: Hashable, Codable, Sendable {
    public var text: String
    public var box: Rect2D
    /// In order, never overlapping. A word the recogniser couldn't box is missing here but stays in `text`.
    public var words: [TextWord]
    /// 0…1.
    public var confidence: Double
    /// The index of its row in reading order (OCR §4.2).
    public var row: Int

    public init(text: String, box: Rect2D, words: [TextWord], confidence: Double, row: Int) {
        self.text = text
        self.box = box
        self.words = words
        self.confidence = confidence
        self.row = row
    }
}

/// The word map: every line of one image, in reading order (OCR §4).
public struct TextMap: Hashable, Codable, Sendable {
    /// The pixel space of every box: the read image, top-left origin.
    public var width: Int
    public var height: Int
    /// Reading order: rows top to bottom, each left to right.
    public var lines: [TextLine]

    public init(width: Int, height: Int, lines: [TextLine]) {
        self.width = width
        self.height = height
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }
}

/// One find result: a run of characters of one line (OCR §4.4).
public struct TextMatch: Hashable, Sendable {
    /// The index of the line in `TextMap.lines`.
    public var line: Int
    /// `Character` offsets in that line's text.
    public var range: Range<Int>
    public var box: Rect2D

    public init(line: Int, range: Range<Int>, box: Rect2D) {
        self.line = line
        self.range = range
        self.box = box
    }
}
