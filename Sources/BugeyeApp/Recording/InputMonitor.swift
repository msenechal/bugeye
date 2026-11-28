import AppKit
import BugeyeCore
import RecordingCore

/// `NSEvent` → timeline input (§7), pure so it can be tested with synthesized events.
enum InputTranslation {
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<TimelineModifier> {
        var set: Set<TimelineModifier> = []
        if flags.contains(.control) { set.insert(.ctrl) }
        if flags.contains(.option) { set.insert(.opt) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.cmd) }
        return set
    }

    /// Cocoa global (bottom-left of the primary display, y up) → Quartz global (top-left, y down).
    static func quartz(_ cocoa: CGPoint, primaryHeight: CGFloat) -> Point2D {
        Point2D(x: cocoa.x, y: primaryHeight - cocoa.y)
    }

    static func button(_ type: NSEvent.EventType) -> TimelineButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        case .otherMouseDown, .otherMouseUp: .other
        default: nil
        }
    }

    /// Clicks and scrolls; nil for anything else.
    static func input(for event: NSEvent, primaryHeight: CGFloat) -> TimelineInput? {
        let point = quartz(event.locationInWindow, primaryHeight: primaryHeight)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let button = button(event.type) else { return nil }
            return .down(button, point, clicks: event.clickCount)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let button = button(event.type) else { return nil }
            return .up(button, point)
        case .scrollWheel:
            // Line-based wheels report lines; points are what the timeline stores (≈ 10 pt a line).
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            return .scroll(point, dx: event.scrollingDeltaX * factor, dy: event.scrollingDeltaY * factor)
        default:
            return nil
        }
    }

    /// A key-down as the formatter needs it: the key's character with no modifiers in the current layout.
    static func keyPress(for event: NSEvent) -> KeyPress? {
        guard event.type == .keyDown else { return nil }
        return KeyPress(
            keyCode: event.keyCode, characters: event.characters(byApplyingModifiers: []),
            modifiers: modifiers(event.modifierFlags), isRepeat: event.isARepeat)
    }
}

/// Global monitors for clicks, scrolls and keys, a 30 Hz cursor sampler and a focus watcher (§7.2). Global
/// monitors don't see events in Bugeye's own windows, so the bar and the bubble neither ring nor reach the
/// timeline. Keys need Accessibility (V13); nothing here needs Input Monitoring.
@MainActor
final class InputMonitor {
    struct Sinks {
        /// Every input, with its host time (seconds; the clock the stream stamps samples with).
        var input: @MainActor (TimelineInput, Double) -> Void = { _, _ in }
        var key: @MainActor (KeyPress, Double) -> Void = { _, _ in }
    }

    private let sinks: Sinks
    private var monitors: [Any] = []
    private var sampler: Timer?
    private var focusTimer: Timer?
    private var lastFocus: (pid: pid_t, window: CGWindowID?)?
    private var activation: NSObjectProtocol?

    init(sinks: Sinks) {
        self.sinks = sinks
    }

    isolated deinit {
        stop()
    }

    func start(keys: Bool) {
        stop()
        let mouse: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: mouse,
            handler: { [weak self] event in
                let host = event.timestamp
                MainActor.assumeIsolated { self?.handleMouse(event, host: host) }
            })
        {
            monitors.append(monitor)
        }
        if keys,
            let monitor = NSEvent.addGlobalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak self] event in
                    let host = event.timestamp
                    MainActor.assumeIsolated {
                        guard let press = InputTranslation.keyPress(for: event) else { return }
                        self?.sinks.key(press, host)
                    }
                })
        {
            monitors.append(monitor)
        }
        let sampler = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleCursor() }
        }
        RunLoop.main.add(sampler, forMode: .common)
        self.sampler = sampler
        let focus = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocus() }
        }
        RunLoop.main.add(focus, forMode: .common)
        focusTimer = focus
        // §7.2 "on app activation": stamped when it happens, not at the next poll.
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocus() }
        }
        checkFocus()
    }

    /// Sends the focused app and window again: the controller calls it once the timeline has started, since the
    /// line sent at `start` comes before the first frame and is dropped (PR #22 review I8).
    func resendFocus() {
        lastFocus = nil
        checkFocus()
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        sampler?.invalidate()
        sampler = nil
        focusTimer?.invalidate()
        focusTimer = nil
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        lastFocus = nil
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func handleMouse(_ event: NSEvent, host: Double) {
        guard let input = InputTranslation.input(for: event, primaryHeight: primaryHeight) else { return }
        sinks.input(input, host)
    }

    private func sampleCursor() {
        let point = InputTranslation.quartz(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        sinks.input(.move(point), HostClock.now())
    }

    /// The active app, and its frontmost window (on activation, and checked twice a second). No window title
    /// (V14). Bugeye itself is skipped: its alerts activate it, and it isn't what was recorded (review M9).
    private func checkFocus() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let pid = app.processIdentifier
        let window = Self.frontWindow(of: pid)
        if let last = lastFocus, last.pid == pid, last.window == window?.id { return }
        lastFocus = (pid, window?.id)
        sinks.input(
            .focus(
                app: app.bundleIdentifier ?? "", name: app.localizedName ?? "", window: window.map { WindowID($0.id) },
                frame: window?.frame), HostClock.now())
    }

    private static func frontWindow(of pid: pid_t) -> (id: CGWindowID, frame: Rect2D)? {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        for entry in list {
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { continue }
            return (id, Rect2D(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height))
        }
        return nil
    }
}
