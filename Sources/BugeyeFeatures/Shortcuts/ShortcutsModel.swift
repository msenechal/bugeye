import BugeyeCore

/// A launch notice (Capture §5.6).
public struct ShortcutNotice: Hashable, Sendable {
    public var title: String
    public var body: String
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The Shortcuts pane's model and the global-hotkey registrations (Capture §5.6, C5, C27). The registrar
/// registers every module's `HotkeySpec`; a press calls `onPress(id)` (the wiring routes it through `ActionRouter`).
@MainActor
public final class ShortcutsModel {
    public enum Button: Hashable, Sendable { case tryAgain, keyboardShortcuts }

    /// At most one under a row, in this priority.
    public enum Message: Hashable, Sendable {
        case taken(KeyCombo)
        case macOSConflict(KeyCombo)
        case duplicate(KeyCombo, title: String)
        case invalid

        public var text: String {
            switch self {
            case .taken(let combo): ShortcutStrings.taken(combo.description)
            case .macOSConflict(let combo): ShortcutStrings.macOSConflict(combo.description)
            case .duplicate(let combo, let title): ShortcutStrings.duplicate(combo.description, title: title)
            case .invalid: ShortcutStrings.invalid
            }
        }

        public var button: Button? {
            switch self {
            case .taken: .tryAgain
            case .macOSConflict: .keyboardShortcuts
            case .duplicate, .invalid: nil
            }
        }
    }

    public struct Row: Hashable, Sendable {
        public var spec: HotkeySpec
        /// The stored binding; nil when cleared.
        public var combo: KeyCombo?
        public var registered: Bool
        public var isRecording: Bool
        public var message: Message?
    }

    public private(set) var rows: [Row]
    /// Called after every change, for the view.
    public var onChange: (() -> Void)?

    private let store: any SettingsStore
    private let registrar: any HotkeyRegistrar
    private let systemCombos: () -> Set<KeyCombo>
    private let onPress: (String) -> Void
    private let onRegistration: (String, Bool) -> Void
    private let log: (String) -> Void
    /// The typed-combo messages (duplicate, invalid), until the row's next action.
    private var typedMessages: [String: Message] = [:]
    private var system: Set<KeyCombo> = []

    public init(
        specs: [HotkeySpec], store: any SettingsStore, registrar: any HotkeyRegistrar,
        systemCombos: @escaping () -> Set<KeyCombo>, onPress: @escaping (String) -> Void,
        onRegistration: @escaping (String, Bool) -> Void, log: @escaping (String) -> Void
    ) {
        self.store = store
        self.registrar = registrar
        self.systemCombos = systemCombos
        self.onPress = onPress
        self.onRegistration = onRegistration
        self.log = log
        rows = specs.map {
            Row(spec: $0, combo: HotkeyBindings.current($0, in: store), registered: true, isRecording: false)
        }
    }

    /// What a row's shortcut field shows.
    public func fieldText(_ row: Row) -> String {
        if row.isRecording { return ShortcutStrings.typeAShortcut }
        guard let combo = row.combo, row.registered else { return ShortcutStrings.none }
        return combo.description
    }

    /// Registers every binding: at launch (an `onLaunch` step) and from the pane's Try Again on any row.
    public func registerAll() {
        system = systemCombos()
        // Release every row first, so rows can swap keys (Restore Defaults) without one refusing the other's.
        for row in rows { registrar.unregister(row.spec.id) }
        for index in rows.indices { register(index) }
        changed()
    }

    /// Starts recording into a row. Every global hotkey is released meanwhile: Carbon takes a registered key before
    /// the app sees it, so typing ⇧⌘3 would capture instead of reaching the field. Every way out of recording
    /// (a combo, Esc, Delete, `stopRecording`) registers them again. Releasing isn't reported to `onRegistration`.
    public func startRecording(_ id: String) {
        guard let index = index(id) else { return }
        for row in rows { registrar.unregister(row.spec.id) }
        for i in rows.indices { rows[i].isRecording = i == index }
        typedMessages[id] = nil
        refreshMessage(index)
        changed()
    }

