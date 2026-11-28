import BugeyeCore
import Foundation

/// Builds a `TextMap` from one image's recognised lines: normalisation (OCR §4.1) and reading order (§4.2).
public enum TextMapBuilder {
    /// `lines` are in the image's pixels, top-left origin; the image is `width` × `height`.
    public static func build(_ lines: [OCRLine], width: Int, height: Int) -> TextMap {
        let bounds = Rect2D(x: 0, y: 0, width: Double(max(width, 0)), height: Double(max(height, 0)))
        let normalised = lines.compactMap { normalise($0, in: bounds) }
        return TextMap(width: width, height: height, lines: ordered(normalised))
    }

    /// Reading order (OCR §4.2, T7): sort by (minY, minX, input order); group into rows, a line joining the row
    /// when it is on the same line as the row's first line; each row left to right (minX, input order). Sets `row`.
    public static func ordered(_ lines: [TextLine]) -> [TextLine] {
        let sorted = lines.enumerated().sorted { a, b in
            if a.element.box.minY != b.element.box.minY { return a.element.box.minY < b.element.box.minY }
            if a.element.box.minX != b.element.box.minX { return a.element.box.minX < b.element.box.minX }
            return a.offset < b.offset
        }
        var rows: [[(offset: Int, element: TextLine)]] = []
        for entry in sorted {
            if let first = rows.last?.first, sameLine(first.element.box, entry.element.box) {
                rows[rows.count - 1].append(entry)
            } else {
                rows.append([entry])
            }
        }
        var result: [TextLine] = []
        result.reserveCapacity(lines.count)
        for (index, row) in rows.enumerated() {
            let inRow = row.sorted { a, b in
                if a.element.box.minX != b.element.box.minX { return a.element.box.minX < b.element.box.minX }
                return a.offset < b.offset
            }
            for entry in inRow {
                var line = entry.element
                line.row = index
                result.append(line)
            }
        }
        return result
    }

    /// Two boxes are on the same line when their vertical overlap is at least half the smaller height
    /// (`design/05` B3).
    static func sameLine(_ a: Rect2D, _ b: Rect2D) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap >= 0.5 * min(a.height, b.height)
    }

    /// The box clipped to `bounds`, or nil when nothing is left.
    static func clip(_ box: Rect2D, to bounds: Rect2D) -> Rect2D? {
        box.standardized.intersection(bounds)
    }

    /// Steps 1–6 of OCR §4.1. Nil when the line is dropped.
    static func normalise(_ line: OCRLine, in bounds: Rect2D) -> TextLine? {
        let original = Array(line.text.precomposedStringWithCanonicalMapping)
        let lead = original.prefix { $0.isWhitespace }.count
        guard lead < original.count else { return nil }
        let trail = original.reversed().prefix { $0.isWhitespace }.count
        let chars = Array(original[lead..<(original.count - trail)])
        guard let box = clip(line.bounds, to: bounds) else { return nil }

        var words: [TextWord] = []
        for word in line.words {
            let raw = word.range
            guard raw.lowerBound >= 0, raw.upperBound <= original.count else { continue }
            var start = min(max(raw.lowerBound - lead, 0), chars.count)
            var end = min(max(raw.upperBound - lead, 0), chars.count)
            guard start < end else { continue }
            if words.contains(where: { $0.range.overlaps(start..<end) }) { continue }
            while start < end, chars[start].isWhitespace { start += 1 }
            while end > start, chars[end - 1].isWhitespace { end -= 1 }
            guard start < end, let wordBox = clip(word.bounds, to: bounds) else { continue }
            words.append(TextWord(text: String(chars[start..<end]), range: start..<end, box: wordBox))
        }

        words.sort { $0.range.lowerBound < $1.range.lowerBound }
        let confidence = line.confidence.isNaN ? 0 : min(max(line.confidence, 0), 1)
        return TextLine(text: String(chars), box: box, words: words, confidence: confidence, row: 0)
    }
}
