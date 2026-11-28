import BugeyeFeatures
import RecordingCore
import Testing

@Suite struct RecordingModuleTests {
    let module = RecordingModule()

    @Test func registersRecordScreenItsHotkeyAndItsPane() {
        #expect(module.id == "recording")
        #expect(
            module.menuItems() == [
                MenuItemSpec(
                    id: "recording.record", title: "Record Screen", slot: MenuSlot(.record, order: 0),
                    hotkeyID: "recording.toggle")
            ])
        #expect(
            module.hotkeys() == [
                HotkeySpec(
                    id: "recording.toggle", title: "Record Screen", defaultKey: KeyCombo("5", [.shift, .command]),
                    settingKey: "recording.hotkey.toggle")
            ])
        #expect(module.settingsSection() == SettingsSectionSpec(id: "recording", title: "Recording", order: 30))
        #expect(module.quickAccessActions().isEmpty)
        #expect(module.mainMenuItems().isEmpty)
    }

    @Test func registersWithoutConflictsBesideItself() throws {
        let registry = try FeatureRegistry([module])
        #expect(registry.hotkeys.map(\.id) == ["recording.toggle"])
    }
}
