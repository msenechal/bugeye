import BugeyeCore
import QuickAccessCore
import Testing

private struct Thumb: Identifiable, Equatable {
    let id: Int
}

@Suite struct QuickAccessStackTests {
    @Test func stackLimitFollowsTheVisibleHeight() {
        #expect(QuickAccessStack<Thumb>.fitting(height: 850) == 4)
        #expect(QuickAccessStack<Thumb>.fitting(height: 176 + 32) == 1)
        #expect(QuickAccessStack<Thumb>.fitting(height: 0) == 1)
        #expect(QuickAccessStack<Thumb>.fitting(height: 2 * 186 - 10 + 32) == 2)
        #expect(QuickAccessStack<Thumb>.fitting(height: 2 * 186 - 10 + 31) == 1)
        #expect(QuickAccessStack<Thumb>.fitting(height: 2000) == 10)
        #expect(QuickAccessStack<Thumb>.limit(height: 2000) == 5)
        #expect(QuickAccessStack<Thumb>.limit(height: 850) == 4)
    }

    @Test func pushEvictsTheOldestFirst() {
        var stack = QuickAccessStack<Thumb>()
        for i in 1...5 { #expect(stack.push(Thumb(id: i), limit: 5, sparing: nil).isEmpty) }
        let evicted = stack.push(Thumb(id: 6), limit: 5, sparing: nil)
        #expect(evicted == [Thumb(id: 1)])
        #expect(stack.items.map(\.id) == [2, 3, 4, 5, 6])
    }

    @Test func hoveredThumbnailIsNotEvictedByANewCapture() {
        var stack = QuickAccessStack<Thumb>()
        for i in 1...4 { stack.push(Thumb(id: i), limit: 4, sparing: nil) }
        let evicted = stack.push(Thumb(id: 5), limit: 4, sparing: 1)
        #expect(evicted == [Thumb(id: 2)])
        #expect(stack.items.map(\.id) == [1, 3, 4, 5])
    }

    @Test func aSmallerLimitEvictsSeveral() {
        var stack = QuickAccessStack<Thumb>()
        for i in 1...5 { stack.push(Thumb(id: i), limit: 5, sparing: nil) }
        let evicted = stack.push(Thumb(id: 6), limit: 2, sparing: 3)
        #expect(evicted.map(\.id) == [1, 2, 4, 5])
        #expect(stack.items.map(\.id) == [3, 6])
    }

    @Test func aOneSlotScreenKeepsTheHoveredAndTheNewThumbnail() {
        var stack = QuickAccessStack<Thumb>()
        stack.push(Thumb(id: 1), limit: 1, sparing: nil)
        let evicted = stack.push(Thumb(id: 2), limit: 1, sparing: 1)
        #expect(evicted.isEmpty)
        #expect(stack.items.map(\.id) == [1, 2])
    }

    @Test func removeTakesOneItemOut() {
        var stack = QuickAccessStack<Thumb>()
        for i in 1...3 { stack.push(Thumb(id: i), limit: 5, sparing: nil) }
        #expect(stack.remove(2) == Thumb(id: 2))
        #expect(stack.remove(9) == nil)
        #expect(stack.items.map(\.id) == [1, 3])
    }
}

@Suite struct QuickAccessLayoutTests {
    let a = CaptureID()
    let b = CaptureID()
    let c = CaptureID()

    @Test func sizesMatchSpecSection4() {
        #expect(QuickAccessLayout.thumbnailWidth == 240)
        #expect(QuickAccessLayout.thumbnailHeight == 176)
        #expect(QuickAccessLayout.imageHeight == 136)
        #expect(QuickAccessLayout.stripHeight == 40)
        #expect(QuickAccessLayout.margin == 16)
        #expect(QuickAccessLayout.gap == 10)
    }

    @Test func bottomLeftStacksNewestAtTheBottom() {
        let anchor = Rect2D(x: 0, y: 25, width: 1512, height: 920)
        let frames = QuickAccessLayout.frames(for: [a, b, c], anchor: anchor, position: .bottomLeft)
        #expect(frames[c] == Rect2D(x: 16, y: 41, width: 240, height: 176))
        #expect(frames[b] == Rect2D(x: 16, y: 41 + 186, width: 240, height: 176))
        #expect(frames[a] == Rect2D(x: 16, y: 41 + 372, width: 240, height: 176))
    }

    @Test func bottomRightUsesTheRightEdge() {
        let anchor = Rect2D(x: 0, y: 0, width: 1512, height: 945)
        let frames = QuickAccessLayout.frames(for: [a], anchor: anchor, position: .bottomRight)
        #expect(frames[a] == Rect2D(x: 1512 - 16 - 240, y: 16, width: 240, height: 176))
    }

    @Test func aSecondDisplayWithANegativeOriginWorks() {
        // An external display left of and below the primary one, in Cocoa global points.
        let anchor = Rect2D(x: -1920, y: -1080, width: 1920, height: 1055)
        let left = QuickAccessLayout.frames(for: [a, b], anchor: anchor, position: .bottomLeft)
        #expect(left[b] == Rect2D(x: -1904, y: -1064, width: 240, height: 176))
        #expect(left[a] == Rect2D(x: -1904, y: -1064 + 186, width: 240, height: 176))
        let right = QuickAccessLayout.frames(for: [a], anchor: anchor, position: .bottomRight)
        #expect(right[a] == Rect2D(x: -16 - 240, y: -1064, width: 240, height: 176))
    }
}
