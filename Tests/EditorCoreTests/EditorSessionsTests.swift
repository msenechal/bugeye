import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import EditorCore
import Foundation
import Testing

/// Records what the sessions ask of the shell and answers from scripts.
@MainActor
final class FakeEditorHost: EditorHost {
    var log: [String] = []
    var loadResult: Result<Size2D, EditorLoadFailure> = .success(Size2D(width: 40, height: 30))
    var saveAnswers: [SaveAnswer] = []
    var goneAnswers: [Bool] = []
    var saveAsURLs: [URL?] = []
    var failures: [(name: String, message: String)] = []
    var exportError: (any Error)?
    var exportCount = 0
    var onExport: (() -> Void)?
    var blockExports = false
    private var pending: [CheckedContinuation<Void, Never>] = []

    var pendingExports: Int { pending.count }
    func releaseExport() { if !pending.isEmpty { pending.removeFirst().resume() } }

    func load(_ item: CaptureItem) async -> Result<Size2D, EditorLoadFailure> {
        log.append("load \(item.fileURL.lastPathComponent)")
        return loadResult
    }
    func showWindow(for session: EditorSession) { log.append("show \(session.name)") }
    func bringForward(_ id: CaptureID) { log.append("forward") }
    func retitle(_ session: EditorSession) { log.append("retitle \(session.name)") }
    func commitPendingEdits(_ session: EditorSession) { log.append("commit") }
    func export(_ session: EditorSession, state: EditorState) async throws -> ExportedImage {
        exportCount += 1
        let n = exportCount
        onExport?()
        if blockExports { await withCheckedContinuation { pending.append($0) } }
        if let exportError { throw exportError }
        return ExportedImage(
            png: Data("png-\(n)-\(state.annotations.count)".utf8),
            preview: try? PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 1, green: 2, blue: 3)))
    }
    func askToSave(_ session: EditorSession) async -> SaveAnswer {
        log.append("ask \(session.name)")
        return saveAnswers.isEmpty ? .cancel : saveAnswers.removeFirst()
    }
    func showGoneAlert(_ session: EditorSession) async -> Bool {
        log.append("gone \(session.name)")
        return goneAnswers.isEmpty ? false : goneAnswers.removeFirst()
    }
    func chooseSaveAsURL(_ session: EditorSession) async -> URL? {
        log.append("panel")
        return saveAsURLs.isEmpty ? nil : saveAsURLs.removeFirst()
    }
    func showSaveFailed(_ session: EditorSession, name: String, message: String) async {
        failures.append((name, message))
    }
}

@MainActor
final class SessionFixture {
    let dir: TempDirectory
    let saveFolder: URL
    let store = FakeFileMetadataStore()
    let bus = CaptureEventBus()
    let recorder: CaptureEventRecorder
    let clipboard = FakeClipboard()
    let notifier = FakeNotifier()
    var policies: [ActivationPolicy] = []
    var order: [String] = []
    let host = FakeEditorHost()
    var documentWindows: DocumentWindows!
    var sessions: EditorSessions!
    var logLines: [String] = []
    let id = CaptureID()
    let oldID = "0d3c5e7a-1111-4222-8333-944455556666"
    var item: CaptureItem
    private var subscription: CaptureSubscription?

    init() throws {
        dir = try TempDirectory("editor-sessions")
        saveFolder = dir.url.appendingPathComponent("Bugeye", isDirectory: true)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        recorder = CaptureEventRecorder(bus)
        item = CaptureItem(
            id: id, fileURL: saveFolder.appendingPathComponent("Shot.png"), isSaved: true, kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 0), pixelsPerPoint: 2)
        documentWindows = DocumentWindows(apply: { [unowned self] policy in
            self.policies.append(policy)
            self.order.append("\(policy)")
        })
        subscription = bus.subscribe { [unowned self] event in self.order.append(event.change.rawValue) }
        let folder = saveFolder
        sessions = EditorSessions(
            environment: EditorEnvironment(
                bus: bus, documentWindows: documentWindows, writer: CaptureFileWriter(metadata: store),
                clipboard: clipboard, notifier: notifier, saveFolder: { folder },
                log: { [unowned self] in self.logLines.append($0) },
                dragFolder: dir.url.appendingPathComponent("Bugeye-Drag", isDirectory: true)))
        sessions.host = host
        try Data("original".utf8).write(to: item.fileURL)
        try store.setValue(Data(id.description.utf8), "dev.msenechal.bugeye.id", at: item.fileURL)
        try store.setValue(Data("{}".utf8), "dev.msenechal.bugeye.provenance", at: item.fileURL)
        bus.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
    }

    func openAndEdit() async -> EditorSession {
        await sessions.open(item)
        let session = sessions.session(id)!
        session.document!.apply { $0.annotations.append(Annotation(shape: .step(center: .zero))) }
        return session
    }

    func contents(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }
    func idAttribute(_ url: URL) -> String? {
        (try? store.value("dev.msenechal.bugeye.id", at: url))?.map { String(decoding: $0, as: UTF8.self) }
    }
}

