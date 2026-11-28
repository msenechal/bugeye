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

    @Test func clicksRingAtTheirAreaPointAndTheTimerStopsWhenDone() throws {
        let clock = Clock()
        let overlay = RecordingOverlay(measurer: FakeTextMeasurer(), primaryHeight: { 1000 }, now: { clock.now })
        // Cocoa area (100, 600, 400, 300): its Quartz top-left is (100, 100).
        overlay.start(
            area: CGRect(x: 100, y: 600, width: 400, height: 300), clicks: true, keys: false, showAllKeys: false)
        #expect(overlay.windowIDs.count == 1)
        overlay.click(.left, at: Point2D(x: 150, y: 120))
        #expect(overlay.isAnimating)
        overlay.stop()
        #expect(!overlay.isAnimating)
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
