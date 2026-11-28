import AppKit
import BugeyeCore
import CaptureCore
import MacAdapters
import os

/// `CaptureShell` on AppKit: overlay windows per session, focus, sound, the alert and `os.Logger` (Capture §7, §8).
/// Overlay windows are only ever shown by `showOverlays` and keyed by `makeKey`, which the flow emits only while
/// selecting; `closeOverlays` closes them (never just hides them) and the sweep closes anything left over.
@MainActor
final class AppCaptureShell: CaptureShell {
    /// Where view events go and what views draw; set once the controller exists.
    weak var controller: CaptureController?
    /// `AppContext.screenRecordingAlert.show`.
    var presentAlert: () -> Void = {}
    /// Called for every log line too (tests).
    var onLog: ((LogCategory, String) -> Void)?

    private(set) var overlays: [SessionID: [SelectionOverlayWindow]] = [:]
    /// Every overlay window ever made and not yet closed, for the leftover sweep.
    private var openWindows: [SelectionOverlayWindow] = []
    private var previousApp: NSRunningApplication?

    func pointerLocation() -> CocoaPoint {
        let point = NSEvent.mouseLocation
        return CocoaPoint(x: point.x, y: point.y)
    }

    func showOverlays(_ session: SessionID, frames: [FrozenDisplay], mode: OverlayMode) {
        let screens = NSScreen.screens
        var windows: [SelectionOverlayWindow] = []
        for frame in frames {
            let screen = screens.first { Self.displayID($0) == frame.display.id.rawValue }
            let inset = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
            let window = SelectionOverlayWindow(session: session, display: frame.display)
            let view = SelectionOverlayView(
                session: session, display: frame.display, image: frame.image.cgImage,
                pixelWidth: frame.image.pixelWidth,
                visibleTopInset: inset)
            let display = frame.display.id
            view.render = { [weak self] in self?.controller?.overlay(for: display) }
            view.send = { [weak self] in self?.controller?.send($0) }
            window.contentView = view
            window.orderFrontRegardless()
            // Crosshair and loupe at the pointer at once, without waiting for a mouse move (design/02 §3.2).
            let mouse = NSEvent.mouseLocation
            let origin = window.frame.origin
            view.showPointer(at: NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y))
            windows.append(window)
        }
        overlays[session] = windows
        openWindows += windows
        NSCursor.crosshair.set()
    }

    func closeOverlays(_ session: SessionID) {
        for window in overlays.removeValue(forKey: session) ?? [] { close(window) }
    }

    func sweepLeftovers(keeping: SessionID?) {
        for window in openWindows where window.session != keeping {
            if window.isVisible { log(.selection, "closing a leftover overlay \(window.windowNumber)", isError: true) }
            close(window)
        }
        overlays = overlays.filter { $0.key == keeping }
    }

    private func close(_ window: SelectionOverlayWindow) {
        window.orderOut(nil)
        window.close()
        window.contentView = nil
        openWindows.removeAll { $0 === window }
    }

    func makeKey(_ session: SessionID, display: DisplayID) {
        guard let window = overlays[session]?.first(where: { $0.display == display }) else { return }
        window.makeKey()
        window.makeFirstResponder(window.contentView)
    }

    func redraw(_ session: SessionID, display: DisplayID, damage: DisplayRect?) {
        guard let window = overlays[session]?.first(where: { $0.display == display }) else { return }
        (window.contentView as? SelectionOverlayView)?.invalidate(damage)
    }

    func activateBugeye() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate()
    }

    func reactivatePreviousApp() {
        previousApp?.activate()
        previousApp = nil
    }

    func beep() { NSSound.beep() }

    func showPermissionAlert() { presentAlert() }

    func overlayWindowNumbers(_ session: SessionID) -> [Int] {
        (overlays[session] ?? []).map(\.windowNumber)
    }

    func log(_ category: LogCategory, _ message: String) {
        log(category, message, isError: false)
    }

    private func log(_ category: LogCategory, _ message: String, isError: Bool) {
        let logger = Logger(subsystem: CaptureFolders.bundleID, category: category.rawValue)
        if isError {
            logger.error("\(message, privacy: .public)")
        } else {
            logger.log("\(message, privacy: .public)")
        }
        onLog?(category, message)
    }

    static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