@MainActor
@Suite struct EditorSessionsTests {
    @Test func openingShowsThenOpensTheDocumentWindowThenPublishesEditingStarted() async throws {
        let f = try SessionFixture()
        f.order = []
        await f.sessions.open(f.item)
        #expect(f.host.log == ["load Shot.png", "show Shot.png"])
        #expect(f.order == ["regular", "editingStarted"])
        #expect(f.recorder.events.last?.origin == "editor")
        #expect(f.sessions.session(f.id)?.isOpen == true)
        #expect(f.sessions.session(f.id)?.imageSize == Size2D(width: 40, height: 30))
        #expect(f.logLines == ["open Shot.png"])
    }

    @Test func aSecondOpenBringsTheEditorForward() async throws {
        let f = try SessionFixture()
        await f.sessions.open(f.item)
        await f.sessions.open(f.item)
        #expect(f.host.log == ["load Shot.png", "show Shot.png", "forward"])
        #expect(f.documentWindows.openCount == 1)
    }

    @Test func aFailedDecodeOnlyPostsTheNotice() async throws {
        let f = try SessionFixture()
        f.host.loadResult = .failure(EditorLoadFailure(reason: "missing"))
        let before = f.recorder.events.count
        await f.sessions.open(f.item)
        #expect(
            f.notifier.posts == [
                FakeNotifier.Post(title: "Couldn't open capture", body: "Shot.png is missing or unreadable.")
            ])
        #expect(f.recorder.events.count == before)
        #expect(f.documentWindows.openCount == 0)
        #expect(f.sessions.session(f.id) == nil)
        #expect(f.logLines == ["open failed Shot.png: missing"])
        f.host.loadResult = .success(Size2D(width: 1, height: 1))
        await f.sessions.open(f.item)
        #expect(f.sessions.session(f.id)?.isOpen == true)
    }

    @Test func closingPublishesEditingEndedAndClosedExactlyOnceWithTheLastKnownItem() async throws {
        let f = try SessionFixture()
        await f.sessions.open(f.item)
        f.bus.publish(CaptureEvent(change: .deleted, item: f.item, origin: "quickAccess"))
        f.order = []
        f.sessions.didClose(f.id)
        f.sessions.didClose(f.id)
        #expect(f.order == ["editingEnded", "accessory"])
        #expect(f.recorder.events.last?.item == f.item)
        #expect(f.documentWindows.underflows == 0)
        #expect(f.logLines.last == "close Shot.png")
    }

    @Test func savedAndMovedRepointTheSessionAndDeletedMarksItGone() async throws {
        let f = try SessionFixture()
        await f.sessions.open(f.item)
        var moved = f.item
        moved.fileURL = f.saveFolder.appendingPathComponent("Renamed.png")
        f.bus.publish(CaptureEvent(change: .moved, item: moved, previousURL: f.item.fileURL, origin: "quickAccess"))
        #expect(f.sessions.session(f.id)?.item.fileURL == moved.fileURL)
        #expect(f.host.log.last == "retitle Renamed.png")
        f.bus.publish(CaptureEvent(change: .deleted, item: moved, origin: "quickAccess"))
        #expect(f.sessions.session(f.id)?.isGone == true)
    }

    @Test func saveWritesInPlaceKeepingTheAttributesThenMarksSavedAndPublishesEdited() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        let outcome = await f.sessions.save(f.id)
        #expect(outcome == .saved)
        #expect(f.contents(f.item.fileURL) == "png-1-1")
        #expect(f.idAttribute(f.item.fileURL) == f.id.description)
        #expect(try f.store.value("dev.msenechal.bugeye.provenance", at: f.item.fileURL) == Data("{}".utf8))
        #expect(session.document?.isDirty == false)
        let edited = try #require(f.recorder.events.last)
        #expect(edited.change == .edited && edited.origin == "editor" && edited.item == f.item)
        #expect(edited.preview?.width == 1)
        #expect(f.logLines.contains { $0.hasPrefix("saved Shot.png in ") && $0.hasSuffix(" ms") })
        #expect(try f.dirContents() == ["Bugeye"])
    }

    @Test func saveOnACleanDocumentWhoseFileExistsDoesNothing() async throws {
        let f = try SessionFixture()
        await f.sessions.open(f.item)
        #expect(await f.sessions.save(f.id) == .unchanged)
        #expect(f.host.exportCount == 0)
        #expect(f.contents(f.item.fileURL) == "original")
    }

    @Test func saveOnAGoneFileShowsTheAlertAndNeverWrites() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        f.bus.publish(CaptureEvent(change: .deleted, item: f.item, origin: "quickAccess"))
        try FileManager.default.removeItem(at: f.item.fileURL)
        #expect(await f.sessions.save(f.id) == .cancelled)
        #expect(f.host.log.suffix(2) == ["commit", "gone Shot.png"])
        #expect(f.host.exportCount == 0)
        #expect(!FileManager.default.fileExists(atPath: f.item.fileURL.path))
        #expect(f.sessions.session(f.id)?.document?.isDirty == true)
    }

    @Test func aFileMovedInFinderIsFoundAtSaveTimeToo() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        try FileManager.default.removeItem(at: f.item.fileURL)
        #expect(await f.sessions.save(f.id) == .cancelled)
        #expect(f.host.log.last == "gone Shot.png")
        #expect(!FileManager.default.fileExists(atPath: f.item.fileURL.path))
    }

    @Test func aSaveRacingQuickAccessSaveIsRedoneOnceAtTheNewURL() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        let newURL = f.saveFolder.appendingPathComponent("Moved.png")
        f.host.onExport = { [unowned f] in
            // Quick Access moves the file while the editor renders; the session hears about it late.
            try? FileManager.default.moveItem(at: f.item.fileURL, to: newURL)
            var moved = f.item
            moved.fileURL = newURL
            f.bus.publish(CaptureEvent(change: .saved, item: moved, previousURL: f.item.fileURL, origin: "quickAccess"))
        }
        #expect(await f.sessions.save(f.id) == .saved)
        #expect(f.contents(newURL) == "png-1-1")
        #expect(f.idAttribute(newURL) == f.id.description)
        #expect(!FileManager.default.fileExists(atPath: f.item.fileURL.path))
        #expect(f.recorder.events.last?.change == .edited)
        #expect(f.recorder.events.last?.item.fileURL == newURL)
    }

    @Test func aTargetMissingWithNoNewURLShowsTheGoneAlert() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        f.host.onExport = { [unowned f] in try? FileManager.default.removeItem(at: f.item.fileURL) }
        #expect(await f.sessions.save(f.id) == .cancelled)
        #expect(f.host.log.last == "gone Shot.png")
        #expect(!FileManager.default.fileExists(atPath: f.item.fileURL.path))
        #expect(try f.dirContents() == ["Bugeye"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.saveFolder.path).isEmpty)
    }

    @Test func goneSaveAsAfterADeleteKeepsTheIDAndPublishesCreated() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        f.bus.publish(CaptureEvent(change: .deleted, item: f.item, origin: "quickAccess"))
        try FileManager.default.removeItem(at: f.item.fileURL)
        let chosen = f.saveFolder.appendingPathComponent("Again.png")
        f.host.goneAnswers = [true]
        f.host.saveAsURLs = [chosen]
        #expect(await f.sessions.save(f.id) == .saved)
        #expect(f.contents(chosen) == "png-1-1")
        #expect(f.idAttribute(chosen) == f.id.description)
        let created = try #require(f.recorder.events.last)
        #expect(created.change == .created && created.origin == "editor" && created.preview != nil)
        #expect(created.item.fileURL == chosen && created.item.isSaved && created.item.id == f.id)
        #expect(session.item.fileURL == chosen && !session.isGone)
        #expect(session.document?.isDirty == false)
        #expect(f.host.log.last == "retitle Again.png")
    }

    @Test func goneSaveAsWhileTheBusStillKnowsItPublishesMovedThenEdited() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        try FileManager.default.removeItem(at: f.item.fileURL)  // moved in Finder: the bus doesn't know
        let elsewhere = f.dir.url.appendingPathComponent("Elsewhere.png")
        f.host.goneAnswers = [true]
        f.host.saveAsURLs = [elsewhere]
        #expect(await f.sessions.save(f.id) == .saved)
        let last = f.recorder.events.suffix(2)
        #expect(last.map(\.change) == [.moved, .edited])
        #expect(last.first?.previousURL == f.item.fileURL)
        #expect(last.first?.item.isSaved == false)
        #expect(last.last?.item.fileURL == elsewhere)
        #expect(f.bus.item(f.id)?.fileURL == elsewhere)
    }

    @Test func saveAsWritesACopyWithANewIDAndTheEditorStaysDirty() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        let copy = f.dir.url.appendingPathComponent("Copy.png")
        f.host.saveAsURLs = [copy]
        let events = f.recorder.events.count
        #expect(await f.sessions.saveAs(f.id) == .saved)
        #expect(f.contents(copy) == "png-1-1")
        let newID = try #require(f.idAttribute(copy))
        #expect(newID != f.id.description && CaptureID(string: newID) != nil)
        #expect(try f.store.value("dev.msenechal.bugeye.provenance", at: copy) == Data("{}".utf8))
        #expect(f.contents(f.item.fileURL) == "original")
        #expect(session.document?.isDirty == true)
        #expect(f.recorder.events.count == events)
        #expect(await f.sessions.saveAs(f.id) == .cancelled)
    }

    @Test func aFailedWriteShowsTheAlertAndStaysDirty() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        f.store.failSetting("dev.msenechal.bugeye.provenance")
        #expect(await f.sessions.save(f.id) == .failed)
        #expect(f.host.failures.count == 1)
        #expect(f.host.failures.first?.name == "Shot.png")
        #expect(f.contents(f.item.fileURL) == "original")
        #expect(session.document?.isDirty == true)
        #expect(f.logLines.last?.hasPrefix("save failed Shot.png: ") == true)
    }

    @Test func savesAreSerialisedAndOnlyTheLatestMarksAndPublishes() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        f.host.blockExports = true
        let first = Task { await f.sessions.save(f.id) }
        while f.host.pendingExports < 1 { await Task.yield() }
        session.document!.apply { $0.annotations.append(Annotation(shape: .step(center: .zero))) }
        let second = Task { await f.sessions.save(f.id) }
        for _ in 0..<50 { await Task.yield() }
        #expect(f.host.exportCount == 1)  // the second waits for the first
        let editedBefore = f.recorder.changes.filter { $0 == .edited }.count
        f.host.releaseExport()
        while f.host.pendingExports < 1 { await Task.yield() }
        f.host.releaseExport()
        #expect(await first.value == .saved)
        #expect(await second.value == .saved)
        #expect(f.contents(f.item.fileURL) == "png-2-2")
        #expect(f.recorder.changes.filter { $0 == .edited }.count == editedBefore + 1)
        #expect(session.document?.isDirty == false)
    }

    @Test func editsMadeDuringASaveStayDirty() async throws {
        let f = try SessionFixture()
        let session = await f.openAndEdit()
        f.host.blockExports = true
        let save = Task { await f.sessions.save(f.id) }
        while f.host.pendingExports < 1 { await Task.yield() }
        session.document!.apply { $0.annotations.append(Annotation(shape: .step(center: .zero))) }
        f.host.releaseExport()
        #expect(await save.value == .saved)
        #expect(session.document?.isDirty == true)
    }

    @Test func copyPutsThePNGOnTheClipboardAndFailureNotifies() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        await f.sessions.copy(f.id)
        #expect(f.clipboard.written == [ClipboardPayload(png: Data("png-1-1".utf8))])
        #expect(f.notifier.posts.isEmpty)
        f.host.exportError = FakeFailure()
        await f.sessions.copy(f.id)
        #expect(
            f.notifier.posts == [
                FakeNotifier.Post(title: "Couldn't copy", body: "The image couldn't be put on the clipboard.")
            ])
    }

    @Test func closingAsksOnlyWhenDirty() async throws {
        let f = try SessionFixture()
        await f.sessions.open(f.item)
        #expect(await f.sessions.shouldClose(f.id))
        #expect(!f.host.log.contains { $0.hasPrefix("ask") })
        f.sessions.session(f.id)!.document!.apply { $0.annotations.append(Annotation(shape: .step(center: .zero))) }
        f.host.saveAnswers = [.cancel, .dontSave, .save]
        #expect(await f.sessions.shouldClose(f.id) == false)
        #expect(await f.sessions.shouldClose(f.id) == true)
        #expect(await f.sessions.shouldClose(f.id) == true)
        #expect(f.contents(f.item.fileURL) == "png-1-1")
    }

    @Test func aFailedOrCancelledSaveKeepsTheWindowOpen() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        try FileManager.default.removeItem(at: f.item.fileURL)
        f.host.saveAnswers = [.save]
        f.host.goneAnswers = [false]
        #expect(await f.sessions.shouldClose(f.id) == false)
    }

    @Test func quitAsksDirtyEditorsInOpeningOrderAndStopsAtTheFirstCancel() async throws {
        let f = try SessionFixture()
        func another(_ name: String, dirty: Bool) async throws -> CaptureItem {
            let item = CaptureItem(
                id: CaptureID(), fileURL: f.saveFolder.appendingPathComponent(name), isSaved: true, kind: .screenshot,
                createdAt: Date(), pixelsPerPoint: 1)
            try Data("x".utf8).write(to: item.fileURL)
            await f.sessions.open(item)
            if dirty {
                f.sessions.session(item.id)!.document!.apply {
                    $0.annotations.append(Annotation(shape: .step(center: .zero)))
                }
            }
            return item
        }
        _ = await f.openAndEdit()
        _ = try await another("Clean.png", dirty: false)
        _ = try await another("B.png", dirty: true)
        _ = try await another("C.png", dirty: true)
        f.host.log = []
        f.host.saveAnswers = [.dontSave, .cancel]
        #expect(await f.sessions.shouldTerminate() == false)
        #expect(f.host.log.filter { $0 != "commit" } == ["forward", "ask Shot.png", "forward", "ask B.png"])
        f.host.log = []
        f.host.saveAnswers = [.save, .dontSave, .dontSave]
        #expect(await f.sessions.shouldTerminate() == true)
        #expect(f.host.log.filter { $0.hasPrefix("ask") } == ["ask Shot.png", "ask B.png", "ask C.png"])
        #expect(f.contents(f.item.fileURL) == "png-1-1")
    }

    @Test func theDragFileIsACopyWithANewIDAndStaleFilesAreRemoved() async throws {
        let f = try SessionFixture()
        _ = await f.openAndEdit()
        let folder = f.dir.url.appendingPathComponent("Bugeye-Drag", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stale = folder.appendingPathComponent("Old.png")
        let fresh = folder.appendingPathComponent("Fresh.png")
        try Data().write(to: stale)
        try Data().write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-25 * 3600)], ofItemAtPath: stale.path)
        let url = try await f.sessions.writeDragFile(f.id)
        #expect(url == folder.appendingPathComponent("Shot.png"))
        #expect(f.contents(url) == "png-1-1")
        #expect(f.idAttribute(url) != nil && f.idAttribute(url) != f.id.description)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Fresh.png", "Shot.png"])
        #expect(DragFolder.url(temporaryDirectory: URL(fileURLWithPath: "/tmp")).path == "/tmp/Bugeye-Drag")
    }
}

