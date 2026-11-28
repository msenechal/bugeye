import BugeyeTestSupport
import Foundation
import Testing

@testable import BugeyeCore

/// The writer's Wave 1 additions (contracts spec §4.1.2): create, move, copy, requireExisting, error texts.
@Suite struct CaptureFileWriterContractTests {
    let dir: TempDirectory
    let dest: URL
    let store = FakeFileMetadataStore()
    var writer: CaptureFileWriter { CaptureFileWriter(metadata: store) }
    let oldID = "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"

    init() throws {
        dir = try TempDirectory("writer-contract")
        dest = dir.url.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    }

    func makeCapture(_ name: String = "shot.png", in folder: URL? = nil) throws -> URL {
        let url = (folder ?? dir.url).appendingPathComponent(name)
        try Data("old".utf8).write(to: url)
        try store.setValue(Data(oldID.utf8), "dev.msenechal.bugeye.id", at: url)
        try store.setValue(Data(#"{"app":"Arc"}"#.utf8), "dev.msenechal.bugeye.provenance", at: url)
        try store.setValue(Data("plist".utf8), "com.apple.metadata:kMDItemWhereFroms", at: url)
        try store.setValue(Data("q".utf8), "com.apple.quarantine", at: url)
        return url
    }

    func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    let preserved = [
        "com.apple.metadata:kMDItemWhereFroms", "dev.msenechal.bugeye.id", "dev.msenechal.bugeye.provenance",
    ]

    // MARK: create

    @Test func createWritesANewFileWithItsIdentity() throws {
        defer { dir.remove() }
        let id = CaptureID()
        let url = try writer.create(Data("png".utf8), named: "a.png", in: dest, identity: id)
        #expect(url.lastPathComponent == "a.png")
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == dest.standardizedFileURL.path)
        #expect(try Data(contentsOf: url) == Data("png".utf8))
        #expect(try store.names(at: url) == ["dev.msenechal.bugeye.id"])
        #expect(try store.value("dev.msenechal.bugeye.id", at: url) == Data(id.description.utf8))
        #expect(try contents(dest) == ["a.png"])
    }

    @Test func createSuffixesOnAClashAndNeverTouchesTheExistingFile() throws {
        defer { dir.remove() }
        let existing = try makeCapture("a.b.png", in: dest)
        let url = try writer.create(Data("new".utf8), named: "a.b.png", in: dest, identity: CaptureID())
        #expect(url.lastPathComponent == "a.b (2).png")
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
        #expect(try store.value("dev.msenechal.bugeye.id", at: existing) == Data(oldID.utf8))
        let third = try writer.create(Data("3".utf8), named: "a.b.png", in: dest, identity: CaptureID())
        #expect(third.lastPathComponent == "a.b (3).png")
        #expect(try contents(dest) == ["a.b (2).png", "a.b (3).png", "a.b.png"])
    }

    @Test func createThrowsNoFreeNameAfter999Attempts() throws {
        defer { dir.remove() }
        for attempt in 1...999 {
            try Data().write(to: dest.appendingPathComponent(CaptureFileNamer.candidate("a.png", attempt: attempt)))
        }
        #expect(throws: CaptureFileWriter.NoFreeName(name: "a.png")) {
            try writer.create(Data("x".utf8), named: "a.png", in: dest, identity: CaptureID())
        }
        #expect(try contents(dest).count == 999)
    }

