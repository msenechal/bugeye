import BugeyeCore
import BugeyeTestSupport
import CaptureCore
import Foundation
import Testing

@MainActor
final class ControllerHarness {
    let dir = try! TempDirectory()
    let source: FakeScreenSource
    let windows = FakeWindowListReader(windows: [otherWindow])
    let pipeline = FakeImagePipeline()
    let permission = FakeScreenCapturePermission(granted: true)
    let settings = InMemorySettingsStore()
    let metadata = FakeFileMetadataStore()
    let clipboard = FakeClipboard()
    let notifier = FakeNotifier()
    let bus = CaptureEventBus()
    let activity = ScreenActivity()
    let registrar = FakeHotkeyRegistrar()
    let shell = FakeCaptureShell()
    let recorder: CaptureEventRecorder
    var controller: CaptureController!

    var saveFolder: URL { dir.url.appendingPathComponent("Pictures/Bugeye", isDirectory: true) }
    var tempFolder: URL { CaptureFolders.temp(home: dir.url.path) }

    init(displays: [DisplayInfo] = [primary, external]) {
        source = FakeScreenSource(displays: displays, time: freezeTime)
        recorder = CaptureEventRecorder(bus)
        try! FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let folder = saveFolder
        let environment = CaptureEnvironment(
            screenSource: source, windowList: windows, pipeline: pipeline, permission: permission, settings: settings,
            writer: CaptureFileWriter(metadata: metadata), clipboard: clipboard, notifier: notifier, metadata: metadata,
            home: dir.url.path, ownPID: ownPID, saveFolder: { (folder, "~/Pictures/Bugeye/") },
            now: { freezeTime.addingTimeInterval(5) }, timeZone: TimeZone(identifier: "Europe/Paris")!)
        controller = CaptureController(
            environment: environment, bus: bus, activity: activity, registrar: registrar, shell: shell)
    }

    func savedNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: saveFolder.path).sorted()
    }

    /// A drag on the primary display, display-local points.
    func drag(_ from: DisplayPoint, _ to: DisplayPoint) {
        let session = controller.session!
        controller.send(.mouseDown(session, primary.id, from.viewPoint(displayHeight: 900), Modifiers()))
        controller.send(.mouseDragged(session, primary.id, to.viewPoint(displayHeight: 900), Modifiers()))
        controller.send(.mouseUp(session, primary.id, to.viewPoint(displayHeight: 900)))
    }
}

