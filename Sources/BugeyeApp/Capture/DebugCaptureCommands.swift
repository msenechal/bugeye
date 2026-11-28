#if DEBUG
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
        }
    }
#endif
