import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import EditorCore
import Foundation
import Testing

@testable import BugeyeApp

@MainActor @Suite struct EditorWiringTests {
    @Test func theWiringRegistersTheEditActionOpenLastCaptureAndTheOpener() throws {
        let dir = try TempDirectory("editor-wiring")
        defer { dir.remove() }
        let context = AppContext.testing(home: dir.url.path, modules: [GeneralModule()] + EditorWiring.modules)
        EditorWiring.install(context)
        #expect(context.router.duplicates.isEmpty)
        #expect(context.registry.moduleIDs.contains("editor"))
        #expect(context.router.quickAccessHandler(for: EditorModule.editActionID) != nil)
        #expect(context.router.canOpen(.screenshot))
        #expect(!context.router.canOpen(.recording))
        #expect(!context.router.isMenuItemEnabled(EditorModule.openLastCaptureID))

        let url = dir.file("Shot.png")
        try Data("png".utf8).write(to: url)
        let item = CaptureItem(
            id: CaptureID(), fileURL: url, isSaved: true, kind: .screenshot, createdAt: Date(), pixelsPerPoint: 2)
        context.captureEvents.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        #expect(context.router.isMenuItemEnabled(EditorModule.openLastCaptureID))
        try FileManager.default.removeItem(at: url)
        #expect(!context.router.isMenuItemEnabled(EditorModule.openLastCaptureID))
    }

    /// Every entry point reaches a live manager: an undecodable file posts the open-failed notice, which needs no
    /// window (final review D, I1). A `.recording` item through Edit does nothing.
    @Test func everyEntryPointReachesTheRetainedManager() async throws {
        let dir = try TempDirectory("editor-wiring-live")
        defer { dir.remove() }
        let notifier = FakeNotifier()
        let policies = ActivationPolicyLog()
        let context = AppContext.testing(
            home: dir.url.path, notifier: notifier, modules: [GeneralModule()] + EditorWiring.modules,
            policies: policies)
        EditorWiring.install(context)
        #expect(policies.applied.isEmpty)  // install opens nothing
        #expect(context.documentWindows.openCount == 0)

        let url = dir.file("Shot.png")
        try Data("not a png".utf8).write(to: url)
        let item = CaptureItem(
            id: CaptureID(), fileURL: url, isSaved: true, kind: .screenshot, createdAt: Date(), pixelsPerPoint: 2)
        let notice = FakeNotifier.Post(
            title: EditorStrings.openFailedTitle, body: EditorStrings.openFailedBody(name: "Shot.png"))
        func waitForPosts(_ count: Int) async throws {
            for _ in 0..<300 where notifier.posts.count < count { try await Task.sleep(for: .milliseconds(10)) }
        }

        let edit = try #require(context.router.quickAccessHandler(for: EditorModule.editActionID))
        var recording = item
        recording.kind = .recording
        edit.perform(QuickAccessActionContext(actionID: EditorModule.editActionID, items: [recording], trigger: .strip))
        edit.perform(
            QuickAccessActionContext(actionID: EditorModule.editActionID, items: [item], trigger: .doubleClick))
        try await waitForPosts(1)
        #expect(notifier.posts == [notice])

        #expect(context.router.open(item))
        try await waitForPosts(2)
        #expect(notifier.posts == [notice, notice])

        context.captureEvents.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        #expect(context.router.performMenuItem(EditorModule.openLastCaptureID))
        try await waitForPosts(3)
        #expect(notifier.posts == [notice, notice, notice])
    }

    @Test func theQuitPromptIsRegisteredAndAllowsQuitWithNoEditorOpen() async throws {
        let dir = try TempDirectory("editor-wiring-quit")
        defer { dir.remove() }
        let context = AppContext.testing(home: dir.url.path, modules: [GeneralModule()] + EditorWiring.modules)
        EditorWiring.install(context)
        #expect(await context.termination.shouldTerminate())
    }
}
