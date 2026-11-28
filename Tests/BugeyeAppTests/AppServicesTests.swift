import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import SwiftUI
import Testing

@testable import BugeyeApp

@MainActor @Suite struct AppServicesTests {
    func services(
        home: String, store: InMemorySettingsStore = InMemorySettingsStore(),
        extraInstall: @MainActor (AppContext) -> Void = { _ in }
    ) throws(AppServices.LaunchError) -> AppServices {
        try AppServices(
            settingsStore: store, secrets: FakeSecretStore(), metadata: FakeFileMetadataStore(), home: home,
            llm: FakeLLM(), clipboard: FakeClipboard(), notifier: FakeNotifier(),
            screenPermission: FakeScreenCapturePermission(granted: true), extraInstall: extraInstall)
    }

    /// K20: computed from the wiring lists, so no epic edits this test when it fills its wiring.
    @Test func modulesAreGeneralThenEveryWiringsModules() throws {
        let wiringIDs =
            (CaptureWiring.modules + QuickAccessWiring.modules + EditorWiring.modules + RecordingWiring.modules
            + TextWiring.modules).map(\.id)
        #expect(AppServices.modules.map(\.id) == ["general"] + wiringIDs)
        let app = try services(home: "/Users/m")
        #expect(app.registry.moduleIDs == ["general"] + wiringIDs)
        #expect(app.aiKey.status == .noKey)
    }

    @Test func buildsWithFakesAndAnEmptyContext() throws {
        let app = try services(home: "/Users/m")
        #expect(app.context.home == "/Users/m")
        #expect(app.context.router.duplicates == [])
        #expect(app.context.settingsPanes.duplicates == [])
        #expect(app.context.statusItem.override == nil)
        #expect(app.context.documentWindows.openCount == 0)
    }

    @Test func aDuplicateRouterIDFailsLaunch() {
        #expect(throws: AppServices.LaunchError.duplicates(router: ["menu:x"], settingsPanes: [], debugCommands: [])) {
            try services(home: "/Users/m") { context in
                context.router.onMenuItem("x") {}
                context.router.onMenuItem("x") {}
            }
        }
    }

    @Test func aDuplicatePaneFailsLaunch() {
        #expect(throws: AppServices.LaunchError.duplicates(router: [], settingsPanes: ["capture"], debugCommands: [])) {
            try services(home: "/Users/m") { context in
                context.settingsPanes.register("capture") { AnyView(EmptyView()) }
                context.settingsPanes.register("capture") { AnyView(EmptyView()) }
            }
        }
    }

    #if DEBUG
        @Test func aDuplicateOrBuiltInDebugCommandFailsLaunch() {
            #expect(
                throws: AppServices.LaunchError.duplicates(
                    router: [], settingsPanes: [], debugCommands: ["quickAccess.stack", "ping"])
            ) {
                try services(home: "/Users/m") { context in
                    context.debugCommands.register("quickAccess.stack") { _ in "" }
                    context.debugCommands.register("quickAccess.stack") { _ in "" }
                    context.debugCommands.register("ping") { _ in "" }
                }
            }
        }
    #endif

    @Test func generalShowsTheDefaultFolder() throws {
        let app = try services(home: "/Users/m")
        #expect(app.general.displayedFolder == "~/Pictures/Bugeye/")
        #expect(app.general.folderURL.path == "/Users/m/Pictures/Bugeye")
    }

    @Test func choosingAFolderStoresItUnderTheHomeAsTilde() throws {
        let dir = try TempDirectory("app")
        defer { dir.remove() }
        let store = InMemorySettingsStore()
        let app = try services(home: dir.url.path, store: store)

        app.general.choose(dir.url.appendingPathComponent("Shots", isDirectory: true))

        #expect(store.value(forKey: AppSettings.Key.saveFolder) == .string("~/Shots/"))
        #expect(app.general.displayedFolder == "~/Shots/")
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("Shots").path))
    }

    @Test func theSaveFolderIsCreatedWhenMissing() throws {
        let dir = try TempDirectory("app")
        defer { dir.remove() }
        let app = try services(home: dir.url.path)
        app.general.ensureFolderExists()
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("Pictures/Bugeye").path))
    }
}
