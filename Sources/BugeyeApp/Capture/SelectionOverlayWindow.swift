import AppKit
import BugeyeCore
import CaptureCore

/// One display's overlay (design/02 §2.8, Capture §5.2): borderless, above everything, on every Space, never
/// released by `close()` so the shell decides when it goes. Finishing **closes** it; it is never only hidden.
@MainActor
final class SelectionOverlayWindow: NSWindow {
    let session: SessionID
    let display: DisplayID

    init(session: SessionID, display: DisplayInfo) {
        self.session = session
        self.display = display.id
        let frame = NSRect(
            x: display.frame.minX, y: display.frame.minY, width: display.frame.width, height: display.frame.height)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        Self.configure(self)
        setFrame(frame, display: false)
    }

    /// The window properties of design/02 §2.8.
    static func configure(_ window: NSWindow) {
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
