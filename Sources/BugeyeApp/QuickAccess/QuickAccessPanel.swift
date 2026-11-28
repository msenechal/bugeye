import AppKit

/// One thumbnail's floating panel (spec §4, `design/02` §2.12): non-activating, borderless, above other apps, on
/// every Space and over full-screen apps, dark. It can become key, so it receives Esc, but never main. Dismissal
/// closes it.
@MainActor
final class QuickAccessPanel: NSPanel {
    static let escapeKeyCode: UInt16 = 53

    /// Esc, as `keyDown` 53 or as `cancelOperation(_:)` (the hosted SwiftUI view sends the latter).
    var onEscape: (@MainActor () -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
