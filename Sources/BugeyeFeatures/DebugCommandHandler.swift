#if DEBUG
    import BugeyeCore
    import Foundation

    /// The debug test channel's protocol (`design/13` §4, contracts K23): one command per line in, one line out.
    /// Every command runs on the main actor. Debug builds only; `scripts/check-release-symbols.sh` checks that
    /// release builds contain none of it.
    ///
    /// Built in: `ping`, `modules`, `hotkey <id>`, `menu <id>`, `get <key>`, `set <key> <json>`, `events`. Any other
    /// first word is looked up through `registered` (the app's `DebugCommands`, where epics register their own).
    @MainActor
    public final class DebugCommandHandler {
        public static let builtInCommands = ["ping", "modules", "hotkey", "menu", "get", "set", "events"]
        /// How many events `events` keeps.
        public static let eventLimit = 50

        public let moduleIDs: [String]
        private let router: ActionRouter
        private let settings: any SettingsStore
        private let registered: @MainActor (String) -> (@MainActor (String) -> String)?
        private var recent: [CaptureEvent] = []
        private var subscription: CaptureSubscription?

        public init(
            moduleIDs: [String], router: ActionRouter, settings: any SettingsStore, bus: CaptureEventBus,
            registered: @escaping @MainActor (String) -> (@MainActor (String) -> String)? = { _ in nil }
        ) {
            self.moduleIDs = moduleIDs
            self.router = router
            self.settings = settings
            self.registered = registered
            subscription = bus.subscribe { [weak self] event in
                guard let self else { return }
                self.recent.append(event)
                if self.recent.count > Self.eventLimit { self.recent.removeFirst(self.recent.count - Self.eventLimit) }
            }
        }

        /// Answers one line. Surrounding whitespace and the line ending are ignored.
        public func respond(to line: String) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let command: String
            let arguments: String
            if let space = trimmed.firstIndex(where: \.isWhitespace) {
                command = String(trimmed[..<space])
                arguments = trimmed[space...].trimmingCharacters(in: .whitespaces)
            } else {
                command = trimmed
                arguments = ""
            }
            switch command {
            case "ping": return "pong"
            case "modules": return moduleIDs.joined(separator: ",")
            case "hotkey":
                guard !arguments.isEmpty else { return "error: usage: hotkey <id>" }
                return router.performHotkey(arguments) ? "ok" : "error: no hotkey \(arguments)"
            case "menu":
                guard !arguments.isEmpty else { return "error: usage: menu <id>" }
                return router.performMenuItem(arguments) ? "ok" : "error: no menu item \(arguments)"
            case "get":
                guard !arguments.isEmpty else { return "error: usage: get <key>" }
                return settings.value(forKey: arguments).map(Self.json) ?? "null"
            case "set":
                return set(arguments)
            case "events":
                return events()
            default:
                if let handler = registered(command) { return handler(arguments) }
                return "error: unknown command \(trimmed)"
            }
        }

        private func set(_ arguments: String) -> String {
            guard let space = arguments.firstIndex(where: \.isWhitespace) else {
                return "error: usage: set <key> <json>"
            }
            let key = String(arguments[..<space])
            let text = arguments[space...].trimmingCharacters(in: .whitespaces)
            if text == "null" {
                settings.setValue(nil, forKey: key)
                return "ok"
            }
            guard let value = Self.value(fromJSON: text) else { return "error: invalid value \(text)" }
            settings.setValue(value, forKey: key)
            return "ok"
        }

        private struct EventLine: Encodable {
            let change: String
            let id: String
            let file: String
            let origin: String
        }

        private func events() -> String {
            let lines = recent.map {
                EventLine(
                    change: $0.change.rawValue, id: $0.item.id.description, file: $0.item.fileURL.lastPathComponent,
                    origin: $0.origin)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(lines)).map { String(decoding: $0, as: UTF8.self) } ?? "error: encoding failed"
        }

        /// Plan P12: strings JSON-quoted, bools, ints as digits, doubles always with a fraction or exponent.
        static func json(_ value: SettingValue) -> String {
            switch value {
            case .string(let string):
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                return (try? encoder.encode(string)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
            case .bool(let bool): return bool ? "true" : "false"
            case .int(let int): return String(int)
            case .double(let double): return double.description
            }
        }

        static func value(fromJSON text: String) -> SettingValue? {
            switch text {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: break
            }
            if text.hasPrefix("\"") {
                return (try? JSONDecoder().decode(String.self, from: Data(text.utf8))).map { .string($0) }
            }
            if let int = Int(text) { return .int(int) }
            if let double = Double(text), double.isFinite { return .double(double) }
            return nil
        }
    }
#endif
