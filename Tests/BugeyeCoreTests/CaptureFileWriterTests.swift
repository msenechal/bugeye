import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct CaptureFileWriterTests {
    let dir: TempDirectory
    let store = FakeFileMetadataStore()
    var writer: CaptureFileWriter { CaptureFileWriter(metadata: store) }

    init() throws {
        dir = try TempDirectory("writer")
    }

    /// A capture on disk with an ID, provenance, Where-from and a foreign attribute.
    func makeCapture(_ name: String = "shot.png") throws -> URL {
        let url = dir.file(name)
        try Data("old".utf8).write(to: url)
        try store.setValue(Data("e621e1f8-c36c-495a-93fc-0c247a3e6e5f".utf8), "dev.msenechal.bugeye.id", at: url)
        try store.setValue(Data(#"{"app":"Arc"}"#.utf8), "dev.msenechal.bugeye.provenance", at: url)
        try store.setValue(Data("plist".utf8), "com.apple.metadata:kMDItemWhereFroms", at: url)
        try store.setValue(Data("q".utf8), "com.apple.quarantine", at: url)
        return url
    }

    @Test func aFirstWriteCreatesTheFileWithNoAttributes() throws {
        defer { dir.remove() }
        let url = dir.file("new.png")
        try writer.write(Data("png".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("png".utf8))
        #expect(try store.names(at: url) == [])
    }

    @Test func aRewriteKeepsBugeyeAttributesAndWhereFroms() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        try writer.write(Data("new".utf8), to: url)

        #expect(try Data(contentsOf: url) == Data("new".utf8))
        #expect(
            try store.names(at: url) == [
                "com.apple.metadata:kMDItemWhereFroms", "dev.msenechal.bugeye.id", "dev.msenechal.bugeye.provenance",
            ])
        #expect(try store.value("dev.msenechal.bugeye.provenance", at: url) == Data(#"{"app":"Arc"}"#.utf8))
    }

    @Test func aRewriteKeepsTheFilesPermissions() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try writer.write(Data("new".utf8), to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func otherAttributesAreNotCopied() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        try writer.write(Data("new".utf8), to: url)
        #expect(try store.value("com.apple.quarantine", at: url) == nil)
    }

    @Test func saveAsCopiesAttributesWithANewIdentity() throws {
        defer { dir.remove() }
        let original = try makeCapture()
        let copy = dir.file("copy.png")
        let newID = try #require(CaptureID(string: "0f8fad5b-d9cb-469f-a165-70867728950e"))

        try writer.write(Data("copy".utf8), to: copy, attributesFrom: original, identity: .new(newID))

        #expect(
            try store.value("dev.msenechal.bugeye.id", at: copy) == Data("0f8fad5b-d9cb-469f-a165-70867728950e".utf8))
        #expect(try store.value("dev.msenechal.bugeye.provenance", at: copy) == Data(#"{"app":"Arc"}"#.utf8))
        #expect(
            try store.value("dev.msenechal.bugeye.id", at: original)
                == Data("e621e1f8-c36c-495a-93fc-0c247a3e6e5f".utf8))
        #expect(try Data(contentsOf: original) == Data("old".utf8))
    }

    @Test func aNewIdentityOnAFirstWriteSetsOnlyTheID() throws {
        defer { dir.remove() }
        let url = dir.file("first.png")
        let id = CaptureID()
        try writer.write(Data("png".utf8), to: url, identity: .new(id))
        #expect(try store.names(at: url) == ["dev.msenechal.bugeye.id"])
        #expect(try store.value("dev.msenechal.bugeye.id", at: url) == Data(id.description.utf8))
    }

    @Test func noTempFileIsLeftBehind() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        try writer.write(Data("new".utf8), to: url)
        #expect(try dir.contents() == ["shot.png"])
    }

    @Test func aFailedAttributeCopyLeavesTheOriginalUntouched() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        store.failSetting("dev.msenechal.bugeye.provenance")

        #expect(throws: FakeFileMetadataStore.InjectedFailure(name: "dev.msenechal.bugeye.provenance")) {
            try writer.write(Data("new".utf8), to: url)
        }
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        #expect(try store.value("dev.msenechal.bugeye.id", at: url) != nil)
        #expect(try dir.contents() == ["shot.png"])
    }

    @Test func writingIntoAMissingFolderThrows() throws {
        defer { dir.remove() }
        let url = dir.url.appendingPathComponent("missing/shot.png")
        #expect(throws: (any Error).self) { try writer.write(Data("png".utf8), to: url) }
    }

    @Test func preservedNames() {
        #expect(CaptureFileWriter.isPreserved("dev.msenechal.bugeye.uisnapshot"))
        #expect(CaptureFileWriter.isPreserved("com.apple.metadata:kMDItemWhereFroms"))
        #expect(!CaptureFileWriter.isPreserved("dev.msenechal.cleanshotcopy.id"))
        #expect(!CaptureFileWriter.isPreserved("com.apple.metadata:_kMDItemUserTags"))
    }
}
