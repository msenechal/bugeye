import BugeyeCore

/// Returns the lines the test gives, for any image.
public struct FakeTextReader: TextReader {
    public var lines: [OCRLine]
    public init(lines: [OCRLine] = []) { self.lines = lines }
    public func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] { lines }
}
