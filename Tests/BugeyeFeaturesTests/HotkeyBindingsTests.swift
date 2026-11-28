import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Testing

@Suite struct HotkeyBindingsTests {
    let area = HotkeySpec(
        id: "capture.area", title: "Capture Area", defaultKey: KeyCombo("4", [.shift, .command]),
        settingKey: "capture.hotkey.area")

    /// Every Capture and Recording default (Capture §5.1, Recording §5.1).
    @Test(arguments: [
        KeyCombo("3", [.shift, .command]), KeyCombo("3", [.option, .shift, .command]),
        KeyCombo("4", [.shift, .command]), KeyCombo("5", [.shift, .command]),
    ])
    func defaultsRoundTrip(combo: KeyCombo) {
        #expect(KeyCombo(description: combo.description) == combo)
        #expect(combo.isValidHotkey)
    }

    @Test func descriptionsParse() {
        #expect(KeyCombo(description: "⇧⌘3") == KeyCombo("3", [.shift, .command]))
        #expect(KeyCombo(description: "⌥⇧⌘3") == KeyCombo("3", [.option, .shift, .command]))
        #expect(KeyCombo(description: "⌘⇧A") == KeyCombo("a", [.shift, .command]))
        #expect(KeyCombo(description: "⌃⌥X") == KeyCombo("x", [.control, .option]))
        #expect(KeyCombo(description: "⌘,") == KeyCombo(",", [.command]))
        #expect(KeyCombo(description: "Q") == KeyCombo("q", []))
    }

    @Test(arguments: ["", "⌘", "⇧⌘", "⌘34", "none", "⌘⌘3", "Cmd+3", "⇧⌘ 3", "3⌘"])
    func invalidDescriptionsAreNil(text: String) {
        #expect(KeyCombo(description: text) == nil)
    }

    @Test func validHotkeysNeedALetterOrDigitAndACommandOptionOrControl() {
        #expect(KeyCombo("a", [.control]).isValidHotkey)
        #expect(KeyCombo("9", [.option]).isValidHotkey)
        #expect(!KeyCombo("3", [.shift]).isValidHotkey)
        #expect(!KeyCombo("3", []).isValidHotkey)
        #expect(!KeyCombo(",", [.command]).isValidHotkey)
        #expect(!KeyCombo("é", [.command]).isValidHotkey)
        #expect(!KeyCombo("ab", [.command]).isValidHotkey)
    }

    @Test func currentFallsBackToTheDefaultWhenMissingOrInvalid() {
        #expect(HotkeyBindings.current(area, in: InMemorySettingsStore()) == area.defaultKey)
        for bad: SettingValue in [.string("⇧3"), .string("garbage"), .bool(true), .int(4)] {
            let store = InMemorySettingsStore(["capture.hotkey.area": bad])
            #expect(HotkeyBindings.current(area, in: store) == area.defaultKey, "\(bad)")
        }
    }

    @Test func clearedIsNilAndValidIsTheUsersBinding() {
        #expect(HotkeyBindings.cleared == "none")
        let cleared = InMemorySettingsStore(["capture.hotkey.area": .string("none")])
        #expect(HotkeyBindings.current(area, in: cleared) == nil)
        let mine = InMemorySettingsStore(["capture.hotkey.area": .string("⌃⌥A")])
        #expect(HotkeyBindings.current(area, in: mine) == KeyCombo("a", [.control, .option]))
    }
}
