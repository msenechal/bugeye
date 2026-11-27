import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct FakeFileMetadataStoreTests {
    @Test func setReadListAndRemove() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let file = dir.file("a.png")
        try Data("x".utf8).write(to: file)
        let store = FakeFileMetadataStore()

        try store.setValue(Data("1".utf8), "dev.msenechal.bugeye.id", at: file)
        try store.setValue(Data("2".utf8), "com.example.other", at: file)
        #expect(try store.names(at: file) == ["com.example.other", "dev.msenechal.bugeye.id"])
        #expect(try store.value("dev.msenechal.bugeye.id", at: file) == Data("1".utf8))

        try store.removeValue("com.example.other", at: file)
        try store.removeValue("never-set", at: file)
        #expect(try store.names(at: file) == ["dev.msenechal.bugeye.id"])
        #expect(try store.value("com.example.other", at: file) == nil)
    }

    @Test func attributesFollowARename() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let old = dir.file("old.png")
        let new = dir.file("new.png")
        try Data("x".utf8).write(to: old)
        let store = FakeFileMetadataStore()
        try store.setValue(Data("1".utf8), "dev.msenechal.bugeye.id", at: old)

        try FileManager.default.moveItem(at: old, to: new)
        #expect(try store.value("dev.msenechal.bugeye.id", at: new) == Data("1".utf8))
    }

    @Test func anAtomicWriteLosesTheAttributesLikeTheRealThing() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let file = dir.file("a.png")
        try Data("x".utf8).write(to: file)
        let store = FakeFileMetadataStore()
        try store.setValue(Data("1".utf8), "dev.msenechal.bugeye.id", at: file)

        try Data("y".utf8).write(to: file, options: .atomic)  // the bug class CaptureFileWriter exists for
        #expect(try store.names(at: file) == [])
    }

    @Test func aMissingFileThrows() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let store = FakeFileMetadataStore()
        #expect(throws: (any Error).self) { try store.names(at: dir.file("missing.png")) }
        #expect(throws: (any Error).self) { try store.setValue(Data(), "n", at: dir.file("missing.png")) }
    }

    @Test func injectedFailuresThrowForThatNameOnly() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let file = dir.file("a.png")
        try Data("x".utf8).write(to: file)
        let store = FakeFileMetadataStore()
        store.failSetting("bad")
        #expect(throws: FakeFileMetadataStore.InjectedFailure(name: "bad")) {
            try store.setValue(Data(), "bad", at: file)
        }
        try store.setValue(Data(), "good", at: file)
    }
}
