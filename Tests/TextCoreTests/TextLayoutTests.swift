import BugeyeCore
import Testing

@testable import TextCore

@Suite struct TextLayoutTests {
    func map(_ lines: [OCRLine]) -> TextMap {
        TextMapBuilder.build(lines, width: 10_000, height: 10_000)
    }

    @Test func oneOutputLinePerRowJoinedWithOneSpace() {
        let m = map([
            boxedLine("Name", x: 0, y: 0), boxedLine("Morgan", x: 200, y: 2), boxedLine("Save", x: 0, y: 40),
        ])
        #expect(TextLayout.lines(m) == "Name Morgan\nSave")
    }

    @Test func aTracebackKeepsItsIndentationWithANarrowLinePresent() {
        // 10 px per character; the "|||" line is 2 px per character and must not inflate the indents.
        let m = map([
            boxedLine("Traceback (most recent call last):", x: 100, y: 0),
            boxedLine("File \"app.py\", line 3, in <module>", x: 120, y: 30),
            boxedLine("main()", x: 140, y: 60),
            ocr("|||", rect(140, 90, 6, 20)),
            boxedLine("ValueError: bad", x: 100, y: 120),
        ])
        #expect(
            TextLayout.lines(m)
                == "Traceback (most recent call last):\n  File \"app.py\", line 3, in <module>\n    main()\n"
                + "    |||\nValueError: bad")
    }

    @Test func theCharacterWidthIsTheMedianAndAnEvenCountAveragesTheMiddleTwo() {
        // Widths per character: 10 and 20 → median 15; the second row is 30 px in → 2 spaces.
        let m = map([ocr("ab", rect(0, 0, 20, 20)), ocr("cd", rect(30, 40, 40, 20))])
        #expect(TextLayout.characterWidth(m) == 15)
        #expect(TextLayout.lines(m) == "ab\n  cd")
    }

    @Test func halfRoundsAwayFromZero() {
        // 15 px in at 10 px per character is 1.5 → 2 spaces.
        let m = map([boxedLine("a", x: 0, y: 0), boxedLine("b", x: 15, y: 40)])
        #expect(TextLayout.lines(m) == "a\n  b")
    }

    @Test func twoAndAHalfRoundsAwayFromZeroNotToEven() {
        // 25 px in at 10 px per character is 2.5 → 3 spaces (banker's rounding would give 2).
        let m = map([boxedLine("a", x: 0, y: 0), boxedLine("b", x: 25, y: 40)])
        #expect(TextLayout.lines(m) == "a\n   b")
    }

    @Test func indentationIsMeasuredFromTheLeftmostRowNotTheFirst() {
        // A heading indented above body text.
        let m = map([boxedLine("head", x: 20, y: 0), boxedLine("body", x: 0, y: 40)])
        #expect(TextLayout.lines(m) == "  head\nbody")
    }

    @Test func noCharacterWidthMeansNoIndent() {
        let line = TextLine(text: "x", box: rect(50, 40, 0, 10), words: [], confidence: 1, row: 1)
        let first = TextLine(text: "y", box: rect(0, 0, 0, 10), words: [], confidence: 1, row: 0)
        let m = TextMap(width: 100, height: 100, lines: [first, line])
        #expect(TextLayout.lines(m) == "y\nx")
    }

    @Test func anEmptyMapHasNoText() {
        #expect(TextLayout.lines(TextMap(width: 10, height: 10, lines: [])) == nil)
    }

    @Test func summaryOfOneShortLineIsTheLine() {
        #expect(TextLayout.summary("  Save  ") == "Save")
    }

    @Test func summaryCutsAtSixtyCharactersWithAnEllipsis() {
        let long = String(repeating: "a", count: 61)
        #expect(TextLayout.summary(long) == String(repeating: "a", count: 60) + "…")
        #expect(TextLayout.summary(String(repeating: "b", count: 60)) == String(repeating: "b", count: 60))
    }

    @Test func summaryCountsLines() {
        let text = (["Traceback (most recent call last):"] + Array(repeating: "  x", count: 11)).joined(separator: "\n")
        #expect(TextLayout.summary(text) == "Traceback (most recent call last): (12 lines)")
    }
}
