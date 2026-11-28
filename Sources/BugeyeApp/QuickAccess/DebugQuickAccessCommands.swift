#if DEBUG
    import QuickAccessCore

    /// `quickAccess.stack`: the stack as one line of JSON, oldest first (contracts K23, spec §8.4).
    @MainActor
    enum DebugQuickAccessCommands {
        static let stack = "quickAccess.stack"

        static func register(_ controller: QuickAccessController, in commands: DebugCommands) {
            commands.register(stack) { [weak controller] _ in
                controller?.model.stackSnapshotJSON() ?? "[]"
            }
        }
    }
#endif
