import BugeyeCore
import CaptureCore
import Foundation

/// Records what the controller asked the shell to do. Overlay windows are numbered from 100.
@MainActor
final class FakeCaptureShell: CaptureShell {
    var pointer = CocoaPoint(x: 700, y: 450)
    private(set) var calls: [String] = []
    private(set) var open: [SessionID: [Int]] = [:]
    private(set) var shown: [(SessionID, [DisplayID], OverlayMode)] = []
    private(set) var logs: [(LogCategory, String)] = []
    private(set) var alerts = 0
    private(set) var beeps = 0
    private var nextWindow = 100

    func pointerLocation() -> CocoaPoint { pointer }

    func showOverlays(_ session: SessionID, frames: [FrozenDisplay], mode: OverlayMode) {
        calls.append("show \(session)")
        shown.append((session, frames.map(\.display.id), mode))
        open[session] = frames.map { _ in
            defer { nextWindow += 1 }
            return nextWindow
        }
    }

    /// Runs once inside the next `closeOverlays`, as a re-entrant call from the shell would.
    var duringClose: (() -> Void)?

    func closeOverlays(_ session: SessionID) {
        calls.append("close \(session)")
        let hook = duringClose
        duringClose = nil
        hook?()
        open[session] = nil
    }

    func sweepLeftovers(keeping: SessionID?) {
        calls.append("sweep")
        open = open.filter { $0.key == keeping }
    }

    func makeKey(_ session: SessionID, display: DisplayID) { calls.append("key \(session) \(display.rawValue)") }
    func redraw(_ session: SessionID, display: DisplayID, damage: DisplayRect?) {}
    func activateBugeye() { calls.append("activate") }
    func reactivatePreviousApp() { calls.append("reactivate") }
    func beep() { beeps += 1 }
    func showPermissionAlert() { alerts += 1 }
    func overlayWindowNumbers(_ session: SessionID) -> [Int] { open[session] ?? [] }
    func log(_ category: LogCategory, _ message: String) { logs.append((category, message)) }

    func logged(_ category: LogCategory) -> [String] { logs.filter { $0.0 == category }.map(\.1) }
}
