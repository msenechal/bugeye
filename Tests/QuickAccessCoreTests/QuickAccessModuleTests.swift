import BugeyeCore
import BugeyeFeatures
import QuickAccessCore
import Testing

@Suite struct QuickAccessModuleTests {
    @Test func moduleDeclaresItsPaneAndMenuItems() {
        let module = QuickAccessModule()
        #expect(module.id == "quickAccess")
        #expect(module.settingsSection() == SettingsSectionSpec(id: "quickAccess", title: "Quick Access", order: 20))
        #expect(
            module.quickAccessActions() == [
                QuickAccessActionSpec(
                    id: "quickAccess.reveal", title: "Reveal in Finder", order: 800, placement: .menu),
                QuickAccessActionSpec(id: "quickAccess.delete", title: "Delete", order: 1000, placement: .menu),
            ])
        #expect(module.quickAccessActions().allSatisfy { $0.kinds == Set(CaptureKind.allCases) })
        #expect(module.menuItems().isEmpty)
        #expect(module.hotkeys().isEmpty)
        #expect(module.mainMenuItems().isEmpty)
    }

    @Test func registersWithoutConflicts() {
        #expect(FeatureRegistry.conflicts(in: [QuickAccessModule()]).isEmpty)
    }
}

@MainActor
@Suite struct QuickAccessActivityTests {
    func action(_ n: Int) -> PerformedQuickAccessAction {
        PerformedQuickAccessAction(actionID: "a\(n)", captureID: CaptureID(), kind: .screenshot, trigger: .strip)
    }

    @Test func recordTellsObserversInOrder() {
        let activity = QuickAccessActivity()
        var seen: [String] = []
        activity.observe { seen.append($0.actionID) }
        activity.record(action(1))
        activity.record(action(2))
        #expect(seen == ["a1", "a2"])
        #expect(activity.recent.map(\.actionID) == ["a1", "a2"])
    }

    @Test func recentKeepsTheLastFifty() {
        let activity = QuickAccessActivity()
        for n in 1...60 { activity.record(action(n)) }
        #expect(activity.recent.count == 50)
        #expect(activity.recent.first?.actionID == "a11")
        #expect(activity.recent.last?.actionID == "a60")
    }
}
