import BugeyeCore

/// macOS's own screenshot shortcuts that are on (Capture C13, plan P10).
public enum ShortcutConflicts {
    /// The `AppleSymbolicHotKeys` screenshot entries and their default keys.
    public static let screenshotEntries: [(number: Int, key: KeyCombo)] = [
        (28, KeyCombo("3", [.shift, .command])), (29, KeyCombo("3", [.control, .shift, .command])),
        (30, KeyCombo("4", [.shift, .command])), (31, KeyCombo("4", [.control, .shift, .command])),
        (184, KeyCombo("5", [.shift, .command])), (181, KeyCombo("6", [.shift, .command])),
    ]

    /// Macs with a Touch Bar, where a missing entry 181 (⇧⌘6) is on.
    public static let touchBarModels: Set<String> = [
        "MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3", "MacBookPro15,1", "MacBookPro15,2",
        "MacBookPro15,3", "MacBookPro15,4", "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
        "MacBookPro17,1", "Mac14,7",
    ]

    /// The keys of every screenshot entry that is on. A missing entry is on with its default key (181 only on Touch
    /// Bar models); an unreadable domain counts as every entry missing.
    public static func enabledSystemCombos(hotkeys: [Int: SymbolicHotkey]?, model: String) -> Set<KeyCombo> {
        var combos: Set<KeyCombo> = []
        for (number, key) in screenshotEntries {
            guard let entry = hotkeys?[number] else {
                if number != 181 || touchBarModels.contains(model) { combos.insert(key) }
                continue
            }
            guard entry.enabled else { continue }
            combos.insert(combo(from: entry.parameters) ?? key)
        }
        return combos
    }

    /// `[ascii, virtual key code, modifier flags]`: the ASCII code when it's a printable character, else the key
    /// code (ANSI letters and digits).
    public static func combo(from parameters: [Int]) -> KeyCombo? {
        guard parameters.count >= 3 else { return nil }
        let key: String
        if (33..<127).contains(parameters[0]), let scalar = Unicode.Scalar(parameters[0]) {
            key = String(Character(scalar)).lowercased()
        } else if let fromCode = keyCodes[parameters[1]] {
            key = fromCode
        } else {
            return nil
        }
        let flags = parameters[2]
        var modifiers: Set<KeyModifier> = []
        if flags & (1 << 17) != 0 { modifiers.insert(.shift) }
        if flags & (1 << 18) != 0 { modifiers.insert(.control) }
        if flags & (1 << 19) != 0 { modifiers.insert(.option) }
        if flags & (1 << 20) != 0 { modifiers.insert(.command) }
        return KeyCombo(key, modifiers)
    }

    /// ANSI virtual key codes (`kVK_ANSI_*`).
    static let keyCodes: [Int: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]
}

extension KeyCombo {
    /// The registrar's form of this combo.
    public var globalKey: GlobalKey {
        GlobalKey(
            key, command: modifiers.contains(.command), option: modifiers.contains(.option),
            control: modifiers.contains(.control), shift: modifiers.contains(.shift))
    }
}
