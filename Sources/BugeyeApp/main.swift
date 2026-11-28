import AppKit

// Menu-bar agent: no Dock icon (Info.plist also sets LSUIElement). NSApplication.delegate is weak, so
// withExtendedLifetime keeps the delegate alive for the whole run.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
