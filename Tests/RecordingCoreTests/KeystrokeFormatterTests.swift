import RecordingCore
import Testing

@Suite struct KeystrokeBaseKeyTests {
    @Test(arguments: [
        // US
        (UInt16(1), "s", "S"), (8, "c", "C"), (20, "3", "3"), (44, "/", "/"), (50, "`", "`"), (42, "\\", "\\"),
        // AZERTY: the A key sits where US has Q; the number row's unshifted characters are symbols.
        (12, "a", "A"), (18, "&", "1"), (19, "é", "2"), (29, "à", "0"),
        // German: Y and Z are swapped; Ü keeps its letter.
        (6, "y", "Y"), (16, "z", "Z"), (33, "ü", "Ü"),
        // Russian: Cyrillic letters show the US letter of the key.
        (8, "с", "C"), (1, "ы", "S"), (0, "ф", "A"), (17, "е", "T"),
        // No characters: the US base.
        (13, "", "W"),
    ])
    func characterKeys(keyCode: UInt16, characters: String, base: String) {
        #expect(KeystrokeFormatter.baseKey(keyCode: keyCode, characters: characters) == base)
    }

    @Test(arguments: [
        (UInt16(36), "Return"), (76, "Enter"), (48, "Tab"), (49, "Space"), (51, "Delete"), (117, "ForwardDelete"),
        (53, "Escape"), (123, "Left"), (124, "Right"), (125, "Down"), (126, "Up"), (115, "Home"), (119, "End"),
        (116, "PageUp"), (121, "PageDown"), (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"),
        (97, "F6"), (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
    ])
    func namedKeys(keyCode: UInt16, name: String) {
        #expect(KeystrokeFormatter.baseKey(keyCode: keyCode, characters: "\r") == name)
    }

    @Test func anUnknownKeyWithNoCharacterHasNoBase() {
        #expect(KeystrokeFormatter.baseKey(keyCode: 200, characters: nil) == nil)
        #expect(KeystrokeFormatter.baseKey(keyCode: 200, characters: "") == nil)
    }
}
