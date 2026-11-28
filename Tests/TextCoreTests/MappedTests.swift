import BugeyeCore
import Testing

@testable import TextCore

@Suite struct MappedTests {
    @Test func scaleAndOffsetApplyToLinesAndWords() {
        let map = TextMapBuilder.build([boxedLine("ab cd", x: 10, y: 20)], width: 200, height: 100)
        let mapped = map.mapped(scale: 0.5, offset: Point2D(x: 0, y: 1000), width: 100, height: 2000)
        #expect(mapped.width == 100)
        #expect(mapped.height == 2000)
        #expect(mapped.lines[0].box == rect(5, 1010, 25, 10))
        #expect(mapped.lines[0].words.map(\.box) == [rect(5, 1010, 10, 10), rect(20, 1010, 10, 10)])
        #expect(mapped.lines[0].text == "ab cd")
    }

    @Test func boxesAreClippedToTheNewSize() {
        let map = TextMapBuilder.build([boxedLine("ab cd", x: 0, y: 0)], width: 200, height: 100)
        let mapped = map.mapped(scale: 1, offset: Point2D(x: -20, y: 0), width: 100, height: 100)
        #expect(mapped.lines[0].box == rect(0, 0, 30, 20))
        #expect(mapped.lines[0].words.map(\.text) == ["cd"])
        #expect(mapped.lines[0].words.map(\.box) == [rect(10, 0, 20, 20)])
    }

    @Test func linesOutsideAreDroppedAndRowsRenumbered() {
        let map = TextMapBuilder.build(
            [boxedLine("top", x: 0, y: 0), boxedLine("middle", x: 0, y: 50), boxedLine("bottom", x: 0, y: 100)],
            width: 200, height: 200)
        let mapped = map.mapped(scale: 1, offset: Point2D(x: 0, y: -50), width: 200, height: 100)
        #expect(mapped.lines.map(\.text) == ["middle", "bottom"])
        #expect(mapped.lines.map(\.row) == [0, 1])
        #expect(mapped.lines[0].box == rect(0, 0, 60, 20))
    }
}
