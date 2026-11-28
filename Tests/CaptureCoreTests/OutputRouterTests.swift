import BugeyeCore
import BugeyeTestSupport
import CaptureCore
import Foundation
import Testing

@Suite struct OutputRouterTests {
    let png = Data("png".utf8)
    let time = Date(timeIntervalSince1970: 1_795_784_592)  // 27 Nov 2026 14:03:12 in Paris
    let paris = TimeZone(identifier: "Europe/Paris")!

    struct Setup {
        let dir = try! TempDirectory()
        let metadata = FakeFileMetadataStore()
        let clipboard = FakeClipboard()
        var save: URL { dir.url.appendingPathComponent("Pictures/Bugeye", isDirectory: true) }
        var temp: URL { dir.url.appendingPathComponent("Caches/Captures", isDirectory: true) }
        var router: OutputRouter {
            OutputRouter(writer: CaptureFileWriter(metadata: metadata), clipboard: clipboard)
        }
    }

    func request(_ setup: Setup, settings: CaptureSettings = CaptureSettings(), id: CaptureID = CaptureID())
        -> OutputRequest
    {
        OutputRequest(
            png: png, id: id, createdAt: time, pixelsPerPoint: 2, settings: settings, saveFolder: setup.save,
            displayedSaveFolder: "~/Pictures/Bugeye/", tempFolder: setup.temp, timeZone: paris)
    }

    @Test func savesToTheFolderThenCopiesPNGAndFileURL() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(at: setup.save, withIntermediateDirectories: true)
        let id = CaptureID()
        let result = setup.router.deliver(request(setup, id: id))
        let item = try #require(result.item)
        #expect(item.fileURL.lastPathComponent == "Screenshot 2026-11-27 at 14.03.12.png")
        #expect(item.fileURL.deletingLastPathComponent().standardizedFileURL == setup.save.standardizedFileURL)
        #expect(item.isSaved && item.kind == .screenshot && item.createdAt == time && item.pixelsPerPoint == 2)
        #expect(item.id == id)
        #expect(try Data(contentsOf: item.fileURL) == png)
        #expect(
            try setup.metadata.value(CaptureFileWriter.identityAttribute, at: item.fileURL) == Data(id.description.utf8)
        )
        #expect(setup.clipboard.written == [ClipboardPayload(png: png, fileURL: item.fileURL)])
        #expect(result.notices.isEmpty)
        #expect(result.logs == ["saved Screenshot 2026-11-27 at 14.03.12.png"])
    }

    @Test func aTakenNameGetsASuffixAndNothingIsOverwritten() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(at: setup.save, withIntermediateDirectories: true)
        let existing = setup.save.appendingPathComponent("Screenshot 2026-11-27 at 14.03.12.png")
        try Data("old".utf8).write(to: existing)
        let item = try #require(setup.router.deliver(request(setup)).item)
        #expect(item.fileURL.lastPathComponent == "Screenshot 2026-11-27 at 14.03.12 (2).png")
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
    }

    @Test func aMissingFolderFallsBackToTempWithTheNotice() throws {
        let setup = Setup()
        let result = setup.router.deliver(request(setup))
        let item = try #require(result.item)
        #expect(!item.isSaved)
        #expect(item.fileURL.deletingLastPathComponent().standardizedFileURL == setup.temp.standardizedFileURL)
        #expect(
            result.notices == [
                Notice(
                    title: "Couldn't save to folder",
                    body:
                        "~/Pictures/Bugeye/ is unavailable. The capture is kept temporarily; use Save in Quick Access.")
            ])
        #expect(!FileManager.default.fileExists(atPath: setup.save.path))
        #expect(result.logs.first?.hasPrefix("kept in temp Screenshot 2026-11-27 at 14.03.12.png: ") == true)
        #expect(setup.clipboard.written == [ClipboardPayload(png: png, fileURL: item.fileURL)])
    }

    @Test func aFolderThatIsAFileFallsBackToTemp() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(
            at: setup.save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: setup.save)
        let result = setup.router.deliver(request(setup))
        #expect(result.item?.isSaved == false)
        #expect(result.notices.map(\.title) == ["Couldn't save to folder"])
    }

    @Test func noFreeNameInTheFolderFallsBackToTemp() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(at: setup.save, withIntermediateDirectories: true)
        let name = "Screenshot 2026-11-27 at 14.03.12.png"
        for attempt in 1...CaptureFileWriter.maxNameAttempts {
            FileManager.default.createFile(
                atPath: setup.save.appendingPathComponent(CaptureFileNamer.candidate(name, attempt: attempt)).path,
                contents: nil)
        }
        let result = setup.router.deliver(request(setup))
        #expect(result.item?.isSaved == false)
        #expect(result.notices.map(\.title) == ["Couldn't save to folder"])
    }

    @Test func savingOffWritesToTempWithoutANotice() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(at: setup.save, withIntermediateDirectories: true)
        let result = setup.router.deliver(request(setup, settings: CaptureSettings(saveToFolder: false)))
        #expect(result.item?.isSaved == false)
        #expect(result.notices.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.save.path).isEmpty)
    }

    @Test func copyOffLeavesTheClipboardAlone() throws {
        let setup = Setup()
        try FileManager.default.createDirectory(at: setup.save, withIntermediateDirectories: true)
        _ = setup.router.deliver(request(setup, settings: CaptureSettings(copyToClipboard: false)))
        #expect(setup.clipboard.written.isEmpty)
    }

    @Test func whenEvenTheTempWriteFailsThePNGAloneIsCopied() throws {
        let setup = Setup()
        // The temp folder's parent is a file: the temp folder can't be created.
        try Data().write(to: setup.dir.url.appendingPathComponent("Caches"))
        let result = setup.router.deliver(request(setup, settings: CaptureSettings(saveToFolder: false)))
        #expect(result.item == nil)
        #expect(setup.clipboard.written == [ClipboardPayload(png: png)])
        #expect(
            result.notices == [
                Notice(title: "Capture failed", body: "Couldn't write the file. The image is on the clipboard.")
            ])
    }

    @Test func whenEvenTheTempWriteFailsWithCopyOffNothingIsCopied() throws {
        let setup = Setup()
        try Data().write(to: setup.dir.url.appendingPathComponent("Caches"))
        let result = setup.router.deliver(
            request(setup, settings: CaptureSettings(copyToClipboard: false, saveToFolder: false)))
        #expect(result.item == nil)
        #expect(setup.clipboard.written.isEmpty)
        #expect(result.notices == [Notice(title: "Capture failed", body: "Couldn't write the file.")])
    }

    @Test func folderFallbackAndTempFailureGiveBothNotices() throws {
        let setup = Setup()
        try Data().write(to: setup.dir.url.appendingPathComponent("Caches"))
        let result = setup.router.deliver(request(setup))
        #expect(result.notices.map(\.title) == ["Couldn't save to folder", "Capture failed"])
    }
}