@Suite @MainActor struct CaptureControllerTests {
    @Test func anAreaCaptureIsSavedCopiedAndAnnouncedFromTheFrozenFrame() async throws {
        let h = ControllerHarness()
        h.controller.request(.area)
        #expect(h.activity.active == [.screenshotSelection])
        await h.controller.settle()
        #expect(h.controller.phase == .selecting)
        #expect(h.source.freezeCount == 1)
        #expect(h.windows.readCount == 1)
        #expect(h.shell.shown.map(\.1) == [[primary.id, external.id]])
        #expect(h.registrar.registered[CaptureModule.ID.escape] == .escape)
        #expect(h.shell.calls.contains("activate"))

        h.drag(DisplayPoint(x: 100, y: 50), DisplayPoint(x: 300, y: 150))
        await h.controller.settle()
        #expect(h.controller.phase == .idle)
        #expect(h.activity.active.isEmpty)
        #expect(h.registrar.registered.isEmpty)
        #expect(h.pipeline.crops == [Rect2D(x: 200, y: 100, width: 400, height: 200)])
        #expect(try h.savedNames() == ["Screenshot 2026-11-27 at 14.03.12.png"])
        let event = try #require(h.recorder.events.first)
        #expect(h.recorder.changes == [.created])
        #expect(event.origin == "capture")
        #expect(event.item.isSaved && event.item.pixelsPerPoint == 2 && event.item.createdAt == freezeTime)
        #expect(event.preview?.width == 400)
        #expect(
            h.clipboard.written == [
                ClipboardPayload(png: FakeImagePipeline.png(width: 400, height: 200), fileURL: event.item.fileURL)
            ])
        #expect(
            LastAreaStore.load(from: h.settings)
                == StoredArea(
                    display: primary.id, rect: Rect2D(x: 100, y: 50, width: 200, height: 100),
                    displaySize: primary.pointSize))
        #expect(h.shell.open.isEmpty)
        #expect(
            h.shell.logged(.selection) == ["begin screenshot overlays [100, 101]", "finish area overlays [100, 101]"])
        #expect(h.shell.logged(.hotkeys) == ["escape on", "escape off"])
        #expect(h.shell.logged(.capture).contains("freeze 2 displays in 0 ms"))
        #expect(h.shell.logged(.capture).contains("saved Screenshot 2026-11-27 at 14.03.12.png"))
        // Leave: close, (sweep), reactivate, in that order, after the selection began.
        let close = try #require(h.shell.calls.firstIndex(of: "close 1"))
        let reactivate = try #require(h.shell.calls.firstIndex(of: "reactivate"))
        #expect(close < reactivate)
        #expect(h.shell.calls.firstIndex(of: "show 1")! < close)
    }

    @Test func everyDisplayIsFrozenOnceAndSavedInDisplayOrderWithOneTimestamp() async throws {
        let h = ControllerHarness(displays: [external, primary])
        h.controller.request(.allDisplays)
        await h.controller.settle()
        #expect(h.source.freezeCount == 1)
        #expect(
            try h.savedNames() == [
                "Screenshot 2026-11-27 at 14.03.12 (2).png", "Screenshot 2026-11-27 at 14.03.12.png",
            ])
        // Primary first: it got the plain name, the external display ` (2)`.
        #expect(h.recorder.events.map(\.item.pixelsPerPoint) == [2, 1])
        #expect(h.recorder.events.first?.item.fileURL.lastPathComponent == "Screenshot 2026-11-27 at 14.03.12.png")
        #expect(h.pipeline.encodedSizes == [Size2D(width: 2880, height: 1800), Size2D(width: 1920, height: 1080)])
        #expect(h.controller.phase == .idle && h.activity.active.isEmpty)
    }

    @Test func fullscreenCapturesTheDisplayUnderThePointer() async throws {
        let h = ControllerHarness()
        h.shell.pointer = CocoaPoint(x: -500, y: 500)
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.recorder.events.map(\.item.pixelsPerPoint) == [1])
        #expect(h.pipeline.encodedSizes == [Size2D(width: 1920, height: 1080)])
    }

    @Test func downscaleEncodesAtOnePixelPerPoint() async throws {
        let h = ControllerHarness()
        h.settings.setValue(.bool(true), forKey: "capture.downscaleToPoints")
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.pipeline.downscaleFactors == [0.5])
        #expect(h.recorder.events.first?.item.pixelsPerPoint == 1)
        #expect(h.pipeline.encodedSizes == [Size2D(width: 1440, height: 900)])
    }

    @Test func downscaleLeavesAOneXCaptureAlone() async throws {
        let h = ControllerHarness()
        h.settings.setValue(.bool(true), forKey: "capture.downscaleToPoints")
        h.shell.pointer = CocoaPoint(x: -500, y: 500)
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.pipeline.downscaleFactors.isEmpty)
    }

    @Test func anEncodingFailureNotifiesAndAnnouncesNothing() async throws {
        let h = ControllerHarness()
        h.pipeline.failEncoding = true
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.recorder.events.isEmpty)
        #expect(h.notifier.posts == [FakeNotifier.Post(title: "Capture failed", body: "Could not encode PNG.")])
        #expect(h.controller.phase == .idle && h.activity.active.isEmpty)
    }

    @Test func anUnusableFolderPostsTheNoticeAndStillAnnounces() async throws {
        let h = ControllerHarness()
        try FileManager.default.removeItem(at: h.saveFolder)
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.recorder.events.first?.item.isSaved == false)
        #expect(
            h.notifier.posts == [
                FakeNotifier.Post(
                    title: "Couldn't save to folder",
                    body:
                        "~/Pictures/Bugeye/ is unavailable. The capture is kept temporarily; use Save in Quick Access.")
            ])
    }

    @Test func aWindowIsCapturedLiveAtFullScaleWithItsOwnTime() async throws {
        let h = ControllerHarness()
        h.source.windowImages = [
            WindowID(7): [try shadowedImage(width: 800, height: 600, body: Rect2D(x: 0, y: 0, width: 800, height: 600))]
        ]
        h.controller.request(.window)
        await h.controller.settle()
        let session = h.controller.session!
        h.controller.send(
            .mouseDown(session, primary.id, DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), Modifiers()))
        await h.controller.settle()
        #expect(h.source.windowCaptures.map(\.pixelSize) == [Size2D(width: 800, height: 600)])
        let item = try #require(h.recorder.events.first?.item)
        #expect(item.pixelsPerPoint == 2)
        #expect(item.createdAt == freezeTime.addingTimeInterval(5))
        #expect(h.controller.phase == .idle)
        #expect(h.controller.heldWindowImages == 0 && h.controller.heldFrameSessions == 0)
    }

    @Test func aClosedWindowPostsCaptureFailed() async throws {
        let h = ControllerHarness()
        h.controller.request(.window)
        await h.controller.settle()
        let session = h.controller.session!
        h.controller.send(
            .mouseDown(session, primary.id, DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), Modifiers()))
        await h.controller.settle()
        #expect(
            h.notifier.posts == [
                FakeNotifier.Post(title: "Capture failed", body: "The window closed before it could be captured.")
            ])
        #expect(h.recorder.events.isEmpty && h.controller.phase == .idle && h.activity.active.isEmpty)
        #expect(h.controller.heldWindowImages == 0)
    }

    @Test func aRequestMadeWhileEffectsRunKeepsTheSettingsReadAtThatRequest() async throws {
        let h = ControllerHarness()
        h.controller.request(.area)
        await h.controller.waitUntil(.selecting)
        // The shell asks for a full-screen capture while the area selection is closing (claude-review, PR #20).
        h.shell.duringClose = { h.controller.request(.fullscreen) }
        h.controller.send(.key(h.controller.session!, .escape))
        // Settings change after the request: the capture still uses those read at the request.
        h.settings.setValue(.bool(true), forKey: "capture.downscaleToPoints")
        await h.controller.settle()
        #expect(h.recorder.events.count == 1)
        #expect(h.pipeline.downscaleFactors.isEmpty)
    }

    @Test func withoutPermissionTheAlertShowsAndNothingIsFrozen() async {
        let h = ControllerHarness()
        h.permission.granted = false
        h.controller.request(.area)
        await h.controller.settle()
        #expect(h.shell.alerts == 1)
        #expect(h.source.freezeCount == 0)
        #expect(h.activity.active.isEmpty)
    }

    @Test func aDeclinedFreezeShowsTheAlert() async {
        let h = ControllerHarness()
        h.source.failNextFreeze(.permissionDenied)
        h.controller.request(.area)
        await h.controller.settle()
        #expect(h.shell.alerts == 1)
        #expect(h.controller.phase == .idle && h.activity.active.isEmpty)
    }

    @Test func screenshotsAreRefusedDuringARecordingsSetUp() async {
        let h = ControllerHarness()
        h.activity.begin(.recordingSetup)
        h.controller.request(.fullscreen)
        await h.controller.settle()
        #expect(h.source.freezeCount == 0)
        #expect(h.shell.logged(.capture) == ["busy: dropped fullscreen"])
        #expect(h.activity.active == [.recordingSetup])
    }

    @Test func theTemporaryEscHotkeyCancels() async {
        let h = ControllerHarness()
        h.controller.request(.area)
        await h.controller.settle()
        #expect(h.registrar.press(CaptureModule.ID.escape))
        #expect(h.controller.phase == .idle)
        #expect(h.registrar.registered.isEmpty)
        #expect(h.shell.open.isEmpty)
        #expect(h.shell.logged(.selection).last == "finish cancelled overlays [100, 101]")
    }

    @Test func returnRecapturesTheStoredAreaAfterARestart() async throws {
        let h = ControllerHarness()
        LastAreaStore.save(
            StoredArea(
                display: external.id, rect: Rect2D(x: 10, y: 20, width: 30, height: 40), displaySize: external.pointSize
            ),
            to: h.settings)
        h.controller.request(.area)
        await h.controller.settle()
        h.controller.send(.key(h.controller.session!, .return))
        await h.controller.settle()
        #expect(h.pipeline.crops == [Rect2D(x: 10, y: 20, width: 30, height: 40)])
        #expect(h.recorder.events.count == 1)
    }

    @Test func theHourlyPurgeSkipsCapturesTheBusKnowsAndTheLaunchPurgeDoesNot() async throws {
        let h = ControllerHarness()
        try FileManager.default.createDirectory(at: h.tempFolder, withIntermediateDirectories: true)
        let known = CaptureID()
        let knownURL = h.tempFolder.appendingPathComponent("known.png")
        let goneURL = h.tempFolder.appendingPathComponent("gone.png")
        for url in [knownURL, goneURL] {
            FileManager.default.createFile(atPath: url.path, contents: Data())
            try FileManager.default.setAttributes(
                [.modificationDate: freezeTime.addingTimeInterval(-2 * 86400)], ofItemAtPath: url.path)
        }
        try h.metadata.setValue(Data(known.description.utf8), CaptureFileWriter.identityAttribute, at: knownURL)
        try h.metadata.setValue(Data(CaptureID().description.utf8), CaptureFileWriter.identityAttribute, at: goneURL)
        h.bus.publish(
            CaptureEvent(
                change: .created,
                item: CaptureItem(
                    id: known, fileURL: knownURL, isSaved: false, kind: .screenshot, createdAt: freezeTime,
                    pixelsPerPoint: 2),
                origin: "capture"))

        #expect(await h.controller.purgeTemp(skippingKnown: true) == 1)
        #expect(FileManager.default.fileExists(atPath: knownURL.path))
        #expect(!FileManager.default.fileExists(atPath: goneURL.path))
        #expect(await h.controller.purgeTemp(skippingKnown: false) == 1)
        #expect(!FileManager.default.fileExists(atPath: knownURL.path))
        #expect(h.shell.logged(.capture) == ["purged 1 temp files", "purged 1 temp files"])
    }
}

