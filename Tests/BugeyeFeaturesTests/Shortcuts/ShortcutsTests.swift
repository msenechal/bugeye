import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Testing

let fullscreenSpec = HotkeySpec(
    id: "capture.fullscreen", title: "Capture Fullscreen", defaultKey: KeyCombo("3", [.shift, .command]),
    settingKey: "capture.hotkey.fullscreen")
let allDisplaysSpec = HotkeySpec(
    id: "capture.allDisplays", title: "Capture All Displays", defaultKey: KeyCombo("3", [.option, .shift, .command]),
    settingKey: "capture.hotkey.allDisplays")
let areaSpec = HotkeySpec(
    id: "capture.area", title: "Capture Area", defaultKey: KeyCombo("4", [.shift, .command]),
    settingKey: "capture.hotkey.area")
let specs = [fullscreenSpec, allDisplaysSpec, areaSpec]

let shiftCmd3 = GlobalKey("3", command: true, shift: true)
let shiftCmd4 = GlobalKey("4", command: true, shift: true)

@Suite struct ShortcutStringsTests {
    @Test func everyStringIsTheSpecs() {
        #expect(ShortcutStrings.none == "None")
        #expect(ShortcutStrings.typeAShortcut == "Type a shortcut")
        #expect(
            ShortcutStrings.footer
                == "Click a shortcut, then type the new keys. Delete clears it; Esc keeps the old one.")
        #expect(ShortcutStrings.restoreDefaults == "Restore Defaults")
        #expect(ShortcutStrings.tryAgain == "Try Again")
        #expect(ShortcutStrings.keyboardShortcuts == "Keyboard Shortcuts\u{2026}")
        #expect(
            ShortcutStrings.keyboardSettingsURL == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        #expect(
            ShortcutStrings.taken("⇧⌘4")
                == "⇧⌘4 is taken by another app, so this action has no shortcut. Quit that app and press Try Again, or choose another shortcut."
        )
        #expect(
            ShortcutStrings.macOSConflict("⇧⌘3")
                == "macOS also uses ⇧⌘3 for its own screenshots and gets it first. Turn it off in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots."
        )
        #expect(ShortcutStrings.duplicate("⇧⌘4", title: "Capture Area") == "⇧⌘4 is already used by Capture Area.")
        #expect(ShortcutStrings.invalid == "Use a letter or digit with at least one of \u{2318}, \u{2325} or \u{2303}.")
        #expect(ShortcutStrings.macOSNoticeTitle == "macOS screenshot shortcuts are still on")
        #expect(
            ShortcutStrings.macOSNoticeBody(["⇧⌘3", "⇧⌘4"])
                == "Disable ⇧⌘3 and ⇧⌘4 in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots, so Bugeye receives them."
        )
        #expect(ShortcutStrings.takenNoticeTitle == "Some Bugeye shortcuts are taken")
        #expect(
            ShortcutStrings.takenNoticeBody(["⇧⌘4"])
                == "⇧⌘4 is taken by another app. Choose another in Bugeye Settings \u{2192} Shortcuts.")
        #expect(
            ShortcutStrings.takenNoticeBody(["⇧⌘3", "⌥⇧⌘3", "⇧⌘4"])
                == "⇧⌘3, ⌥⇧⌘3 and ⇧⌘4 are taken by other apps. Choose others in Bugeye Settings \u{2192} Shortcuts.")
    }

    @Test func keysJoinWithCommasAndAnd() {
        #expect(ShortcutStrings.join(["A"]) == "A")
        #expect(ShortcutStrings.join(["A", "B"]) == "A and B")
        #expect(ShortcutStrings.join(["A", "B", "C"]) == "A, B and C")
        #expect(ShortcutStrings.join(["A", "B", "C", "D"]) == "A, B, C and D")
    }
}

@Suite struct ShortcutConflictsTests {
    let shift: Int = 1 << 17
    let control: Int = 1 << 18
    let command: Int = 1 << 20

