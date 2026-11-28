#if DEBUG
    import BugeyeFeatures

    /// The debug channel's registered commands (K23, design/13 §4). Every command runs on the main actor and
    /// answers one line. Epics register theirs from their own folders, inside `#if DEBUG`.
    @MainActor
    final class DebugCommands {
        private var handlers: [String: @MainActor (String) -> String] = [:]
        /// Prefixes registered twice, or naming a built-in command; launch fails unless this is empty.
        private(set) var duplicates: [String] = []

        /// `prefix` is the command's first word, e.g. "quickAccess.stack"; `handler` gets the rest of the line.
        /// A duplicate prefix, or one of the built-in commands, is recorded and fails launch, as a router id does.
        func register(_ prefix: String, _ handler: @escaping @MainActor (_ arguments: String) -> String) {
            guard !DebugCommandHandler.builtInCommands.contains(prefix), handlers[prefix] == nil else {
                return duplicates.append(prefix)
            }
            handlers[prefix] = handler
        }

        func handler(for prefix: String) -> (@MainActor (String) -> String)? {
            handlers[prefix]
        }
    }
#endif
