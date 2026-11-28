import BugeyeCore

extension TextLine {
    /// The box of a run of characters (OCR §4.3), in the map's pixel space; nil when the run is empty or holds only
    /// whitespace. The range is clamped to the text first (plan P11).
    public func box(for range: Range<Int>) -> Rect2D? {
        let chars = Array(text)
        let range = range.clamped(to: 0..<chars.count)
        guard !range.isEmpty, chars[range].contains(where: { !$0.isWhitespace }) else { return nil }

        let words =
            self.words.isEmpty ? [TextWord(text: text, range: 0..<chars.count, box: box)] : self.words
        var pieces: [Rect2D] = []
        for word in words where word.range.overlaps(range) {
            if range.contains(word.range.lowerBound), range.upperBound >= word.range.upperBound {
                pieces.append(word.box)
                continue
            }
            let count = Double(word.range.count)
            let start = Double(max(range.lowerBound, word.range.lowerBound) - word.range.lowerBound)
            let end = Double(min(range.upperBound, word.range.upperBound) - word.range.lowerBound)
            let x0 = word.box.minX + word.box.width * start / count
            let x1 = word.box.minX + word.box.width * end / count
            pieces.append(Rect2D(x: x0, y: word.box.minY, width: x1 - x0, height: word.box.height))
        }

        // Characters no word covers (Vision couldn't box them) get a slice of the line box.
        let perCharacter = box.width / Double(chars.count)
        for index in range where !chars[index].isWhitespace {
            guard !words.contains(where: { $0.range.contains(index) }) else { continue }
            pieces.append(
                Rect2D(
                    x: box.minX + perCharacter * Double(index), y: box.minY, width: perCharacter,
                    height: box.height))
        }
        return pieces.reduce(nil) { $0?.union($1) ?? $1 }
    }
}

extension Rect2D {
    /// The smallest rect holding both.
    func union(_ other: Rect2D) -> Rect2D {
        let x0 = min(minX, other.minX)
        let y0 = min(minY, other.minY)
        return Rect2D(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }
}