@Suite struct TempJanitorTests {
    @Test func filesOlderThanADayAreCandidatesWithTheirIdentity() throws {
        let dir = try TempDirectory()
        let metadata = FakeFileMetadataStore()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = dir.url.appendingPathComponent("old.png")
        let fresh = dir.url.appendingPathComponent("fresh.png")
        let noID = dir.url.appendingPathComponent("noid.png")
        for url in [old, fresh, noID] { FileManager.default.createFile(atPath: url.path, contents: Data()) }
        let id = CaptureID()
        try metadata.setValue(Data(id.description.utf8), CaptureFileWriter.identityAttribute, at: old)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 3600)], ofItemAtPath: noID.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-23 * 3600)], ofItemAtPath: fresh.path)

        let janitor = TempJanitor(metadata: metadata)
        let candidates = janitor.candidates(in: dir.url, now: now).sorted { $0.url.path < $1.url.path }
        #expect(candidates.map(\.url.lastPathComponent) == ["noid.png", "old.png"])
        #expect(candidates.map(\.id) == [nil, id])
        #expect(janitor.remove(candidates) == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path) == ["fresh.png"])
    }

    @Test func aMissingFolderHasNoCandidates() throws {
        let dir = try TempDirectory()
        #expect(
            TempJanitor(metadata: FakeFileMetadataStore()).candidates(
                in: dir.url.appendingPathComponent("x"), now: Date()
            ).isEmpty)
    }
}
