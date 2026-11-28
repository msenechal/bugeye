// OCR-owned from Wave 1 (contracts §4.1.9, K3): word-level since the OCR epic (OCR §3.2, T4).

/// One word of an `OCRLine`, as the recogniser boxed it.
public struct OCRWord: Hashable, Codable, Sendable {
    /// The word's characters (`Character` offsets) in the line's `text`. Never empty; never overlapping another word.
    public var range: Range<Int>
    /// In the read image's pixels, top-left origin.
    public var bounds: Rect2D

    public init(range: Range<Int>, bounds: Rect2D) {
        self.range = range
        self.bounds = bounds
    }
}

/// A line of recognised text. `bounds` is in the image's pixels, top-left origin.
public struct OCRLine: Hashable, Codable, Sendable {
    public var text: String
    public var bounds: Rect2D
    public var confidence: Double
    /// The whitespace-separated words of `text` that the recogniser could box, in order. A word it couldn't box is
    /// missing here, but stays in `text`.
    public var words: [OCRWord]

    public init(text: String, bounds: Rect2D, confidence: Double, words: [OCRWord] = []) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
        self.words = words
    }
}

/// OCR (Vision on macOS). Reads `image` exactly as given: no strips, no scaling (TextCore does both).
/// Slow: never call it on the main actor. Throws `CancellationError` when its task is cancelled.
public protocol TextReader: Sendable {
    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine]
}

/// Vision-style normalised rects (0…1, bottom-left origin) to pixel rects (top-left origin):
/// x = minX·w, y = (1 − maxY)·h, width·w, height·h. Shared by the OCR, face and rectangle adapters.
public enum NormalizedRect2D {
    public static func pixelRect(_ normalized: Rect2D, imageWidth: Int, imageHeight: Int) -> Rect2D {
        let w = Double(imageWidth)
        let h = Double(imageHeight)
        return Rect2D(
            x: normalized.minX * w, y: (1 - normalized.maxY) * h,
            width: normalized.width * w, height: normalized.height * h)
    }
}
