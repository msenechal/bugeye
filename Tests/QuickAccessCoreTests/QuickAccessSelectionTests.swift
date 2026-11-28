import BugeyeCore
import QuickAccessCore
import Testing

@Suite struct QuickAccessSelectionTests {
    let a = CaptureID()
    let b = CaptureID()
    let c = CaptureID()

    @Test func toggleAddsAndRemoves() {
        var selection = QuickAccessSelection()
        #expect(selection.isEmpty)
        selection.toggle(a)
        #expect(selection.contains(a))
        #expect(selection.host == a)
        selection.toggle(a)
        #expect(selection.isEmpty)
        #expect(selection.host == nil)
    }

    @Test func hostIsTheLastShiftClickedStillSelected() {
        var selection = QuickAccessSelection()
        selection.toggle(a)
        selection.toggle(b)
        selection.toggle(c)
        #expect(selection.host == c)
        selection.toggle(c)
        #expect(selection.host == b)
        selection.toggle(a)
        selection.toggle(a)
        #expect(selection.host == a)
        selection.remove(a)
        #expect(selection.host == b)
    }

    @Test func orderedFollowsTheStackNotTheClicks() {
        var selection = QuickAccessSelection()
        selection.toggle(c)
        selection.toggle(a)
        #expect(selection.ordered(byStack: [a, b, c]) == [a, c])
    }

    @Test func clearEmptiesIt() {
        var selection = QuickAccessSelection()
        selection.toggle(a)
        selection.toggle(b)
        selection.clear()
        #expect(selection.isEmpty)
        #expect(selection.count == 0)
    }
}
