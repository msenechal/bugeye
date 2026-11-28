import BugeyeCore
import Foundation
import Testing

@testable import TextCore

@Suite struct TextMapBuilderTests {
    @Test func textIsNormalisedToNFC() {
        let decomposed = "Où".decomposedStringWithCanonicalMapping
        let line = textLine(ocr(decomposed, rect(0, 0, 20, 10)))
        #expect(line.text.unicodeScalars.count == 2)
        #expect(
            line.text.unicodeScalars.map(\.value)
                == "Où".precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value))
    }

    @Test func trimmingShiftsAndClipsWordRanges() {
        let line = textLine(
            ocr(
                "  ab cd \n", rect(0, 0, 90, 10),
                words: [word(2..<4, rect(20, 0, 20, 10)), word(5..<8, rect(50, 0, 30, 10))]))
        #expect(line.text == "ab cd")
        #expect(line.words.map(\.range) == [0..<2, 3..<5])
        #expect(line.words.map(\.text) == ["ab", "cd"])
    }

    @Test func aWordLeftEmptyByTrimmingIsDropped() {
        let line = textLine(ocr(" ab  ", rect(0, 0, 50, 10), words: [word(3..<5, rect(30, 0, 20, 10))]))
        #expect(line.words.isEmpty)
    }

    @Test func emptyAndWhitespaceLinesAreDropped() {
        let map = TextMapBuilder.build(
            [ocr("", rect(0, 0, 10, 10)), ocr(" \t\n", rect(0, 20, 10, 10)), ocr("x", rect(0, 40, 10, 10))],
            width: 100, height: 100)
        #expect(map.lines.map(\.text) == ["x"])
    }

    @Test func lineBoxesAreClippedToTheImage() {
        let map = TextMapBuilder.build([ocr("x", rect(-10, 90, 30, 20))], width: 100, height: 100)
        #expect(map.lines[0].box == rect(0, 90, 20, 10))
    }

    @Test func aLineOutsideTheImageIsDropped() {
        let map = TextMapBuilder.build(
            [ocr("out", rect(100, 0, 30, 20)), ocr("flat", rect(0, 0, 30, 0))], width: 100, height: 100)
        #expect(map.isEmpty)
        #expect(map.lines.isEmpty)
    }

    @Test func badWordsAreDropped() {
        let line = textLine(
            ocr(
                "aa bb cc dd ee", rect(0, 0, 140, 10),
                words: [
                    word(-1..<2, rect(0, 0, 20, 10)),  // out of bounds
                    word(0..<2, rect(0, 0, 20, 10)),  // kept
                    word(1..<4, rect(10, 0, 30, 10)),  // overlaps the kept one
                    word(3..<3, rect(30, 0, 0, 10)),  // empty
                    word(6..<8, rect(60, 0, 20, 10)),  // kept
                    word(8..<9, rect(80, 0, 10, 10)),  // whitespace only
                    word(9..<11, rect(20_000, 0, 20, 10)),  // box outside the image
                    word(12..<20, rect(120, 0, 20, 10)),  // out of bounds
                ]), width: 1000, height: 1000)
        #expect(line.words.map(\.text) == ["aa", "cc"])
    }

    @Test func wordsOutOfOrderAreKeptInOrder() {
        let line = textLine(
            ocr(
                "ab cd", rect(0, 0, 50, 10), words: [word(3..<5, rect(30, 0, 20, 10)), word(0..<2, rect(0, 0, 20, 10))])
        )
        #expect(line.words.map(\.text) == ["ab", "cd"])
    }

    @Test func aWordsPaddingIsTrimmed() {
        let line = textLine(ocr("ab cd", rect(0, 0, 50, 10), words: [word(2..<5, rect(20, 0, 30, 10))]))
        #expect(line.words.map(\.range) == [3..<5])
        #expect(line.words.map(\.text) == ["cd"])
    }

    @Test func wordBoxesAreClippedToTheImage() {
        let map = TextMapBuilder.build(
            [ocr("ab", rect(0, 0, 50, 10), words: [word(0..<2, rect(-5, -5, 20, 20))])], width: 100, height: 100)
        #expect(map.lines[0].words[0].box == rect(0, 0, 15, 15))
    }

    @Test func confidenceIsClamped() {
        let map = TextMapBuilder.build(
            [
                ocr("a", rect(0, 0, 10, 10), confidence: 1.5), ocr("b", rect(0, 20, 10, 10), confidence: -1),
                ocr("c", rect(0, 40, 10, 10), confidence: .nan),
            ], width: 100, height: 100)
        #expect(map.lines.map(\.confidence) == [1, 0, 0])
    }

    @Test func theMapKeepsItsPixelSpace() {
        let map = TextMapBuilder.build([], width: 640, height: 480)
        #expect(map.width == 640)
        #expect(map.height == 480)
        #expect(map.isEmpty)
    }
}

@Suite struct ReadingOrderTests {
    func order(_ lines: [OCRLine]) -> [String] {
        TextMapBuilder.build(lines, width: 10_000, height: 10_000).lines.map(\.text)
    }

    @Test func twoLinesOnARowComeOutLeftToRight() {
        // The right-hand line sits 2 px higher: a (minY, minX) sort alone would put it first.
        #expect(order([ocr("left", rect(0, 10, 40, 20)), ocr("right", rect(100, 8, 50, 20))]) == ["left", "right"])
        #expect(order([ocr("right", rect(100, 8, 50, 20)), ocr("left", rect(0, 10, 40, 20))]) == ["left", "right"])
    }

    @Test func rowsRunTopToBottom() {
        #expect(order([ocr("second", rect(0, 50, 40, 20)), ocr("first", rect(0, 10, 40, 20))]) == ["first", "second"])
    }

    @Test func groupingComparesWithTheRowsFirstLine() {
        // b overlaps a by 10 of 20 (joins); c overlaps b by 10 but a by 0, so c starts a new row.
        let map = TextMapBuilder.build(
            [ocr("a", rect(0, 0, 10, 20)), ocr("b", rect(20, 10, 10, 20)), ocr("c", rect(40, 20, 10, 20))],
            width: 100, height: 100)
        #expect(map.lines.map(\.text) == ["a", "b", "c"])
        #expect(map.lines.map(\.row) == [0, 0, 1])
    }

    @Test func aBigNumberBesideATwoLineCaptionIsOneRow() {
        let map = TextMapBuilder.build(
            [
                ocr("Requests today", rect(120, 10, 140, 30)), ocr("up 12%", rect(120, 50, 60, 30)),
                ocr("42", rect(0, 0, 100, 100)),
            ], width: 1000, height: 1000)
        #expect(map.lines.map(\.text) == ["42", "Requests today", "up 12%"])
        #expect(map.lines.map(\.row) == [0, 0, 0])
    }

    @Test func tiesKeepInputOrder() {
        #expect(order([ocr("one", rect(0, 0, 10, 10)), ocr("two", rect(0, 0, 10, 10))]) == ["one", "two"])
        #expect(order([ocr("two", rect(0, 0, 10, 10)), ocr("one", rect(0, 0, 10, 10))]) == ["two", "one"])
    }

    @Test func rowsAreIndexed() {
        let map = TextMapBuilder.build(
            [
                ocr("c", rect(0, 100, 10, 20)), ocr("a", rect(0, 0, 10, 20)), ocr("b", rect(50, 2, 10, 20)),
            ], width: 1000, height: 1000)
        #expect(map.lines.map(\.text) == ["a", "b", "c"])
        #expect(map.lines.map(\.row) == [0, 0, 1])
    }
}
