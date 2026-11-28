/// How an image is cut into strips for reading (OCR §5.1, T6), in input pixels.
public struct StripPlan: Hashable, Sendable {
    /// 2 below 2 pixels per point (the image is enlarged before reading), else 1.
    public let scale: Int
    /// Rows per strip: 4000 / scale.
    public let rows: Int
    /// Rows shared by consecutive strips: 200 / scale.
    public let overlap: Int

    public init(pixelsPerPoint: Double) {
        scale = pixelsPerPoint < 2 ? 2 : 1
        rows = 4000 / scale
        overlap = 200 / scale
    }

    /// One strip `0..<H` when `H ≤ rows`; otherwise strips of `rows` rows starting `rows − overlap` apart, the last
    /// one ending at `H`.
    public func strips(height: Int) -> [Range<Int>] {
        guard height > 0 else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        while true {
            result.append(start..<min(start + rows, height))
            if start + rows >= height { return result }
            start += rows - overlap
        }
    }
}
