import BugeyeCore
import CaptureCore
import Testing

@Suite struct WindowHitTestTests {
    func window(_ id: UInt32, pid: Int32 = 10, _ rect: Rect2D, layer: Int = 0, alpha: Double = 1) -> WindowInfo {
        WindowInfo(id: WindowID(id), ownerPID: pid, bounds: rect, layer: layer, alpha: alpha)
    }

    @Test func theFrontmostNormalWindowOfAnotherAppUnderThePointerWins() {
        let windows = [
            window(1, Rect2D(x: 0, y: 0, width: 50, height: 50), layer: 25),  // menu bar extra
            window(2, pid: 99, Rect2D(x: 0, y: 0, width: 100, height: 100)),  // Bugeye's own
            window(3, Rect2D(x: 0, y: 0, width: 100, height: 100), alpha: 0),  // invisible
            window(4, Rect2D(x: 0, y: 0, width: 100, height: 100)),
            window(5, Rect2D(x: 0, y: 0, width: 200, height: 200)),
        ]
        #expect(WindowHitTest.topmost(at: QuartzPoint(x: 10, y: 10), in: windows, excludingPID: 99)?.id == WindowID(4))
        #expect(
            WindowHitTest.topmost(at: QuartzPoint(x: 150, y: 150), in: windows, excludingPID: 99)?.id == WindowID(5))
        #expect(WindowHitTest.topmost(at: QuartzPoint(x: 250, y: 10), in: windows, excludingPID: 99) == nil)
    }

    @Test func windowsOnADisplayLeftOfThePrimaryAreHitInQuartzSpace() {
        let windows = [window(1, Rect2D(x: -800, y: -300, width: 400, height: 300))]
        #expect(
            WindowHitTest.topmost(at: QuartzPoint(x: -700, y: -100), in: windows, excludingPID: 0)?.id == WindowID(1))
    }

    @Test func theDisplayHoldingTheWindowsCentre() {
        let displays = [
            (DisplayID(1), QuartzRect(x: 0, y: 0, width: 1440, height: 900)),
            (DisplayID(2), QuartzRect(x: -1920, y: -480, width: 1920, height: 1080)),
        ]
        #expect(
            WindowHitTest.display(containingCentreOf: QuartzRect(x: -100, y: 0, width: 400, height: 300), in: displays)
                == DisplayID(1))
        #expect(
            WindowHitTest.display(containingCentreOf: QuartzRect(x: -500, y: 0, width: 400, height: 300), in: displays)
                == DisplayID(2))
        #expect(
            WindowHitTest.display(containingCentreOf: QuartzRect(x: 5000, y: 0, width: 10, height: 10), in: displays)
                == nil)
    }
}
