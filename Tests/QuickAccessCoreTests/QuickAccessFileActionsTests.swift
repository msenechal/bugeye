import BugeyeCore
import BugeyeTestSupport
import Foundation
import QuickAccessCore
import Testing

@Suite struct QuickAccessFileActionsTests {
    let metadata = FakeFileMetadataStore()
    var actions: QuickAccessFileActions { QuickAccessFileActions(writer: CaptureFileWriter(metadata: metadata)) }

    func capture(
        in dir: TempDirectory, named name: String = "Screenshot 2026-11-27 at 14.03.12.png",
        kind: CaptureKind = .screenshot, bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    ) throws -> CaptureItem {
        let url = dir.file(name)
        try Data(bytes).write(to: url)
        let id = CaptureID()
        try metadata.setValue(Data(id.description.utf8), CaptureFileWriter.identityAttribute, at: url)
        return CaptureItem(
            id: id, fileURL: url, isSaved: false, kind: kind, createdAt: Date(timeIntervalSince1970: 1_795_784_592),
            pixelsPerPoint: 2, duration: kind == .screenshot ? nil : 42)
    }

    // MARK: Copy

    @Test func copyOfAScreenshotHoldsThePNGAndTheURL() throws {
        let dir = try TempDirectory("qa-copy")
        defer { dir.remove() }
        let item = try capture(in: dir)
        #expect(
            actions.run(.readForCopy(item))
                == .copied(ClipboardPayload(png: Data([0x89, 0x50, 0x4E, 0x47]), fileURL: item.fileURL)))
    }

    @Test func copyOfARecordingHoldsOnlyTheURL() throws {
        let dir = try TempDirectory("qa-copy")
        defer { dir.remove() }
        let item = try capture(in: dir, named: "Recording.mp4", kind: .recording)
        #expect(actions.run(.readForCopy(item)) == .copied(ClipboardPayload(fileURL: item.fileURL)))
    }

    @Test(arguments: [CaptureKind.screenshot, .recording, .gif])
    func copyOfAMissingFileFails(_ kind: CaptureKind) throws {
        let dir = try TempDirectory("qa-copy")
        defer { dir.remove() }
        let item = try capture(in: dir, named: "Gone.png", kind: kind)
        try FileManager.default.removeItem(at: item.fileURL)
        #expect(actions.run(.readForCopy(item)) == .copyFailed(name: "Gone.png"))
    }

    // MARK: Save

    @Test func saveMovesIntoTheFolderKeepingTheIdentity() throws {
        let temp = try TempDirectory("qa-temp")
        let saves = try TempDirectory("qa-saves")
        defer { temp.remove(); saves.remove() }
        let item = try capture(in: temp)
        let result = actions.run(.save(item, folder: saves.url, displayPath: "~/Pictures/Bugeye/"))
        var expected = item
        expected.fileURL = saves.file(item.fileURL.lastPathComponent)
        expected.isSaved = true
        #expect(result == .saved(expected, previousURL: item.fileURL))
        #expect(try saves.contents() == [item.fileURL.lastPathComponent])
        #expect(try temp.contents().isEmpty)
        let id = try metadata.value(CaptureFileWriter.identityAttribute, at: expected.fileURL)
        #expect(id == Data(item.id.description.utf8))
    }

    @Test func saveKeepsTheSourceExtension() throws {
        let temp = try TempDirectory("qa-temp")
        let saves = try TempDirectory("qa-saves")
        defer { temp.remove(); saves.remove() }
        let item = try capture(in: temp, named: "Recording 2026-11-27 at 14.03.12.mov", kind: .recording)
        guard case .saved(let saved, _) = actions.run(.save(item, folder: saves.url, displayPath: "x")) else {
            Issue.record("not saved")
            return
        }
        #expect(saved.fileURL.lastPathComponent == "Recording 2026-11-27 at 14.03.12.mov")
    }

    @Test func saveCreatesAMissingFolder() throws {
        let temp = try TempDirectory("qa-temp")
        let root = try TempDirectory("qa-root")
        defer { temp.remove(); root.remove() }
        let item = try capture(in: temp)
        let folder = root.url.appendingPathComponent("Pictures/Bugeye", isDirectory: true)
        guard case .saved(let saved, _) = actions.run(.save(item, folder: folder, displayPath: "x")) else {
            Issue.record("not saved")
            return
        }
        #expect(saved.fileURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func saveOntoAClashGetsASuffix() throws {
        let temp = try TempDirectory("qa-temp")
        let saves = try TempDirectory("qa-saves")
        defer { temp.remove(); saves.remove() }
        let item = try capture(in: temp)
        try Data([1]).write(to: saves.file(item.fileURL.lastPathComponent))
        guard case .saved(let saved, _) = actions.run(.save(item, folder: saves.url, displayPath: "x")) else {
            Issue.record("not saved")
            return
        }
        #expect(saved.fileURL.lastPathComponent == "Screenshot 2026-11-27 at 14.03.12 (2).png")
        #expect(try Data(contentsOf: saves.file(item.fileURL.lastPathComponent)) == Data([1]))
    }

    @Test func aFolderThatIsAFileIsUnavailable() throws {
        let temp = try TempDirectory("qa-temp")
        defer { temp.remove() }
        let item = try capture(in: temp)
        let notAFolder = temp.file("Bugeye")
        try Data().write(to: notAFolder)
        #expect(
            actions.run(.save(item, folder: notAFolder, displayPath: "~/Pictures/Bugeye/"))
                == .saveFolderUnavailable(path: "~/Pictures/Bugeye/"))
        #expect(FileManager.default.fileExists(atPath: item.fileURL.path))
    }

    @Test func aMoveFailureGivesTheWritersText() throws {
        let temp = try TempDirectory("qa-temp")
        let saves = try TempDirectory("qa-saves")
        defer { temp.remove(); saves.remove() }
        let item = try capture(in: temp)
        try FileManager.default.removeItem(at: item.fileURL)
        #expect(
            actions.run(.save(item, folder: saves.url, displayPath: "x"))
                == .saveFailed("The file couldn't be moved into place."))
    }

    // MARK: Save As…

    @Test func saveAsCopiesWithANewIdentity() throws {
        let temp = try TempDirectory("qa-temp")
        let dest = try TempDirectory("qa-dest")
        defer { temp.remove(); dest.remove() }
        var item = try capture(in: temp)
        item.isSaved = true
        try metadata.setValue(Data("safari".utf8), "dev.msenechal.bugeye.provenance", at: item.fileURL)
        let newID = CaptureID()
        let target = dest.file("Copy.png")
        let result = actions.run(.saveAs(item, to: target, newID: newID))
        #expect(
            result
                == .savedCopy(
                    CaptureItem(
                        id: newID, fileURL: target, isSaved: true, kind: .screenshot, createdAt: item.createdAt,
                        pixelsPerPoint: 2)))
        #expect(try metadata.value(CaptureFileWriter.identityAttribute, at: target) == Data(newID.description.utf8))
        #expect(try metadata.value("dev.msenechal.bugeye.provenance", at: target) == Data("safari".utf8))
        #expect(
            try metadata.value(CaptureFileWriter.identityAttribute, at: item.fileURL) == Data(item.id.description.utf8))
        #expect(try Data(contentsOf: target) == Data(contentsOf: item.fileURL))
    }

    @Test func saveAsOntoItselfChangesNothing() throws {
        let temp = try TempDirectory("qa-temp")
        defer { temp.remove() }
        let item = try capture(in: temp)
        #expect(actions.run(.saveAs(item, to: item.fileURL, newID: CaptureID())) == .saveAsUnchanged)
        #expect(
            try metadata.value(CaptureFileWriter.identityAttribute, at: item.fileURL) == Data(item.id.description.utf8))
    }

    @Test func saveAsOfAMissingFileFails() throws {
        let temp = try TempDirectory("qa-temp")
        defer { temp.remove() }
        let item = try capture(in: temp)
        try FileManager.default.removeItem(at: item.fileURL)
        guard case .saveAsFailed(let text) = actions.run(.saveAs(item, to: temp.file("Copy.png"), newID: CaptureID()))
        else {
            Issue.record("expected a failure")
            return
        }
        #expect(!text.isEmpty)
        #expect(try temp.contents().isEmpty)
    }

    // MARK: Delete

    @Test func deleteRemovesAndAMissingFileCountsAsDone() throws {
        let temp = try TempDirectory("qa-temp")
        defer { temp.remove() }
        let item = try capture(in: temp)
        let remove: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        #expect(QuickAccessFileActions.delete(item.fileURL, using: remove) == .deleted)
        #expect(try temp.contents().isEmpty)
        #expect(QuickAccessFileActions.delete(item.fileURL, using: remove) == .deleted)
    }

    @Test func aDeleteFailureGivesItsText() throws {
        let temp = try TempDirectory("qa-temp")
        defer { temp.remove() }
        let item = try capture(in: temp)
        struct Locked: LocalizedError { var errorDescription: String? { "It's locked." } }
        #expect(
            QuickAccessFileActions.delete(item.fileURL, using: { _ in throw Locked() }) == .deleteFailed("It's locked.")
        )
    }
}