@Suite @MainActor struct CaptureControllerSelectorTests {
    let recording = SelectionRequest(purpose: .recording, hint: "hint", clickSelectsDisplay: true)

    @Test func aRecordingSelectionAnswersTheAreaAndNeverDeliversOrHoldsTheScreenshotActivity() async throws {
        let h = ControllerHarness()
        let task = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.selecting)
        #expect(h.activity.active.isEmpty)
        #expect(h.controller.overlay(for: primary.id)?.hint == "hint")
        h.drag(DisplayPoint(x: 100, y: 50), DisplayPoint(x: 300, y: 150))
        let result = await task.value
        #expect(
            result
                == .area(
                    StoredArea(
                        display: primary.id, rect: Rect2D(x: 100, y: 50, width: 200, height: 100),
                        displaySize: primary.pointSize)))
        await h.controller.settle()
        #expect(h.recorder.events.isEmpty)
        #expect(LastAreaStore.load(from: h.settings) == nil)
        #expect(h.shell.open.isEmpty)
    }

    @Test func aLateFreezeAfterACancelDoesNotStartTheNextSelection() async {
        let h = ControllerHarness()
        h.source.hold()
        let first = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.freezing)
        h.controller.cancel(.recording)
        #expect(await first.value == .cancelled)
        // A new selection starts; then both freezes finish. Only the new one's frames open overlays.
        let second = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.freezing)
        h.source.release()
        await h.controller.waitUntil(.selecting)
        #expect(h.shell.shown.count == 1)
        #expect(h.shell.shown.first?.0 == h.controller.session)
        h.controller.cancel(.recording)
        #expect(await second.value == .cancelled)
    }

    @Test func aFreezeFinishingAfterACancelKeepsNoFrames() async {
        let h = ControllerHarness()
        h.source.hold()
        let task = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.freezing)
        h.controller.cancel(.recording)
        #expect(await task.value == .cancelled)
        h.source.release()
        await h.controller.settle()
        #expect(h.controller.heldFrameSessions == 0)
        #expect(h.controller.inFlightCount == 0)
    }

    @Test func aSelectionWhileAScreenshotRunsAnswersBusy() async {
        let h = ControllerHarness()
        h.controller.request(.area)
        #expect(await h.controller.select(recording) == .busy)
        #expect(h.controller.phase != .idle)
    }

    @Test func anExternalCancelWhileFreezingAnswersCancelledAndNoOverlayEverShows() async {
        let h = ControllerHarness()
        h.source.hold()
        let task = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.freezing)
        h.controller.cancel(.recording)
        #expect(await task.value == .cancelled)
        // The freeze finishes after the cancel: its frames are dropped by session, nothing shows.
        h.source.release()
        await h.controller.settle()
        #expect(h.source.freezeCount == 1)
        #expect(h.shell.shown.isEmpty)
        #expect(h.controller.phase == .idle)
    }

    @Test func anExternalCancelWhileSelectingClosesTheOverlays() async {
        let h = ControllerHarness()
        let task = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.selecting)
        h.controller.cancel(.recording)
        #expect(await task.value == .cancelled)
        #expect(h.shell.open.isEmpty && h.registrar.registered.isEmpty)
    }

    @Test func aFreezeFailureAnswersCancelled() async {
        let h = ControllerHarness()
        h.source.failNextFreeze(.failed("boom"))
        #expect(await h.controller.select(recording) == .cancelled)
        #expect(h.notifier.posts == [FakeNotifier.Post(title: "Capture failed", body: "boom")])
    }

    @Test func aClickAnswersTheDisplay() async {
        let h = ControllerHarness()
        let task = Task { await h.controller.select(recording) }
        await h.controller.waitUntil(.selecting)
        h.drag(DisplayPoint(x: 100, y: 50), DisplayPoint(x: 100, y: 50))
        #expect(await task.value == .display(primary.id))
    }
}