    @Test func missingEntriesCountAsOnWithTheirDefaultKeys() {
        let on = ShortcutConflicts.enabledSystemCombos(hotkeys: [:], model: "Mac15,3")
        #expect(
            on == [
                KeyCombo("3", [.shift, .command]), KeyCombo("3", [.control, .shift, .command]),
                KeyCombo("4", [.shift, .command]),
                KeyCombo("4", [.control, .shift, .command]), KeyCombo("5", [.shift, .command]),
            ])
    }

    @Test func entry181CountsAsOnWhenMissingOnlyOnTouchBarModels() {
        #expect(
            ShortcutConflicts.enabledSystemCombos(hotkeys: [:], model: "MacBookPro16,1").contains(
                KeyCombo("6", [.shift, .command])))
        #expect(
            ShortcutConflicts.enabledSystemCombos(hotkeys: [:], model: "Mac14,7").contains(
                KeyCombo("6", [.shift, .command])))
        #expect(
            !ShortcutConflicts.enabledSystemCombos(hotkeys: [:], model: "MacBookPro18,3").contains(
                KeyCombo("6", [.shift, .command])))
    }

    @Test func disabledEntriesAreOffAndRemappedOnesUseTheirOwnKeys() {
        let hotkeys: [Int: SymbolicHotkey] = [
            28: SymbolicHotkey(enabled: false, parameters: [51, 20, shift + command]),
            30: SymbolicHotkey(enabled: true, parameters: [65535, 0, control + command]),  // ⌃⌘A by key code
            29: SymbolicHotkey(enabled: false, parameters: []),
            31: SymbolicHotkey(enabled: false, parameters: []),
            184: SymbolicHotkey(enabled: false, parameters: []),
        ]
        #expect(
            ShortcutConflicts.enabledSystemCombos(hotkeys: hotkeys, model: "Mac15,3") == [
                KeyCombo("a", [.control, .command])
            ])
    }

    @Test func anUnreadableDomainCountsAsAllDefaults() {
        #expect(
            ShortcutConflicts.enabledSystemCombos(hotkeys: nil, model: "Mac15,3").contains(
                KeyCombo("3", [.shift, .command])))
    }

    @Test func parametersDecodeAsciiThenKeyCode() {
        #expect(ShortcutConflicts.combo(from: [52, 21, shift + command]) == KeyCombo("4", [.shift, .command]))
        #expect(ShortcutConflicts.combo(from: [65535, 23, shift + command]) == KeyCombo("5", [.shift, .command]))
        #expect(ShortcutConflicts.combo(from: [65535, 999, shift]) == nil)
        #expect(ShortcutConflicts.combo(from: [1]) == nil)
    }
}

@MainActor
final class ShortcutsHarness {
    let store = InMemorySettingsStore()
    let registrar = FakeHotkeyRegistrar()
    var system: Set<KeyCombo> = []
    var presses: [String] = []
    var registrations: [String: Bool] = [:]
    var logs: [String] = []
    var changes = 0
    lazy var model: ShortcutsModel = {
        let model = ShortcutsModel(
            specs: specs, store: store, registrar: registrar, systemCombos: { [unowned self] in system },
            onPress: { [unowned self] in presses.append($0) },
            onRegistration: { [unowned self] in registrations[$0] = $1 }, log: { [unowned self] in logs.append($0) })
        model.onChange = { [unowned self] in changes += 1 }
        return model
    }()
}

