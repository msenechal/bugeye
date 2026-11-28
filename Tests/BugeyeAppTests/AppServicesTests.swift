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
        // Test-only ids, so an epic's own registrations never collide with them (K20, final review I1).
        do {
            _ = try services(home: "/Users/m") { context in
                context.router.onMenuItem("test.item") {}
                context.router.onMenuItem("test.item") {}
            }
            Issue.record("launch should fail")
        } catch {
            guard case .duplicates(let router, _, _) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(router.contains("menu:test.item"))
        }
    }

    @Test func aDuplicatePaneFailsLaunch() {
        do {
            _ = try services(home: "/Users/m") { context in
                context.settingsPanes.register("test.pane") { AnyView(EmptyView()) }
                context.settingsPanes.register("test.pane") { AnyView(EmptyView()) }
            }
            Issue.record("launch should fail")
        } catch {
            guard case .duplicates(_, let panes, _) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(panes.contains("test.pane"))
        }
    }

    #if DEBUG
        @Test func aDuplicateOrBuiltInDebugCommandFailsLaunch() {
            do {
                _ = try services(home: "/Users/m") { context in
                    context.debugCommands.register("test.command") { _ in "" }
                    context.debugCommands.register("test.command") { _ in "" }
                    context.debugCommands.register("ping") { _ in "" }
                }
                Issue.record("launch should fail")
            } catch {
                guard case .duplicates(_, _, let commands) = error else {
                    Issue.record("\(error)")
                    return
                }
                #expect(commands.contains("test.command") && commands.contains("ping"))
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
