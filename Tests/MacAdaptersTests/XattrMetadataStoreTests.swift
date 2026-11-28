import BugeyeCore
import BugeyeTestSupport
import Foundation
import MacAdapters
import Testing

@Suite struct XattrMetadataStoreTests {
    let store = XattrMetadataStore()

    @Test func setReadListAndRemove() throws {
        let dir = try TempDirectory("xattr")
        defer { dir.remove() }
        let file = dir.file("a.png")
        try Data("x".utf8).write(to: file)

        try store.setValue(Data("1".utf8), "dev.msenechal.bugeye.id", at: file)
        #expect(try store.names(at: file).contains("dev.msenechal.bugeye.id"))
        #expect(try store.value("dev.msenechal.bugeye.id", at: file) == Data("1".utf8))
        #expect(try store.value("dev.msenechal.bugeye.none", at: file) == nil)

        try store.removeValue("dev.msenechal.bugeye.id", at: file)
        try store.removeValue("dev.msenechal.bugeye.id", at: file)
        #expect(try !store.names(at: file).contains("dev.msenechal.bugeye.id"))
    }

    @Test func whereFromsRoundTripsAsABinaryPlist() throws {
        let dir = try TempDirectory("xattr")
        defer { dir.remove() }
        let file = dir.file("a.png")
        try Data("x".utf8).write(to: file)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["https://example.com/page"], format: .binary, options: 0)

        try store.setValue(plist, CaptureFileWriter.whereFromsAttribute, at: file)
        let read = try #require(try store.value(CaptureFileWriter.whereFromsAttribute, at: file))
        let urls = try PropertyListSerialization.propertyList(from: read, format: nil) as? [String]
        #expect(urls == ["https://example.com/page"])
    }

    @Test func aMissingFileThrows() throws {
        let dir = try TempDirectory("xattr")
        defer { dir.remove() }
        #expect(throws: (any Error).self) { try store.names(at: dir.file("missing")) }
        #expect(throws: (any Error).self) { try store.value("n", at: dir.file("missing")) }
    }

    /// The same contract the Linux tests check with the fake, against the real file system.
    @Test func captureFileWriterKeepsRealAttributesAcrossARewrite() throws {
        let dir = try TempDirectory("xattr")
        defer { dir.remove() }
        let file = dir.file("shot.png")
        try Data("old".utf8).write(to: file)
        try store.setValue(Data("id".utf8), "dev.msenechal.bugeye.id", at: file)
        try store.setValue(Data("p".utf8), "dev.msenechal.bugeye.provenance", at: file)

        try CaptureFileWriter(metadata: store).write(Data("new".utf8), to: file)

        #expect(try Data(contentsOf: file) == Data("new".utf8))
        #expect(try store.value("dev.msenechal.bugeye.id", at: file) == Data("id".utf8))
        #expect(try store.value("dev.msenechal.bugeye.provenance", at: file) == Data("p".utf8))
        #expect(try dir.contents() == ["shot.png"])
    }
}
