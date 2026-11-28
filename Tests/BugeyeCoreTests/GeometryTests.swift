import BugeyeCore
import Testing

@Suite struct GeometryTests {
    @Test func standardizedFlipsNegativeSizes() {
        let rect = Rect2D(x: 10, y: 20, width: -4, height: -6)
        #expect(rect.standardized == Rect2D(x: 6, y: 14, width: 4, height: 6))
    }

    @Test func containsIsHalfOpen() {
        let rect = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(rect.contains(Point2D(x: 0, y: 0)))
        #expect(rect.contains(Point2D(x: 9.99, y: 9.99)))
        #expect(!rect.contains(Point2D(x: 10, y: 5)))
        #expect(!rect.contains(Point2D(x: 5, y: 10)))
    }

    @Test func intersectionOfOverlappingRects() {
        let a = Rect2D(x: 0, y: 0, width: 10, height: 10)
        let b = Rect2D(x: 5, y: -5, width: 10, height: 10)
        #expect(a.intersection(b) == Rect2D(x: 5, y: 0, width: 5, height: 5))
    }

    @Test func touchingOrDisjointRectsDoNotIntersect() {
        let a = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(a.intersection(Rect2D(x: 10, y: 0, width: 5, height: 5)) == nil)
        #expect(a.intersection(Rect2D(x: 20, y: 20, width: 5, height: 5)) == nil)
    }

    @Test func emptyWhenEitherSideIsZero() {
        #expect(Rect2D(x: 1, y: 1, width: 0, height: 5).isEmpty)
        #expect(Rect2D(x: 1, y: 1, width: 5, height: 0).isEmpty)
        #expect(!Rect2D(x: 1, y: 1, width: 1, height: 1).isEmpty)
    }
}
