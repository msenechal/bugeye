import Foundation

extension TextMap {
    /// Find (OCR §4.4): runs of whole consecutive characters of one line whose folded forms equal the folded query,
    /// left to right without overlaps, line by line in reading order. A match with no box is skipped; an empty or
    /// whitespace-only query has no matches.
    public func matches(of query: String, matchCase: Bool = false) -> [TextMatch] {
        guard query.contains(where: { !$0.isWhitespace }) else { return [] }
        let needle = query.flatMap { TextFold.fold($0, matchCase: matchCase) }
        guard !needle.isEmpty else { return [] }
        var result: [TextMatch] = []
        for (index, line) in lines.enumerated() {
            let folded = line.text.map { TextFold.fold($0, matchCase: matchCase) }
            var start = 0
            while start < folded.count {
                guard let end = matchEnd(folded, from: start, needle: needle) else {
                    start += 1
                    continue
                }
                if let box = line.box(for: start..<end) {
                    result.append(TextMatch(line: index, range: start..<end, box: box))
                }
                start = end
            }
        }
        return result
    }

    /// The end of a run starting at `start` whose folded scalars equal `needle`, or nil.
    private func matchEnd(_ folded: [[Unicode.Scalar]], from start: Int, needle: [Unicode.Scalar]) -> Int? {
        var length = 0
        var end = start
        while end < folded.count {
            let piece = folded[end]
            guard length + piece.count <= needle.count,
                needle[length..<(length + piece.count)].elementsEqual(piece)
            else { return nil }
            length += piece.count
            end += 1
            if length == needle.count { return end }
        }
        return nil
    }
}

/// The per-character fold of find (OCR §4.4): canonical decomposition, nonspacing marks removed, then lowercased
/// unless matching case. Portable and identical on Linux and macOS.
enum TextFold {
    static func fold(_ character: Character, matchCase: Bool) -> [Unicode.Scalar] {
        var scalars = String.UnicodeScalarView()
        for scalar in String(character).decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        let string = String(scalars)
        return Array((matchCase ? string : string.lowercased()).unicodeScalars)
    }
}
