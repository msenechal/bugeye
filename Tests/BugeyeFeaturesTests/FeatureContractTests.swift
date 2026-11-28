import BugeyeCore
import BugeyeFeatures
import Testing

/// The Wave 1 spec changes and registry conflicts (contracts §4.2.1).
@Suite struct FeatureContractTests {
    struct Plain: FeatureModule {
        var id: String { "plain" }
    }

    func action(_ id: String, _ placement: QuickAccessPlacement, kinds: Set<CaptureKind> = Set(CaptureKind.allCases))
        -> QuickAccessActionSpec
    {
        QuickAccessActionSpec(id: id, title: id, order: 0, placement: placement, kinds: kinds)
    }

    func mainItem(_ id: String, _ group: MainMenuGroup, _ order: Int) -> MainMenuItemSpec {
        MainMenuItemSpec(id: id, title: id, key: nil, group: group, order: order, action: "\(id):")
    }

    @Test func specDefaults() {
        let item = MenuItemSpec(id: "capture.area", title: "Capture Area", slot: MenuSlot(.capture, order: 0))
        #expect(item.hotkeyID == nil && item.shownKey == nil)
        let hotkey = HotkeySpec(
            id: "capture.area", title: "Capture Area", defaultKey: KeyCombo("4", [.shift, .command]),
            settingKey: "capture.hotkey.area")
        #expect(hotkey.title == "Capture Area")
        let qa = QuickAccessActionSpec(id: "editor.edit", title: "Edit", order: 10)
        #expect(qa.placement == .menu)
        #expect(qa.kinds == Set(CaptureKind.allCases))
        #expect(Plain().mainMenuItems() == [])
    }

    @Test func placementsHaveTheirNames() {
        #expect([QuickAccessPlacement.primary, .menu, .selection].map(\.rawValue) == ["primary", "menu", "selection"])
    }

    @Test func twoPrimariesForOneKindConflict() {
        let a = StubModule(id: "a", actions: [action("a.edit", .primary, kinds: [.screenshot])])
        let b = StubModule(id: "b", actions: [action("b.play", .primary, kinds: [.screenshot, .recording])])
        let c = StubModule(id: "c", actions: [action("c.gif", .primary, kinds: [.gif])])
        #expect(
            FeatureRegistry.conflicts(in: [a, b, c]) == [
                .quickAccessPrimaryTaken(.screenshot, ids: ["a.edit", "b.play"])
            ])
    }

    @Test func primariesForDifferentKindsDoNotConflict() {
        let a = StubModule(id: "a", actions: [action("a.edit", .primary, kinds: [.screenshot])])
        let b = StubModule(id: "b", actions: [action("b.play", .primary, kinds: [.recording, .gif])])
        let c = StubModule(id: "c", actions: [action("c.menu", .menu), action("c.other", .menu)])
        #expect(FeatureRegistry.conflicts(in: [a, b, c]) == [])
    }

    @Test func moreThanOneSelectionActionConflicts() {
        let a = StubModule(id: "a", actions: [action("a.combine", .selection)])
        #expect(FeatureRegistry.conflicts(in: [a]) == [])
        let b = StubModule(id: "b", actions: [action("b.collect", .selection)])
        #expect(
            FeatureRegistry.conflicts(in: [a, b]) == [.quickAccessSelectionTaken(ids: ["a.combine", "b.collect"])])
    }

    @Test func duplicateMainMenuItemsConflict() {
        let a = StubModule(id: "a", mainMenu: [mainItem("editor.copyText", .edit, 80)])
        let b = StubModule(id: "b", mainMenu: [mainItem("editor.copyText", .edit, 90)])
        #expect(FeatureRegistry.conflicts(in: [a, b]) == [.duplicateMainMenuItem("editor.copyText")])
    }

    @Test func aModuleCannotReuseAShellMainMenuID() {
        let a = StubModule(id: "a", mainMenu: [mainItem("mainMenu.save", .file, 5)])
        #expect(FeatureRegistry.conflicts(in: [a]) == [.duplicateMainMenuItem("mainMenu.save")])
    }

    @Test func aMenuItemsHotkeyMustBeDeclared() {
        let item = MenuItemSpec(
            id: "capture.area", title: "Capture Area", slot: MenuSlot(.capture, order: 0), hotkeyID: "capture.area")
        let declared = HotkeySpec(
            id: "capture.area", title: "Capture Area", defaultKey: KeyCombo("4", [.shift, .command]),
            settingKey: "capture.hotkey.area")
        #expect(
            FeatureRegistry.conflicts(in: [StubModule(id: "a", menu: [item])]) == [
                .unknownHotkey(menuItem: "capture.area", hotkeyID: "capture.area")
            ])
        #expect(
            FeatureRegistry.conflicts(in: [StubModule(id: "a", menu: [item]), StubModule(id: "b", keys: [declared])])
                == [])
    }

    @Test func mainMenuItemsAreSortedByGroupThenOrder() throws {
        let registry = try FeatureRegistry([
            StubModule(id: "a", mainMenu: [mainItem("v", .view, 5), mainItem("e2", .edit, 90)]),
            StubModule(id: "b", mainMenu: [mainItem("e1", .edit, 80), mainItem("f", .file, 40)]),
        ])
        #expect(registry.mainMenuItems.map(\.id) == ["f", "e1", "e2", "v"])
    }
}
