#if DEBUG
    import AppKit
    import BugeyeCore
    import CaptureCore

    /// The Capture epic's debug commands (K23) for the Mac batch.
    @MainActor
    enum DebugCaptureCommands {
        static func register(_ commands: DebugCommands, controller: CaptureController) {
            // `capture.state` → `idle` or `<phase> <session>`.
            commands.register("capture.state") { _ in
                guard let session = controller.session else { return "idle" }
                return "\(controller.phase) \(session)"
            }
            // `capture.click <display id> <x> <y>`: a click (down and up) at display-local points (top-left) on the
            // live overlay, so the batch can pick a window or drag nothing without a real mouse (Capture §9.4.2).
            commands.register("capture.click") { arguments in
                let parts = arguments.split(separator: " ")
                guard parts.count == 3, let id = UInt32(parts[0]), let x = Double(parts[1]), let y = Double(parts[2])
                else { return "error: usage: capture.click <display id> <x> <y>" }
                guard let session = controller.session, controller.phase == .selecting else {
                    return "error: no selection is up"
                }
                guard
                    let screen = NSScreen.screens.first(where: { AppCaptureShell.displayID($0) == id })
                else { return "error: no display \(id)" }
                let point = DisplayPoint(x: x, y: y).viewPoint(displayHeight: screen.frame.height)
                controller.send(.mouseDown(session, DisplayID(id), point, Modifiers()))
                controller.send(.mouseUp(session, DisplayID(id), point))
                return "ok"
            }
        }
    }
#endif
