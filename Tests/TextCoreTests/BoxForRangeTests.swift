import BugeyeCore
import Testing

@testable import TextCore

@Suite struct BoxForRangeTests {
    @Test func aWholeWordIsItsBox() {
        let line = textLine(boxedLine("hello world", x: 0, y: 0))
        #expect(line.box(for: 6..<11) == rect(60, 0, 50, 20))
    }

    @Test func customerInsideCustomersIsEightNinthsOfItsWidth() {
        let line = textLine(boxedLine("customers", x: 0, y: 0))
        #expect(line.box(for: 0..<8) == rect(0, 0, 80, 20))
    }

    @Test func aPartialWordIsCutInProportionToCharacters() {
        // The word box is wider than 10 px per character: the cut follows the word, not the line.
        let line = textLine(ocr("abcd", rect(0, 0, 40, 20), words: [word(0..<4, rect(100, 0, 200, 20))]))
        #expect(line.box(for: 1..<3) == rect(150, 0, 100, 20))
    }

    @Test func aRangeAcrossTwoWordsIsTheUnion() {
        let line = textLine(boxedLine("hello world", x: 0, y: 0))
        #expect(line.box(for: 3..<8) == rect(30, 0, 50, 20))
    }

    @Test func emptyAndWhitespaceRangesHaveNoBox() {
        let line = textLine(boxedLine("hello world", x: 0, y: 0))
        #expect(line.box(for: 2..<2) == nil)
        #expect(line.box(for: 5..<6) == nil)
    }

    @Test func aLineWithoutWordsIsSlicedByCharacters() {
        let line = textLine(ocr("abcd", rect(10, 5, 40, 20)))
        #expect(line.box(for: 1..<3) == rect(20, 5, 20, 20))
        #expect(line.box(for: 0..<4) == rect(10, 5, 40, 20))
    }

    @Test func aRepeatedWordWithItsFirstCopyUnboxed() {
        // "go go": Vision boxed only the second "go".
        let line = textLine(ocr("go go", rect(0, 0, 50, 20), words: [word(3..<5, rect(30, 0, 20, 20))]))
        #expect(line.box(for: 0..<2) == rect(0, 0, 20, 20))
        #expect(line.box(for: 3..<5) == rect(30, 0, 20, 20))
        #expect(line.box(for: 0..<5) == rect(0, 0, 50, 20))
    }

    @Test func unboxedCharactersAreSlicedFromTheLinesOwnLeftEdge() {
        let line = textLine(ocr("go go", rect(100, 0, 50, 20), words: [word(3..<5, rect(130, 0, 20, 20))]))
        #expect(line.box(for: 0..<2) == rect(100, 0, 20, 20))
    }

    @Test func outOfRangeRangesAreClamped() {
        let line = textLine(boxedLine("abc", x: 0, y: 0))
        #expect(line.box(for: 1..<99) == rect(10, 0, 20, 20))
        #expect(line.box(for: 50..<99) == nil)
    }
}
