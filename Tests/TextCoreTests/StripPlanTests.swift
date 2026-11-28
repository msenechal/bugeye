import Testing

@testable import TextCore

@Suite struct StripPlanTests {
    @Test func belowTwoPixelsPerPointTheScaleIsTwo() {
        #expect(StripPlan(pixelsPerPoint: 1).scale == 2)
        #expect(StripPlan(pixelsPerPoint: 1.5).scale == 2)
        #expect(StripPlan(pixelsPerPoint: 2).scale == 1)
        #expect(StripPlan(pixelsPerPoint: 3).scale == 1)
    }

    @Test func rowsAndOverlapAreInInputPixels() {
        #expect(StripPlan(pixelsPerPoint: 2).rows == 4000)
        #expect(StripPlan(pixelsPerPoint: 2).overlap == 200)
        #expect(StripPlan(pixelsPerPoint: 1).rows == 2000)
        #expect(StripPlan(pixelsPerPoint: 1).overlap == 100)
    }

    @Test func aShortImageIsOneStrip() {
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 4000) == [0..<4000])
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 10) == [0..<10])
    }

    @Test func theSpecsExamples() {
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 8200) == [0..<4000, 3800..<7800, 7600..<8200])
        #expect(StripPlan(pixelsPerPoint: 1).strips(height: 4500) == [0..<2000, 1900..<3900, 3800..<4500])
    }

    @Test func oneRowMoreThanAStripMakesTwo() {
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 4001) == [0..<4000, 3800..<4001])
    }

    @Test func anExactFitEndsOnTheLastFullStrip() {
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 7800) == [0..<4000, 3800..<7800])
        #expect(StripPlan(pixelsPerPoint: 1).strips(height: 3900) == [0..<2000, 1900..<3900])
    }

    @Test func noRowsNoStrips() {
        #expect(StripPlan(pixelsPerPoint: 2).strips(height: 0) == [])
    }
}
