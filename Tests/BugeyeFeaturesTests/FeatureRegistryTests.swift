import BugeyeFeatures
import Testing

/// A module built from plain values, for tests.
struct StubModule: FeatureModule {
    var id: String
    var menu: [MenuItemSpec] = []
    var keys: [HotkeySpec] = []
    var section: SettingsSectionSpec? = nil
    var actions: [QuickAccessActionSpec] = []

    func menuItems() -> [MenuItemSpec] { menu }
    func hotkeys() -> [HotkeySpec] { keys }
    func settingsSection() -> SettingsSectionSpec? { section }
    func quickAccessActions() -> [QuickAccessActionSpec] { actions }
}

@Suite struct FeatureRegistryTests {
    let areaKey = KeyCombo("4", [.shift, .command])

    @Test func distinctModulesRegister() throws {
        let registry = try FeatureRegistry([
            StubModule(
                id: "capture",
                menu: [MenuItemSpec(id: "capture.area", title: "Capture Area", slot: MenuSlot(.capture, order: 0))]),
            StubModule(
                id: "record",
                menu: [MenuItemSpec(id: "record.screen", title: "Record Screen", slot: MenuSlot(.record, order: 0))]),
        ])
        #expect(registry.moduleIDs == ["capture", "record"])
        #expect(registry.menuItems.map(\.id) == ["capture.area", "record.screen"])
    }

    @Test func twoModulesCannotShareAnID() {
        #expect(throws: FeatureRegistryError(conflicts: [.duplicateModule("capture")])) {
            try FeatureRegistry([StubModule(id: "capture"), StubModule(id: "capture")])
        }
    }

    @Test func twoModulesCannotClaimTheSameHotkey() {
        let a = StubModule(id: "a", keys: [HotkeySpec(id: "a.area", defaultKey: areaKey, settingKey: "hotkey.a")])
        let b = StubModule(id: "b", keys: [HotkeySpec(id: "b.area", defaultKey: areaKey, settingKey: "hotkey.b")])
        #expect(throws: FeatureRegistryError(conflicts: [.hotkeyTaken(areaKey, ids: ["a.area", "b.area"])])) {
            try FeatureRegistry([a, b])
        }
    }

    @Test func modifierOrderDoesNotHideAHotkeyClash() {
        let a = StubModule(
            id: "a", keys: [HotkeySpec(id: "a.k", defaultKey: KeyCombo("4", [.command, .shift]), settingKey: "a")])
        let b = StubModule(
            id: "b", keys: [HotkeySpec(id: "b.k", defaultKey: KeyCombo("4", [.shift, .command]), settingKey: "b")])
        #expect(FeatureRegistry.conflicts(in: [a, b]).count == 1)
    }

    @Test func twoModulesCannotClaimTheSameMenuSlot() {
        let slot = MenuSlot(.capture, order: 2)
        let a = StubModule(id: "a", menu: [MenuItemSpec(id: "a.item", title: "A", slot: slot)])
        let b = StubModule(id: "b", menu: [MenuItemSpec(id: "b.item", title: "B", slot: slot)])
        #expect(throws: FeatureRegistryError(conflicts: [.menuSlotTaken(slot, ids: ["a.item", "b.item"])])) {
            try FeatureRegistry([a, b])
        }
    }

    @Test func everyOtherKindOfClashIsReported() {
        let a = StubModule(
            id: "a", menu: [MenuItemSpec(id: "same", title: "A", slot: MenuSlot(.capture, order: 0))],
            keys: [HotkeySpec(id: "k", defaultKey: KeyCombo("1", [.command]), settingKey: "hotkey")],
            section: SettingsSectionSpec(id: "pane", title: "A", order: 0),
            actions: [QuickAccessActionSpec(id: "copy", title: "Copy", order: 0)])
        let b = StubModule(
            id: "b", menu: [MenuItemSpec(id: "same", title: "B", slot: MenuSlot(.record, order: 0))],
            keys: [
                HotkeySpec(id: "k2", defaultKey: KeyCombo("2", [.command]), settingKey: "hotkey"),
                HotkeySpec(id: "k", defaultKey: KeyCombo("3", [.command]), settingKey: "hotkey.other"),
            ],
            section: SettingsSectionSpec(id: "pane", title: "B", order: 1),
            actions: [QuickAccessActionSpec(id: "copy", title: "Copy", order: 1)])
        #expect(
            FeatureRegistry.conflicts(in: [a, b]) == [
                .duplicateMenuItem("same"), .duplicateHotkey("k"), .settingKeyTaken("hotkey", ids: ["k", "k2"]),
                .duplicateSettingsSection("pane"), .duplicateQuickAccessAction("copy"),
            ])
    }

    @Test func keyCombosPrintInMacOSOrder() {
        #expect(KeyCombo("4", [.command, .shift]).description == "⇧⌘4")
        #expect(KeyCombo("3", [.command, .option, .shift]).description == "⌥⇧⌘3")
        #expect(KeyCombo(",", [.command]).description == "⌘,")
    }
}
