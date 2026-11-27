import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct AppSettingsTests {
    @Test func defaultsWhenNothingIsStored() {
        let settings = AppSettings.load(from: InMemorySettingsStore())
        #expect(settings.saveFolder == "~/Pictures/Bugeye/")
        #expect(settings.aiModel == "claude-opus-5-5")
    }

    @Test func loadsStoredValues() {
        let store = InMemorySettingsStore([
            "saveFolder": .string("/Volumes/Shots/"), "ai.model": .string("claude-haiku-5-5"),
        ])
        let settings = AppSettings.load(from: store)
        #expect(settings.saveFolder == "/Volumes/Shots/")
        #expect(settings.aiModel == "claude-haiku-5-5")
    }

    @Test func invalidValuesFallBackToDefaults() {
        let store = InMemorySettingsStore([
            "saveFolder": .string("relative/path"), "ai.model": .string("gpt-9"),
        ])
        #expect(AppSettings.load(from: store) == AppSettings())
        let wrongTypes = InMemorySettingsStore(["saveFolder": .bool(true), "ai.model": .string("claude-")])
        #expect(AppSettings.load(from: wrongTypes) == AppSettings())
        let upper = InMemorySettingsStore(["ai.model": .string("claude-Opus")])
        #expect(AppSettings.load(from: upper).aiModel == "claude-opus-5-5")
    }

    @Test func saveWritesOnlyChangedKeys() {
        let store = InMemorySettingsStore()
        var settings = AppSettings()
        let old = settings
        settings.aiModel = "claude-sonnet-5-5"
        settings.save(to: store, comparedTo: old)
        #expect(store.all == ["ai.model": .string("claude-sonnet-5-5")])
    }

    @Test func tildeExpandsAgainstTheHomeFolder() {
        #expect(FolderPath.expandingTilde("~/Pictures/Bugeye/", home: "/Users/m") == "/Users/m/Pictures/Bugeye/")
        #expect(FolderPath.expandingTilde("~/Pictures/Bugeye/", home: "/Users/m/") == "/Users/m/Pictures/Bugeye/")
        #expect(FolderPath.expandingTilde("/Volumes/X/", home: "/Users/m") == "/Volumes/X/")
        #expect(FolderPath.expandingTilde("~other/x", home: "/Users/m") == "~other/x")
    }

    @Test func homeAbbreviatesToTilde() {
        #expect(FolderPath.abbreviatingHome("/Users/m/Pictures/Bugeye/", home: "/Users/m") == "~/Pictures/Bugeye/")
        #expect(FolderPath.abbreviatingHome("/Users/m", home: "/Users/m/") == "~")
        #expect(FolderPath.abbreviatingHome("/Users/mx/Pictures", home: "/Users/m") == "/Users/mx/Pictures")
        #expect(FolderPath.abbreviatingHome("/Volumes/X/", home: "/Users/m") == "/Volumes/X/")
    }

    @Test func saveFolderIsCreatedOnceWithItsParents() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let folder = dir.url.appendingPathComponent("Pictures/Bugeye", isDirectory: true)
        #expect(try SaveFolder.ensureExists(at: folder))
        #expect(try !SaveFolder.ensureExists(at: folder))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func aFileInTheWayIsAnError() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let file = dir.file("Bugeye")
        try Data().write(to: file)
        #expect(throws: (any Error).self) { try SaveFolder.ensureExists(at: file) }
    }
}
