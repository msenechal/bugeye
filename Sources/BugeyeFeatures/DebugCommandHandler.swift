#if DEBUG
    import Foundation

    /// The debug test channel's protocol (`design/13` §4): one command per line in, one line out.
    /// Debug builds only; `scripts/check-release-symbols.sh` checks that release builds contain none of it.
    public struct DebugCommandHandler: Sendable {
        public let moduleIDs: [String]

        public init(moduleIDs: [String]) {
            self.moduleIDs = moduleIDs
        }

        /// `ping` → `pong`; `modules` → the registered module ids, comma-separated; anything else → an error
        /// line. Surrounding whitespace and the line ending are ignored.
        public func respond(to line: String) -> String {
            switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "ping": "pong"
            case "modules": moduleIDs.joined(separator: ",")
            case let other: "error: unknown command \(other)"
            }
        }
    }
#endif
