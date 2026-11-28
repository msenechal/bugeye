import AppKit
import BugeyeTestSupport
import SwiftUI

// The fixture app (spec §5.5): a window with known content for smoke and end-to-end tests. Test-only:
// scripts/bundle.sh never copies it into Bugeye.app. Run it with `make fixture`.

/// Opens Window ▸ Small Window: a 400 × 300 pt window for Capture's window-mode batch (Capture §9.4.2).
@MainActor
final class FixtureMenuTarget: NSObject {
    private var smallWindow: NSWindow?

    @objc func openSmallWindow(_ sender: Any?) {
        if smallWindow == nil {
            let size = FixtureContent.smallWindowSize
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = FixtureContent.smallWindowTitle
            window.isReleasedWhenClosed = false
            window.center()
            smallWindow = window
        }
        smallWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
func fixtureMainMenu(target: FixtureMenuTarget) -> NSMenu {
    let main = NSMenu()
    let app = NSMenu()
    app.addItem(
        NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    let appItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    appItem.submenu = app
    main.addItem(appItem)

    let window = NSMenu(title: FixtureContent.windowMenu)
    let small = NSMenuItem(
        title: FixtureContent.smallWindowItem, action: #selector(FixtureMenuTarget.openSmallWindow(_:)),
        keyEquivalent: "")
    small.target = target
    window.addItem(small)
    let windowItem = NSMenuItem(title: FixtureContent.windowMenu, action: nil, keyEquivalent: "")
    windowItem.submenu = window
    main.addItem(windowItem)
    return main
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let target = FixtureMenuTarget()
    app.mainMenu = fixtureMainMenu(target: target)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled, .closable, .resizable],
        backing: .buffered, defer: false)
    window.title = FixtureContent.windowTitle
    window.contentView = NSHostingView(rootView: FixtureView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate()
    withExtendedLifetime(target) { app.run() }
}
