import BugeyeCore
import Foundation
import Testing

@testable import TextCore

@Suite struct FindTests {
    func map(_ lines: OCRLine...) -> TextMap {
        TextMapBuilder.build(lines, width: 10_000, height: 10_000)
    }

    @Test func ouFindsOu() {
        let m = map(boxedLine("Où est-il", x: 0, y: 0))
        #expect(m.matches(of: "ou").map(\.range) == [0..<2])
        #expect(m.matches(of: "OU").map(\.range) == [0..<2])
    }

    @Test func matchCaseRespectsCaseButStillFoldsAccents() {
        let m = map(boxedLine("Où ou", x: 0, y: 0))
        #expect(m.matches(of: "Ou", matchCase: true).map(\.range) == [0..<2])
        #expect(m.matches(of: "ou", matchCase: true).map(\.range) == [3..<5])
    }

    @Test func aMatchMaySpanWords() {
        let m = map(boxedLine("hello world", x: 0, y: 0))
        let found = m.matches(of: "lo wo")
        #expect(found.map(\.range) == [3..<8])
        #expect(found.map(\.box) == [rect(30, 0, 50, 20)])
    }

    @Test func matchesNeverCrossLines() {
        let m = map(boxedLine("abc", x: 0, y: 0), boxedLine("def", x: 0, y: 100))
        #expect(m.matches(of: "cd").isEmpty)
        #expect(m.matches(of: "c d").isEmpty)
    }

    @Test func matchesRunLeftToRightWithoutOverlaps() {
        let m = map(boxedLine("aaaa", x: 0, y: 0))
        #expect(m.matches(of: "aa").map(\.range) == [0..<2, 2..<4])
        #expect(map(boxedLine("aaa", x: 0, y: 0)).matches(of: "aa").map(\.range) == [0..<2])
    }

    @Test func matchesFollowReadingOrder() {
        let m = map(boxedLine("key two", x: 0, y: 100), boxedLine("key one", x: 0, y: 0))
        let found = m.matches(of: "key")
        #expect(found.map(\.line) == [0, 1])
        #expect(m.lines.map(\.text) == ["key one", "key two"])
    }

    @Test func emptyAndWhitespaceQueriesHaveNoMatches() {
        let m = map(boxedLine("a b", x: 0, y: 0))
        #expect(m.matches(of: "").isEmpty)
        #expect(m.matches(of: "  ").isEmpty)
    }

    @Test func aDecomposedQueryMatchesAPrecomposedLine() {
        let m = map(boxedLine("garçon", x: 0, y: 0))
        #expect(m.matches(of: "garçon".decomposedStringWithCanonicalMapping).map(\.range) == [0..<6])
        #expect(m.matches(of: "GARCON").map(\.range) == [0..<6])
    }

    @Test func aMatchsBoxIsBoxForItsRange() {
        let m = map(boxedLine("customers", x: 0, y: 0))
        let found = m.matches(of: "customer")
        #expect(found == [TextMatch(line: 0, range: 0..<8, box: rect(0, 0, 80, 20))])
    }

    @Test func aMatchOfOnlySpacesInsideTheLineIsSkipped() {
        // "a  b": the query "  " is whitespace only, so it has no matches at all.
        #expect(map(boxedLine("a  b", x: 0, y: 0)).matches(of: "  ").isEmpty)
    }

    @Test func emojiAndCombiningMarksCountAsOneCharacter() {
        let m = map(boxedLine("👍🏽 ok", x: 0, y: 0))
        #expect(m.matches(of: "ok").map(\.range) == [2..<4])
    }
}
