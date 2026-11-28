import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import Testing

@testable import BugeyeApp

@MainActor @Suite struct AppServicesTests {
    func services(home: String, store: InMemorySettingsStore = InMemorySettingsStore()) throws -> AppServices {
        try AppServices(
            settingsStore: store, secrets: FakeSecretStore(), metadata: FakeFileMetadataStore(), home: home,
            llm: FakeLLM())
    }

    @Test func waveZeroRegistersOnlyGeneral() throws {
        let app = try services(home: "/Users/m")
        #expect(app.registry.moduleIDs == ["general"])
        #expect(SettingsLayout.panes(for: app.registry).map(\.title) == ["General", "AI"])
        #expect(app.aiKey.status == .noKey)
    }

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
