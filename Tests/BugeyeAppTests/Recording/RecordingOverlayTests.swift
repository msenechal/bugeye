import AppKit
import BugeyeCore
import BugeyeTestSupport
import RecordingCore
import Testing

@testable import BugeyeApp

@MainActor @Suite struct RecordingOverlayTests {
    final class Clock {
        var now = 100.0
    }

    /// PR #24 review I7: a click in Quartz points rings at its point in the area, on a primary-display area and on
    /// one with a negative origin; the timer stops by itself once the ring is done, on an empty frame.
    @Test(arguments: [
        // Cocoa area (100, 600, 400, 300) with a 1000 pt primary: Quartz top-left (100, 100).
        (CGRect(x: 100, y: 600, width: 400, height: 300), Point2D(x: 150, y: 120)),
        // Left of and above the primary: Quartz top-left (-1500, -300).
        (CGRect(x: -1500, y: 1000, width: 400, height: 300), Point2D(x: -1450, y: -280)),
    ])
    func clicksRingAtTheirAreaPointAndTheTimerStopsWhenDone(area: CGRect, click: Point2D) throws {
        let clock = Clock()
        let overlay = RecordingOverlay(measurer: FakeTextMeasurer(), primaryHeight: { 1000 }, now: { clock.now })
        overlay.start(area: area, clicks: true, keys: false, showAllKeys: false)
        overlay.click(.left, at: click)
        var expected = ClickRings()
        expected.click(.left, at: Point2D(x: 50, y: 20), time: 100)
        #expect(overlay.rings == expected)
        #expect(overlay.isAnimating)
        clock.now = 100 + ClickRings.duration / 2
        overlay.frame()
        #expect(overlay.isAnimating)
        clock.now = 100 + ClickRings.duration + 0.01
        overlay.frame()
        #expect(!overlay.isAnimating)
        let lastFrame = overlay.drawnLists
        #expect(lastFrame.count == 1)
        let empty = lastFrame.first?.commands.contains { if case .strokePath = $0 { true } else { false } } == false
        #expect(empty)
        overlay.stop()
        #expect(overlay.windowIDs.isEmpty)
    }

    @Test func keysFollowTheShowAllKeysRuleAndRepeatsAreIgnored() {
        let clock = Clock()
        let overlay = RecordingOverlay(measurer: FakeTextMeasurer(), primaryHeight: { 1000 }, now: { clock.now })
        overlay.start(area: CGRect(x: 0, y: 0, width: 400, height: 300), clicks: false, keys: true, showAllKeys: false)
        overlay.key(KeyPress(keyCode: 0, characters: "a", modifiers: []))
        #expect(!overlay.isAnimating)
        overlay.key(KeyPress(keyCode: 1, characters: "s", modifiers: [.cmd], isRepeat: true))
        #expect(!overlay.isAnimating)
        overlay.key(KeyPress(keyCode: 1, characters: "s", modifiers: [.cmd]))
        #expect(overlay.isAnimating)
        overlay.stop()
    }

    @Test func theViewDrawsRingsAndBadgeAsDisplayLists() {
        let view = OverlayView(measurer: FakeTextMeasurer())
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        view.rings.click(.left, at: Point2D(x: 50, y: 50), time: 0)
        view.badge.press("⌘ S", at: 0)
        view.time = 0.1
        let lists = view.lists()
        #expect(lists.count == 2)
        let balanced = lists.allSatisfy { $0.isBalanced }
        #expect(balanced)
        #expect(lists[0].size == Size2D(width: 400, height: 300))
        #expect(view.isFlipped)
    }

    @Test func theWindowIsClickThroughAboveEverything() {
        let window = OverlayWindow(view: NSView())
        #expect(window.ignoresMouseEvents)
        #expect(window.level == .screenSaver)
        #expect(!window.isOpaque)
    }
}
