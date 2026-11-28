import BugeyeCore
import Foundation

/// Which window is under the pointer in window mode (design/02 §2.9).
public enum WindowHitTest {
    /// The first window, front to back, with layer 0, alpha > 0, another process id, and bounds containing `point`.
    public static func topmost(at point: QuartzPoint, in windows: [WindowInfo], excludingPID: Int32) -> WindowInfo? {
        windows.first {
            $0.layer == 0 && $0.alpha > 0 && $0.ownerPID != excludingPID
                && QuartzRect($0.bounds).contains(point)
        }
    }

    /// The display whose Quartz frame holds the window's centre, or nil when it is on no display.
    public static func display(containingCentreOf window: QuartzRect, in displays: [(DisplayID, QuartzRect)])
        -> DisplayID?
    {
        displays.first { $0.1.contains(window.centre) }?.0
    }
}
