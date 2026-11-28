import BugeyeCore
import Foundation
import Testing

@Suite struct TextReaderTests {
    @Test func theLineOnlyInitialiserStillCompilesAndHasNoWords() {
        let line = OCRLine(text: "Save", bounds: Rect2D(x: 1, y: 2, width: 3, height: 4), confidence: 0.5)
        #expect(line.words.isEmpty)
    }

    @Test func aLineWithWordsRoundTripsThroughJSON() throws {
        let line = OCRLine(
            text: "let x", bounds: Rect2D(x: 0, y: 0, width: 50, height: 10), confidence: 0.9,
            words: [
                OCRWord(range: 0..<3, bounds: Rect2D(x: 0, y: 0, width: 30, height: 10)),
                OCRWord(range: 4..<5, bounds: Rect2D(x: 40, y: 0, width: 10, height: 10)),
            ])
        let data = try JSONEncoder().encode(line)
        #expect(try JSONDecoder().decode(OCRLine.self, from: data) == line)
    }

    @Test func aNormalisedRectBecomesTopLeftPixels() {
        let rect = NormalizedRect2D.pixelRect(
            Rect2D(x: 0.25, y: 0.5, width: 0.5, height: 0.25), imageWidth: 200, imageHeight: 100)
        #expect(rect == Rect2D(x: 50, y: 25, width: 100, height: 25))
    }

    @Test func aNegativeSizeNormalisedRectIsStandardised() {
        let rect = NormalizedRect2D.pixelRect(
            Rect2D(x: 0.75, y: 0.75, width: -0.5, height: -0.25), imageWidth: 200, imageHeight: 100)
        #expect(rect == Rect2D(x: 50, y: 25, width: 100, height: 25))
    }
}