    /// The next combo typed while recording. Invalid or duplicate combos aren't saved.
    public func typed(_ combo: KeyCombo, for id: String) {
        guard let index = index(id) else { return }
        if !combo.isValidHotkey {
            typedMessages[id] = .invalid
        } else if let other = rows.first(where: { $0.spec.id != id && $0.combo == combo }) {
            typedMessages[id] = .duplicate(combo, title: other.spec.title)
        } else {
            typedMessages[id] = nil
            store.setValue(.string(combo.description), forKey: rows[index].spec.settingKey)
        }
        endRecording()
    }

    /// Esc while recording: the old combo stays.
    public func escapeTyped(_ id: String) {
        guard index(id) != nil else { return }
        endRecording()
    }

    /// Delete while recording: the binding is cleared.
    public func deleteTyped(_ id: String) {
        guard let index = index(id) else { return }
        typedMessages[id] = nil
        store.setValue(.string(HotkeyBindings.cleared), forKey: rows[index].spec.settingKey)
        endRecording()
    }

    /// A row's field lost focus, or the pane closed (nil): that recording ends with nothing changed. A field that
    /// resigns after another row started recording leaves the new recording alone.
    public func stopRecording(_ id: String? = nil) {
        guard rows.contains(where: { $0.isRecording && (id == nil || $0.spec.id == id) }) else { return }
        endRecording()
    }

    private func endRecording() {
        for i in rows.indices { rows[i].isRecording = false }
        registerAll()
    }

    public func tryAgain(_ id: String) {
        guard let index = index(id) else { return }
        system = systemCombos()
        register(index)
        changed()
    }

    public func restoreDefaults() {
        typedMessages = [:]
        for index in rows.indices {
            rows[index].isRecording = false
            store.setValue(nil, forKey: rows[index].spec.settingKey)
        }
        registerAll()
    }

    /// The notices after `registerAll` at launch: macOS conflicts, then taken keys.
    public func launchNotices() -> [ShortcutNotice] {
        var notices: [ShortcutNotice] = []
        let conflicts = rows.compactMap { row in row.combo.flatMap { system.contains($0) ? $0.description : nil } }
        if !conflicts.isEmpty {
            notices.append(
                ShortcutNotice(
                    title: ShortcutStrings.macOSNoticeTitle, body: ShortcutStrings.macOSNoticeBody(conflicts)))
        }
        let taken = rows.filter { !$0.registered }.compactMap { $0.combo?.description }
        if !taken.isEmpty {
            notices.append(
                ShortcutNotice(title: ShortcutStrings.takenNoticeTitle, body: ShortcutStrings.takenNoticeBody(taken)))
        }
        return notices
    }

    // MARK: Private

    private func index(_ id: String) -> Int? { rows.firstIndex { $0.spec.id == id } }

    private func register(_ index: Int) {
        let spec = rows[index].spec
        let combo = HotkeyBindings.current(spec, in: store)
        rows[index].combo = combo
        guard let combo else {
            registrar.unregister(spec.id)
            rows[index].registered = true
            onRegistration(spec.id, true)
            refreshMessage(index)
            return
        }
        let id = spec.id
        let onPress = self.onPress
        let ok = registrar.register(id, key: combo.globalKey) { onPress(id) }
        rows[index].registered = ok
        onRegistration(id, ok)
        log("\(ok ? "registered" : "taken") \(id) \(combo.description)")
        if system.contains(combo) { log("macOS conflict \(combo.description)") }
        refreshMessage(index)
    }

    private func refreshMessage(_ index: Int) {
        let row = rows[index]
        if let combo = row.combo, !row.registered {
            rows[index].message = .taken(combo)
        } else if let combo = row.combo, system.contains(combo) {
            rows[index].message = .macOSConflict(combo)
        } else {
            rows[index].message = typedMessages[row.spec.id]
        }
    }

    private func changed() { onChange?() }
}