    @Test func aFailedCreateLeavesNothing() throws {
        defer { dir.remove() }
        store.failSetting("dev.msenechal.bugeye.id")
        #expect(throws: FakeFileMetadataStore.InjectedFailure.self) {
            try writer.create(Data("x".utf8), named: "a.png", in: dest, identity: CaptureID())
        }
        #expect(try contents(dest) == [])
    }

    // MARK: move

    @Test func aSameVolumeMoveKeepsEveryAttribute() throws {
        defer { dir.remove() }
        let source = try makeCapture()
        let url = try writer.move(source, into: dest)
        #expect(url.lastPathComponent == "shot.png")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        #expect(try store.names(at: url) == (preserved + ["com.apple.quarantine"]).sorted())
    }

    @Test func aMoveWithANewIdentityReplacesTheID() throws {
        defer { dir.remove() }
        let source = try makeCapture()
        let id = CaptureID()
        let url = try writer.move(source, into: dest, named: "renamed.png", identity: .new(id))
        #expect(url.lastPathComponent == "renamed.png")
        #expect(try store.value("dev.msenechal.bugeye.id", at: url) == Data(id.description.utf8))
        #expect(try store.value("dev.msenechal.bugeye.provenance", at: url) == Data(#"{"app":"Arc"}"#.utf8))
    }

    @Test func aMoveSuffixesOnAClash() throws {
        defer { dir.remove() }
        let existing = try makeCapture("shot.png", in: dest)
        let source = try makeCapture()
        let url = try writer.move(source, into: dest)
        #expect(url.lastPathComponent == "shot (2).png")
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
        #expect(try contents(dest) == ["shot (2).png", "shot.png"])
    }

    @Test func aCrossVolumeMoveKeepsThePreservedAttributesAndRemovesTheSource() throws {
        defer { dir.remove() }
        var writer = self.writer
        writer.simulateCrossVolume = true
        let source = try makeCapture()
        let id = CaptureID()
        let url = try writer.move(source, into: dest, identity: .new(id))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        #expect(try store.names(at: url) == preserved)
        #expect(try store.value("dev.msenechal.bugeye.id", at: url) == Data(id.description.utf8))
        #expect(try contents(dest) == ["shot.png"])
    }

    @Test func aCrossVolumeMoveSuffixesOnAClash() throws {
        defer { dir.remove() }
        var writer = self.writer
        writer.simulateCrossVolume = true
        _ = try makeCapture("shot.png", in: dest)
        let url = try writer.move(try makeCapture(), into: dest)
        #expect(url.lastPathComponent == "shot (2).png")
        #expect(try contents(dest) == ["shot (2).png", "shot.png"])
    }

    @Test func aFailedCrossVolumeMoveLeavesTheSourceAndNoPartialFile() throws {
        defer { dir.remove() }
        var writer = self.writer
        writer.simulateCrossVolume = true
        let source = try makeCapture()
        store.failSetting("dev.msenechal.bugeye.provenance")
        #expect(throws: FakeFileMetadataStore.InjectedFailure.self) { try writer.move(source, into: dest) }
        #expect(try Data(contentsOf: source) == Data("old".utf8))
        #expect(try store.value("dev.msenechal.bugeye.id", at: source) == Data(oldID.utf8))
        #expect(try contents(dest) == [])
    }

    @Test func aMoveOfAMissingSourceThrowsAndLeavesNothing() throws {
        defer { dir.remove() }
        #expect(throws: (any Error).self) { try writer.move(dir.file("missing.png"), into: dest) }
        #expect(try contents(dest) == [])
    }

    // MARK: write(requireExisting:)

    @Test func requireExistingReplacesAnExistingTargetKeepingItsAttributes() throws {
        defer { dir.remove() }
        let url = try makeCapture()
        try writer.write(Data("new".utf8), to: url, requireExisting: true)
        #expect(try Data(contentsOf: url) == Data("new".utf8))
        #expect(try store.names(at: url) == preserved)
        #expect(try dir.contents() == ["dest", "shot.png"])
    }

    @Test func requireExistingOnAMissingTargetThrowsAndCreatesNothing() throws {
        defer { dir.remove() }
        let url = dir.file("gone.png")
        #expect(throws: CaptureFileWriter.TargetMissing(url: url)) {
            try writer.write(Data("new".utf8), to: url, requireExisting: true)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try dir.contents() == ["dest"])
    }

    // MARK: copy

    @Test func copyKeepsThePreservedAttributesWithANewIdentityAndLeavesTheSource() throws {
        defer { dir.remove() }
        let source = try makeCapture()
        let target = dest.appendingPathComponent("copy.png")
        let id = CaptureID()
        try writer.copy(source, to: target, identity: .new(id))
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        #expect(try store.names(at: target) == preserved)
        #expect(try store.value("dev.msenechal.bugeye.id", at: target) == Data(id.description.utf8))
        #expect(try Data(contentsOf: source) == Data("old".utf8))
        #expect(try store.value("dev.msenechal.bugeye.id", at: source) == Data(oldID.utf8))
        #expect(try store.value("com.apple.quarantine", at: source) == Data("q".utf8))
        #expect(try contents(dest) == ["copy.png"])
    }

    @Test func copyReplacesAnExistingDestination() throws {
        defer { dir.remove() }
        let source = try makeCapture()
        let target = dest.appendingPathComponent("copy.png")
        try Data("older".utf8).write(to: target)
        try writer.copy(source, to: target, identity: .new(CaptureID()))
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        #expect(try contents(dest) == ["copy.png"])
    }

    @Test func aFailedCopyLeavesNoTempFile() throws {
        defer { dir.remove() }
        let source = try makeCapture()
        store.failSetting("dev.msenechal.bugeye.id")
        #expect(throws: FakeFileMetadataStore.InjectedFailure.self) {
            try writer.copy(source, to: dest.appendingPathComponent("copy.png"), identity: .new(CaptureID()))
        }
        #expect(try contents(dest) == [])
    }

    // MARK: descriptions (K30)

    @Test func errorDescriptionsAreSettled() {
        #expect(
            CaptureFileWriter.NoFreeName(name: "a.png").errorDescription
                == "Too many files are already named like \u{201C}a.png\u{201D}.")
        #expect(CaptureFileWriter.RenameFailed(errno: 1).errorDescription == "The file couldn't be moved into place.")
        #expect(
            CaptureFileWriter.TargetMissing(url: URL(fileURLWithPath: "/x/shot.png")).errorDescription
                == "\u{201C}shot.png\u{201D} was moved or deleted.")
    }
}
