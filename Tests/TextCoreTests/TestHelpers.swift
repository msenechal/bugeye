import BugeyeCore
import Foundation

@testable import TextCore

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect2D {
    Rect2D(x: x, y: y, width: w, height: h)
}

func ocr(_ text: String, _ box: Rect2D, confidence: Double = 0.9, words: [OCRWord] = []) -> OCRLine {
    OCRLine(text: text, bounds: box, confidence: confidence, words: words)
}

func word(_ range: Range<Int>, _ box: Rect2D) -> OCRWord {
    OCRWord(range: range, bounds: box)
}

/// A line whose words are boxed evenly at `charWidth` per character, split on single spaces.
func boxedLine(_ text: String, x: Double, y: Double, charWidth: Double = 10, height: Double = 20) -> OCRLine {
    var words: [OCRWord] = []
    var start = 0
    let chars = Array(text) + [" "]
    for (i, ch) in chars.enumerated() {
        if ch == " " {
            if i > start {
                words.append(
                    OCRWord(
                        range: start..<i,
                        bounds: Rect2D(
                            x: x + Double(start) * charWidth, y: y, width: Double(i - start) * charWidth,
                            height: height)))
            }
            start = i + 1
        }
    }
    return OCRLine(
        text: text, bounds: Rect2D(x: x, y: y, width: Double(text.count) * charWidth, height: height),
        confidence: 0.9, words: words)
}

/// Builds a one-line map and returns its line.
func textLine(_ line: OCRLine, width: Int = 10_000, height: Int = 10_000) -> TextLine {
    TextMapBuilder.build([line], width: width, height: height).lines[0]
}

/// Polls `condition` until it holds, yielding and sleeping briefly; fails the caller after about two seconds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if await condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}