@Suite @MainActor struct ShortcutsModelTests {
    @Test func registerAllRegistersEveryBindingAndRoutesPresses() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        #expect(
            h.registrar.registered == [
                "capture.fullscreen": shiftCmd3,
                "capture.allDisplays": GlobalKey("3", command: true, option: true, shift: true),
                "capture.area": shiftCmd4,
            ])
        #expect(h.registrations == ["capture.fullscreen": true, "capture.allDisplays": true, "capture.area": true])
        h.registrar.press("capture.area")
        #expect(h.presses == ["capture.area"])
        #expect(h.model.rows.map { h.model.fieldText($0) } == ["⇧⌘3", "⌥⇧⌘3", "⇧⌘4"])
        #expect(
            h.logs == [
                "registered capture.fullscreen ⇧⌘3", "registered capture.allDisplays ⌥⇧⌘3",
                "registered capture.area ⇧⌘4",
            ])
        #expect(h.model.launchNotices().isEmpty)
    }

    @Test func aTakenKeyShowsNoneTheTakenMessageAndTheNotice() {
        let h = ShortcutsHarness()
        h.registrar.taken = [shiftCmd4, shiftCmd3]
        h.model.registerAll()
        let area = h.model.rows[2]
        #expect(h.model.fieldText(area) == "None")
        #expect(area.message == .taken(KeyCombo("4", [.shift, .command])))
        #expect(area.message?.button == .tryAgain)
        #expect(area.message?.text == ShortcutStrings.taken("⇧⌘4"))
        #expect(h.registrations["capture.area"] == false)
        #expect(h.logs.contains("taken capture.area ⇧⌘4"))
        #expect(
            h.model.launchNotices()
                == [
                    ShortcutNotice(
                        title: "Some Bugeye shortcuts are taken", body: ShortcutStrings.takenNoticeBody(["⇧⌘3", "⇧⌘4"]))
                ])
        // Stored binding unchanged; Try Again after the other app quits brings it back.
        #expect(h.store.value(forKey: "capture.hotkey.area") == nil)
        h.registrar.taken = []
        h.model.tryAgain("capture.area")
        #expect(h.model.rows[2].message == nil)
        #expect(h.model.fieldText(h.model.rows[2]) == "⇧⌘4")
        #expect(h.registrations["capture.area"] == true)
    }

    @Test func aMacOSConflictShowsItsMessageAndNoticeButStaysRegistered() {
        let h = ShortcutsHarness()
        h.system = [KeyCombo("3", [.shift, .command]), KeyCombo("5", [.shift, .command])]
        h.model.registerAll()
        let full = h.model.rows[0]
        #expect(full.message == .macOSConflict(KeyCombo("3", [.shift, .command])))
        #expect(full.message?.button == .keyboardShortcuts)
        #expect(h.model.fieldText(full) == "⇧⌘3")
        #expect(h.logs.contains("macOS conflict ⇧⌘3"))
        #expect(
            h.model.launchNotices()
                == [
                    ShortcutNotice(
                        title: "macOS screenshot shortcuts are still on", body: ShortcutStrings.macOSNoticeBody(["⇧⌘3"])
                    )
                ])
    }

    @Test func takenOutranksAMacOSConflict() {
        let h = ShortcutsHarness()
        h.system = [KeyCombo("3", [.shift, .command])]
        h.registrar.taken = [shiftCmd3]
        h.model.registerAll()
        #expect(h.model.rows[0].message == .taken(KeyCombo("3", [.shift, .command])))
        #expect(
            h.model.launchNotices().map(\.title) == [
                "macOS screenshot shortcuts are still on", "Some Bugeye shortcuts are taken",
            ])
    }

    @Test func typingAValidComboSavesAndRegistersIt() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        #expect(h.model.fieldText(h.model.rows[2]) == "Type a shortcut")
        h.model.typed(KeyCombo("x", [.control, .option]), for: "capture.area")
        #expect(h.store.value(forKey: "capture.hotkey.area") == .string("⌃⌥X"))
        #expect(h.registrar.registered["capture.area"] == GlobalKey("x", option: true, control: true))
        #expect(h.model.fieldText(h.model.rows[2]) == "⌃⌥X")
        #expect(h.model.rows[2].isRecording == false)
        #expect(h.changes > 0)
    }

    @Test func aDuplicateIsNotSaved() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        h.model.typed(KeyCombo("3", [.shift, .command]), for: "capture.area")
        #expect(h.store.value(forKey: "capture.hotkey.area") == nil)
        #expect(h.model.rows[2].message == .duplicate(KeyCombo("3", [.shift, .command]), title: "Capture Fullscreen"))
        #expect(h.model.rows[2].message?.text == "⇧⌘3 is already used by Capture Fullscreen.")
        #expect(h.registrar.registered["capture.area"] == shiftCmd4)
    }

    @Test func anInvalidComboIsNotSaved() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        h.model.typed(KeyCombo("4", [.shift]), for: "capture.area")
        #expect(h.store.value(forKey: "capture.hotkey.area") == nil)
        #expect(h.model.rows[2].message == .invalid)
        #expect(h.model.rows[2].message?.text == ShortcutStrings.invalid)
    }

    @Test func escKeepsTheOldComboAndDeleteClearsIt() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        h.model.escapeTyped("capture.area")
        #expect(h.model.rows[2].isRecording == false)
        #expect(h.model.fieldText(h.model.rows[2]) == "⇧⌘4")
        h.model.startRecording("capture.area")
        h.model.deleteTyped("capture.area")
        #expect(h.store.value(forKey: "capture.hotkey.area") == .string("none"))
        #expect(h.registrar.registered["capture.area"] == nil)
        #expect(h.model.fieldText(h.model.rows[2]) == "None")
        // A cleared binding counts as registered (C27).
        #expect(h.registrations["capture.area"] == true)
    }

    @Test func restoreDefaultsResetsEveryRow() {
        let h = ShortcutsHarness()
        h.store.setValue(.string("none"), forKey: "capture.hotkey.area")
        h.store.setValue(.string("⌃⌥X"), forKey: "capture.hotkey.fullscreen")
        h.model.registerAll()
        h.model.restoreDefaults()
        #expect(h.store.value(forKey: "capture.hotkey.area") == nil)
        #expect(h.store.value(forKey: "capture.hotkey.fullscreen") == nil)
        #expect(h.model.rows.map { h.model.fieldText($0) } == ["⇧⌘3", "⌥⇧⌘3", "⇧⌘4"])
        #expect(h.registrar.registered["capture.area"] == shiftCmd4)
    }

    @Test func aTypedComboThatIsTakenStaysStoredWithTheTakenMessage() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.registrar.taken = [GlobalKey("x", control: true)]
        h.model.startRecording("capture.area")
        h.model.typed(KeyCombo("x", [.control]), for: "capture.area")
        #expect(h.store.value(forKey: "capture.hotkey.area") == .string("⌃X"))
        #expect(h.model.rows[2].message == .taken(KeyCombo("x", [.control])))
        #expect(h.registrations["capture.area"] == false)
    }

    @Test func restoreDefaultsSwapsKeysBetweenRowsWithoutReportingThemTaken() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.typed(KeyCombo("x", [.control, .option]), for: "capture.fullscreen")
        h.model.typed(KeyCombo("3", [.shift, .command]), for: "capture.area")
        #expect(h.registrar.registered["capture.area"] == shiftCmd3)
        h.model.restoreDefaults()
        #expect(h.model.rows.allSatisfy { $0.message == nil && $0.registered })
        #expect(h.registrar.registered["capture.fullscreen"] == shiftCmd3)
        #expect(h.registrar.registered["capture.area"] == shiftCmd4)
    }

    @Test func recordingReleasesEveryKeySoTypedCombosReachTheField() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        // Carbon would take ⇧⌘3 before the field sees it: nothing is registered while recording.
        #expect(h.registrar.registered.isEmpty)
        // …and that doesn't count as a failed registration for the status menu.
        #expect(h.registrations.values.allSatisfy { $0 })
        h.model.typed(KeyCombo("3", [.shift, .command]), for: "capture.area")
        #expect(h.model.rows[2].message == .duplicate(KeyCombo("3", [.shift, .command]), title: "Capture Fullscreen"))
        #expect(h.registrar.registered.count == 3)
    }

    @Test func everyWayOutOfRecordingRegistersTheKeysAgain() {
        let h = ShortcutsHarness()
        h.model.registerAll()
        h.model.startRecording("capture.area")
        h.model.escapeTyped("capture.area")
        #expect(h.registrar.registered.count == 3)
        h.model.startRecording("capture.area")
        h.model.stopRecording()
        #expect(h.registrar.registered.count == 3)
        #expect(h.model.rows.allSatisfy { !$0.isRecording })
        h.model.startRecording("capture.area")
        h.model.deleteTyped("capture.area")
        #expect(h.registrar.registered.count == 2)
    }

    @Test func keyCodesGiveTheUnshiftedKey() {
        #expect(ShortcutConflicts.key(forKeyCode: 21) == "4")
        #expect(ShortcutConflicts.key(forKeyCode: 0) == "a")
        #expect(ShortcutConflicts.key(forKeyCode: 999) == nil)
    }

    @Test func comboConvertsToAGlobalKey() {
        #expect(
            KeyCombo("3", [.option, .shift, .command]).globalKey
                == GlobalKey("3", command: true, option: true, shift: true))
    }
}
