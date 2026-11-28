/// Key labels for the keystroke badge and the timeline (spec §5.4, §7.4).
public enum KeystrokeFormatter {
    /// The key's base: a name for a named key ("Return", "F1", "Space"), the digit for the number row, the
    /// uppercase letter a Latin layout produces, and the US letter of the key for any other script.
    /// `characters` is the key's character with no modifiers applied in the current layout
    /// (`NSEvent.characters(byApplyingModifiers: [])`). Nil when the key has neither a name nor a character.
    public static func baseKey(keyCode: UInt16, characters: String?) -> String? {
        if let name = namedKeys[keyCode] { return name }
        if let digit = numberRow[keyCode] { return digit }
        guard let characters, characters.count == 1, let scalar = characters.unicodeScalars.first,
            scalar.value >= 0x20
        else { return usBase[keyCode] }
        if scalar.properties.isAlphabetic, scalar.value >= 0x250 {
            // Cyrillic, Greek, …: the US letter of the key.
            return usBase[keyCode] ?? characters.uppercased()
        }
        return characters.uppercased()
    }

    /// macOS virtual key codes of keys with names.
    static let namedKeys: [UInt16: String] = [
        36: "Return", 76: "Enter", 48: "Tab", 49: "Space", 51: "Delete", 117: "ForwardDelete", 53: "Escape",
        123: "Left", 124: "Right", 125: "Down", 126: "Up", 115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]

    static let numberRow: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]

    /// The US (ANSI) character of each character key.
    static let usBase: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
        46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
    ]
}
