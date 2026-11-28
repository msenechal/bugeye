import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import QuickAccessCore
import Testing

@testable import BugeyeApp

@MainActor @Suite struct QuickAccessWiringTests {
    func context(_ home: TempDirectory) -> AppContext {
        AppContext.testing(home: home.url.path, modules: [GeneralModule()] + QuickAccessWiring.modules)
    }

    @Test func theModuleIsQuickAccess() {
        #expect(QuickAccessWiring.modules.map(\.id) == ["quickAccess"])
    }

    @Test func installRegistersHandlersPaneAndDebugCommand() throws {
        let home = try TempDirectory("qa-wiring")
        defer { home.remove() }
        let context = context(home)
        QuickAccessWiring.install(context)
        #expect(context.router.quickAccessHandler(for: QuickAccessActionID.reveal) != nil)
        #expect(context.router.quickAccessHandler(for: QuickAccessActionID.delete) != nil)
        #expect(context.router.duplicates.isEmpty)
        #expect(context.settingsPanes.hasView(for: "quickAccess"))
        #expect(context.settingsPanes.duplicates.isEmpty)
        #if DEBUG
            #expect(context.debugCommands.handler(for: "quickAccess.stack")?("") == "[]")
            #expect(context.debugCommands.duplicates.isEmpty)
        #endif
    }

    @Test func aCreatedEventShowsAThumbnail() throws {
        let home = try TempDirectory("qa-wiring")
        defer { home.remove() }
        let context = context(home)
        QuickAccessWiring.install(context)
        let item = CaptureItem(
            id: CaptureID(), fileURL: home.file("Screenshot.png"), isSaved: false, kind: .screenshot, createdAt: Date(),
            pixelsPerPoint: 2)
        context.captureEvents.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        #if DEBUG
            let stack = try #require(context.debugCommands.handler(for: "quickAccess.stack")?(""))
            #expect(stack.contains("\"file\":\"Screenshot.png\""))
        #endif
        context.captureEvents.publish(CaptureEvent(change: .deleted, item: item, origin: "capture"))
        #if DEBUG
            #expect(context.debugCommands.handler(for: "quickAccess.stack")?("") == "[]")
        #endif
    }
}
