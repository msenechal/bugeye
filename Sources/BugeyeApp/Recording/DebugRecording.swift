#if DEBUG
    import BugeyeCore

    /// `recording.state`: the flow's state, one line (contracts K23), for the Mac batch.
    @MainActor
    enum DebugRecording {
        static func register(_ context: AppContext, controller: RecordingController) {
            context.debugCommands.register("recording.state") { [weak controller] _ in
                controller?.stateDescription ?? "none"
            }
        }
    }
#endif
