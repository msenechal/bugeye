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

    @Test func quittingWithNoEditorOpenIsAllowed() async throws {
        let dir = try TempDirectory("editor-wiring-quit")
        defer { dir.remove() }
        let context = AppContext.testing(home: dir.url.path, modules: [GeneralModule()] + EditorWiring.modules)
        EditorWiring.install(context)
        #expect(await context.termination.shouldTerminate())
    }

    @Test func theAppBuildsWithTheEditorWired() throws {
        #expect(AppServices.modules.map(\.id).contains("editor"))
        _ = try FeatureRegistry(AppServices.modules)
    }
}
