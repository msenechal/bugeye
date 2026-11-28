import AppKit
import BugeyeTestSupport
import SwiftUI

// The fixture app (spec §5.5): a window with known content for smoke and end-to-end tests. Test-only:
// scripts/bundle.sh never copies it into Bugeye.app. Run it with `make fixture`.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .resizable],
        backing: .buffered, defer: false)
    window.title = FixtureContent.windowTitle
    window.contentView = NSHostingView(rootView: FixtureView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate()
    app.run()
}
