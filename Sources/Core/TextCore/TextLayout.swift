import BugeyeCore

/// The text map: a word map as plain text with rows and indentation (OCR §4.6).
public enum TextLayout {
    /// Below this many pixels per character there is no indentation: no real text is that narrow, and a bad
    /// recogniser result would otherwise indent by tens of thousands of spaces (ledger ruling, PR #5 review).
    public static let minimumCharacterWidth = 1.0

    /// The widest first line `summary` keeps, in characters.
    public static let summaryLength = 60

    /// One output line per row, the row's line texts joined with one space, indented by
    /// `round((row.minX − leftmost minX) / characterWidth)` spaces (half away from zero), or none when the
    /// character width is under `minimumCharacterWidth`; nil with no rows.
    public static func lines(_ map: TextMap) -> String? {
        var rows: [[TextLine]] = []
        for line in map.lines {
            if let last = rows.last?.last, last.row == line.row {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        guard !rows.isEmpty else { return nil }
        let rowMinX = rows.map { row in row.map(\.box.minX).min() ?? 0 }
        let leftmost = rowMinX.min() ?? 0
        let width = characterWidth(map)
        return zip(rows, rowMinX).map { row, minX in
            let indent =
                width >= minimumCharacterWidth ? Int(((minX - leftmost) / width).rounded(.toNearestOrAwayFromZero)) : 0
            return String(repeating: " ", count: max(indent, 0)) + row.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// The median over all lines of `box.width / text.count`; the mean of the two middle values for an even count;
    /// 0 with no lines (T7).
    static func characterWidth(_ map: TextMap) -> Double {
        let widths = map.lines.filter { !$0.text.isEmpty }.map { $0.box.width / Double($0.text.count) }.sorted()
        guard !widths.isEmpty else { return 0 }
        let middle = widths.count / 2
        return widths.count % 2 == 1 ? widths[middle] : (widths[middle - 1] + widths[middle]) / 2
    }

    /// The first line, spaces trimmed, cut to 60 characters plus `…` when longer, then ` (N lines)` when the text
    /// has more than one line (`design/05` B2), e.g. `Traceback (most recent call last): (12 lines)`.
    public static func summary(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var first = Substring(lines.first ?? "")
        while let c = first.first, c == " " || c == "\t" { first.removeFirst() }
        while let c = first.last, c == " " || c == "\t" { first.removeLast() }
        var result = first.count > summaryLength ? String(first.prefix(summaryLength)) + "…" : String(first)
        if lines.count > 1 { result += " (\(lines.count) lines)" }
        return result
    }
}
