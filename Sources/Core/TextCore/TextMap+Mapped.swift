import BugeyeCore

extension TextMap {
    /// The map in another pixel space (OCR §4.5): every box becomes `(x·scale + offset.x, y·scale + offset.y,
    /// w·scale, h·scale)`, then line and word boxes are clipped to `width` × `height`, dropping lines and words left
    /// empty. Keeps the order and renumbers rows densely (plan P8).
    public func mapped(scale: Double, offset: Point2D, width: Int, height: Int) -> TextMap {
        let bounds = Rect2D(x: 0, y: 0, width: Double(max(width, 0)), height: Double(max(height, 0)))
        func transform(_ box: Rect2D) -> Rect2D? {
            TextMapBuilder.clip(
                Rect2D(
                    x: box.minX * scale + offset.x, y: box.minY * scale + offset.y, width: box.width * scale,
                    height: box.height * scale), to: bounds)
        }
        var result: [TextLine] = []
        var rowIndex: [Int: Int] = [:]
        for line in lines {
            guard let box = transform(line.box) else { continue }
            var copy = line
            copy.box = box
            copy.words = line.words.compactMap { word in
                guard let box = transform(word.box) else { return nil }
                var word = word
                word.box = box
                return word
            }
            if rowIndex[line.row] == nil { rowIndex[line.row] = rowIndex.count }
            copy.row = rowIndex[line.row] ?? 0
            result.append(copy)
        }
        return TextMap(width: width, height: height, lines: result)
    }
}
