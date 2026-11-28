import BugeyeCore

extension KeyCombo {
    /// Parses `description` ("⇧⌘3", "⌥⇧⌘3"): modifier symbols (any order, each once), then one character, stored
    /// lowercased (plan P9). Nil for anything else.
    public init?(description: String) {
        var modifiers: Set<KeyModifier> = []
        var rest = Substring(description)
        while let first = rest.first, let modifier = KeyModifier.allCases.first(where: { $0.symbol == String(first) }) {
            guard modifiers.insert(modifier).inserted else { return nil }
            rest = rest.dropFirst()
        }
        guard rest.count == 1, let key = rest.first, !key.isWhitespace else { return nil }
        self.init(String(key).lowercased(), modifiers)
    }

    /// A letter or digit with at least one of ⌘, ⌥ or ⌃ (Capture §5.6).
    public var isValidHotkey: Bool {
        guard key.count == 1, let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1,
            scalar.isASCII, ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar))
        else { return false }
        return !modifiers.isDisjoint(with: [.command, .option, .control])
    }
}

/// The user's hotkey bindings, stored by Capture's Shortcuts pane as a `KeyCombo` description.
public enum HotkeyBindings {
    /// The stored value of a cleared binding.
    public static let cleared = "none"

    /// The user's binding: nil when cleared; the default when the value is missing or not a valid hotkey.
    public static func current(_ spec: HotkeySpec, in store: any SettingsStore) -> KeyCombo? {
        guard case .string(let text)? = store.value(forKey: spec.settingKey) else { return spec.defaultKey }
        if text == cleared { return nil }
        guard let combo = KeyCombo(description: text), combo.isValidHotkey else { return spec.defaultKey }
        return combo
    }
}
