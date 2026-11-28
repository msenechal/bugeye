import AppKit
import BugeyeCore
import QuickAccessCore
import UniformTypeIdentifiers

/// The system calls Quick Access makes outside its panels (spec Q7: effects, not ports). Tests replace them.
@MainActor
struct QuickAccessSystem {
    /// Moves a saved capture to the Trash. Runs off the main actor.
    var trash: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
    /// Removes a temp capture. Runs off the main actor.
    var remove: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.removeItem(at: url)
    }
    var reveal: @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    /// Gives the keyboard back to the app the user was typing in.
    var activateFrontmostApp: @MainActor () -> Void = {
        NSWorkspace.shared.frontmostApplication?.activate()
    }
    /// Makes a remembered Bugeye window key again; false when it's gone.
    var restoreKey: @MainActor (WindowToken) -> Bool = { token in
        guard let window = NSApplication.shared.window(withWindowNumber: token.rawValue) else { return false }
        window.makeKey()
        return true
    }
    var bugeyeIsActive: @MainActor () -> Bool = { NSApplication.shared.isActive }
    /// Bugeye's key window when Bugeye is active and that window isn't a thumbnail.
    var bugeyeKeyWindow: @MainActor () -> WindowToken? = {
        let app = NSApplication.shared
        guard app.isActive, let window = app.keyWindow, !(window is QuickAccessPanel) else { return nil }
        return WindowToken(window.windowNumber)
    }
    /// The save panel: name = the file's name, starting folder = its folder, its content type. `completion` gets
    /// the chosen URL, or nil for Cancel.
    var showSavePanel:
        @MainActor (_ name: String, _ directory: URL, _ completion: @escaping @MainActor (URL?) -> Void)
            -> Void = { name, directory, completion in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.directoryURL = directory
                let ext = (name as NSString).pathExtension
                if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
                    panel.allowedContentTypes = [type]
                }
                // The panel needs Bugeye active; the app the user was in gets the keyboard back after it
                // (final review of #11, M6).
                let previous = NSWorkspace.shared.frontmostApplication
                NSApplication.shared.activate()
                panel.begin { response in
                    MainActor.assumeIsolated {
                        completion(response == .OK ? panel.url : nil)
                        if let previous, previous != NSRunningApplication.current { previous.activate() }
                    }
                }
            }
    /// The visible frame of the display under the pointer, in Cocoa global points.
    var anchorUnderPointer: @MainActor () -> Rect2D = {
        let point = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? .zero
        return Rect2D(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }
}
