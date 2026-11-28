import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import SwiftUI
import Testing

@testable import BugeyeApp

@MainActor @Suite struct AppContextTests {
    let dir: TempDirectory
    init() throws { dir = try TempDirectory("context") }

    @Test func theTestBuilderUsesFakesAndFreshShellObjects() throws {
        defer { dir.remove() }
        let notifier = FakeNotifier()
        let policies = ActivationPolicyLog()
        let context = AppContext.testing(home: dir.url.path, notifier: notifier, policies: policies)
        context.notifier.post(title: "T", body: "B")
        #expect(notifier.posts == [FakeNotifier.Post(title: "T", body: "B")])
        #expect(context.registry.moduleIDs == ["general"])
        #expect(context.screenPermission.preflight())
        context.documentWindows.opened()
        context.documentWindows.closed()
        #expect(policies.applied == [.regular, .accessory])
        #expect(AppContext.testing(home: dir.url.path).router !== context.router)
    }

    @Test func launchStepsRunOnceInOrder() {
        defer { dir.remove() }
        let context = AppContext.testing(home: dir.url.path)
        var log: [Int] = []
        context.onLaunch { log.append(1) }
        context.onLaunch { log.append(2) }
        #expect(log == [])
        context.runLaunchSteps()
        context.runLaunchSteps()
        #expect(log == [1, 2])
    }

    @Test func retainKeepsAnObjectAlive() {
        defer { dir.remove() }
        let context = AppContext.testing(home: dir.url.path)
        weak var weakObject: NSObject?
        do {
            let object = NSObject()
            weakObject = object
            context.retain(object)
        }
        #expect(weakObject != nil)
    }

    @Test func settingsPanesKeepTheFirstAndRecordDuplicates() {
        let panes = SettingsPanes()
        #expect(panes.view(for: "capture") == nil && !panes.hasView(for: "capture"))
        panes.register("capture") { AnyView(Text("one")) }
        panes.register("capture") { AnyView(Text("two")) }
        #expect(panes.hasView(for: "capture"))
        #expect(panes.duplicates == ["capture"])
    }

    @Test func theAlertLogsUntilAPresenterIsSet() {
        let alert = ScreenRecordingAlert()
        alert.show()  // logs only
        var shown = 0
        alert.presenter = { shown += 1 }
        alert.show()
        #expect(shown == 1)
    }

    @Test func aSecondOwnerIsRefused() {
        let state = StatusItemState()
        var heard = 0
        state.observe { heard += 1 }
        let override = StatusItemOverride(badge: .finishing, accessibilityLabel: "Finishing", menu: [])
        state.setOverride(override, owner: "recording")
        state.setOverride(
            StatusItemOverride(badge: .paused(elapsed: "1"), accessibilityLabel: "x", menu: []), owner: "guide")
        state.setOverride(nil, owner: "guide")
        #expect(state.override == override && state.owner == "recording" && heard == 1)
        state.setOverride(nil, owner: "recording")
        #expect(state.override == nil && state.owner == nil && heard == 2)
        state.setOverride(override, owner: "guide")
        #expect(state.owner == "guide")
    }

    @Test func hotkeysCountAsRegisteredUntilMarkedOtherwise() {
        let status = HotkeyStatus()
        #expect(status.isRegistered("capture.area"))
        status.setRegistered("capture.area", false)
        #expect(!status.isRegistered("capture.area"))
        status.setRegistered("capture.area", true)
        #expect(status.isRegistered("capture.area"))
    }

    #if DEBUG
        @Test func debugCommandsRefuseDuplicatesAndBuiltIns() {
            let commands = DebugCommands()
            commands.register("recording.state") { "idle \($0)" }
            commands.register("recording.state") { _ in "other" }
            commands.register("events") { _ in "" }
            #expect(commands.handler(for: "recording.state")?("x") == "idle x")
            #expect(commands.handler(for: "events") == nil)
            #expect(commands.duplicates == ["recording.state", "events"])
        }
    #endif
}
