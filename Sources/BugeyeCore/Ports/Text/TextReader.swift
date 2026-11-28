// OCR-owned from Wave 1 (contracts §4.1.9): moved here unchanged; OCR reshapes it (T4).

/// A line of recognised text. `bounds` is in the image's pixels, top-left origin.
public struct OCRLine: Hashable, Codable, Sendable {
    public var text: String
    public var bounds: Rect2D
    public var confidence: Double

    public init(text: String, bounds: Rect2D, confidence: Double) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// OCR (Vision on macOS).
public protocol TextReader: Sendable {
    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine]
}
