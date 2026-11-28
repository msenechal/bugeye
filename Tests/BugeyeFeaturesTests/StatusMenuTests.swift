import BugeyeFeatures
import Testing

@Suite struct StatusMenuTests {
    @Test func waveZeroMenuMatchesTheSpec() throws {
        let registry = try FeatureRegistry([GeneralModule()])
        #expect(
            StatusMenu.entries(for: registry) == [
                .item(id: "app.about", title: "About Bugeye", key: nil),
                .separator,
                .item(id: "app.settings", title: "Settings\u{2026}", key: KeyCombo(",", [.command])),
                .separator,
                .item(id: "app.quit", title: "Quit Bugeye", key: KeyCombo("q", [.command])),
            ])
    }

    @Test func moduleItemsSitBetweenAboutAndSettingsGroupedBySlot() throws {
        let registry = try FeatureRegistry([
            StubModule(
                id: "rec", menu: [MenuItemSpec(id: "rec", title: "Record Screen", slot: MenuSlot(.record, order: 0))]),
            StubModule(
                id: "cap",
                menu: [
                    MenuItemSpec(id: "text", title: "Capture Text", slot: MenuSlot(.capture, order: 2)),
                    MenuItemSpec(id: "area", title: "Capture Area", slot: MenuSlot(.capture, order: 1)),
                ]),
        ])
        let titles = StatusMenu.entries(for: registry).map { entry -> String in
            if case .item(_, let title, _) = entry { return title }
            return "—"
        }
        #expect(
            titles == [
                "About Bugeye", "—", "Capture Area", "Capture Text", "—", "Record Screen", "—", "Settings…", "—",
                "Quit Bugeye",
            ])
    }

    @Test func settingsHasGeneralThenShortcutsThenAI() throws {
        let registry = try FeatureRegistry([GeneralModule()])
        #expect(SettingsLayout.panes(for: registry).map(\.title) == ["General", "Shortcuts", "AI"])
        #expect(registry.moduleIDs == ["general"])
    }

    @Test func shellStringsAreExactlyTheSpecs() {
        #expect(ShellStrings.settingsWindowTitle == "Bugeye Settings")
        #expect(ShellStrings.saveCapturesTo == "Save captures to")
        #expect(ShellStrings.choose == "Choose\u{2026}")
        #expect(ShellStrings.apiKeyField == "Anthropic API key")
        #expect(ShellStrings.saveKey == "Save")
        #expect(ShellStrings.testKey == "Test key")
        #expect(
            ShellStrings.aiPrivacyNote
                == "Bugeye only sends data to Claude for features you turn on. Each one is off until you enable it.")
    }
}