extension SessionFixture {
    func dirContents() throws -> [String] { try dir.contents().filter { !$0.hasPrefix(".") } }
}

@MainActor
@Suite struct LastCaptureTests {
    @Test func followsTheNewestCreatedCaptureAndIsEnabledWhenItCanOpen() throws {
        let dir = try TempDirectory("last-capture")
        let bus = CaptureEventBus()
        let router = ActionRouter()
        let last = LastCapture(bus: bus, router: router)
        #expect(!last.isEnabled)
        let shot = CaptureItem(
            id: CaptureID(), fileURL: dir.file("a.png"), isSaved: true, kind: .screenshot, createdAt: Date(),
            pixelsPerPoint: 2)
        let movie = CaptureItem(
            id: CaptureID(), fileURL: dir.file("b.mp4"), isSaved: true, kind: .recording, createdAt: Date(),
            pixelsPerPoint: 2)
        try Data().write(to: shot.fileURL)
        try Data().write(to: movie.fileURL)
        bus.publish(CaptureEvent(change: .created, item: shot, origin: "capture"))
        #expect(!last.isEnabled)  // no opener yet
        var opened: [CaptureItem] = []
        router.onOpen(.screenshot) { opened.append($0) }
        #expect(last.isEnabled)
        bus.publish(CaptureEvent(change: .created, item: movie, origin: "recording"))
        #expect(last.item == movie)
        #expect(!last.isEnabled)  // no recording opener in Wave 1
        #expect(!last.open())
        bus.publish(CaptureEvent(change: .created, item: shot, origin: "capture"))
        #expect(last.open())
        #expect(opened == [shot])
        try FileManager.default.removeItem(at: shot.fileURL)
        #expect(!last.isEnabled)
        try Data().write(to: shot.fileURL)
        bus.publish(CaptureEvent(change: .deleted, item: shot, origin: "quickAccess"))
        #expect(!last.isEnabled)
        dir.remove()
    }
}
