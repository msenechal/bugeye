import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@testable import BugeyeApp

/// A recorder that writes a small file on stop and reports what it was asked.
final class FakeRecorder: RecorderDriving, @unchecked Sendable {
    enum StopBehaviour { case movie, throwing, hanging }

    private let lock = NSLock()
    private var log: [String] = []
    private var held = false
    var request: StreamRequest?
    var failPrepare: StreamRecorder.Failure?
    var stopBehaviour = StopBehaviour.movie
    let callbacks: StreamRecorder.Callbacks

    init(callbacks: StreamRecorder.Callbacks = StreamRecorder.Callbacks()) {
        self.callbacks = callbacks
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    /// While held, `prepare` doesn't return.
    var holdsPrepare: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return held
        }
        set {
            lock.lock()
            held = newValue
            lock.unlock()
        }
    }

    private func note(_ call: String) {
        lock.lock()
        log.append(call)
        lock.unlock()
    }

    func prepare(_ request: StreamRequest) async throws {
        note("prepare")
        self.request = request
        for _ in 0..<1000 where holdsPrepare { try? await Task.sleep(for: .milliseconds(5)) }
        note("prepared")
        if let failPrepare { throw failPrepare }
    }

    func beginTake() { note("begin") }
    func pause(_ stamped: @escaping @Sendable (Double) -> Void) { note("pause") }
    func resume(_ stamped: @escaping @Sendable (Double) -> Void) { note("resume") }

    func stop() async throws -> MovieWriter.Result {
        note("stop")
        switch stopBehaviour {
        case .movie: break
        case .throwing: throw MovieWriter.Failure.notWriting("disk full")
        case .hanging:
            try? await Task.sleep(for: .seconds(60))
            return .noFrames
        }
        guard let url = request?.output else { return .noFrames }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: url)
        return .movie(url, duration: 12.5)
    }

    func cancel() async { note("cancel") }
}

@MainActor
final class FakeSurfaces: RecordingSurfaces {
    var calls: [String] = []
    var borders: [CGRect] = []
    var answer = true

    func showBorder(_ frame: CGRect, recording: Bool) {
        calls.append(recording ? "border red" : "border dashed")
        borders.append(frame)
    }
    func closeBorder() { calls.append("close border") }
    func showBar(around selection: CGRect, wholeDisplay: Bool, state: OptionsBarState) { calls.append("bar") }
    func updateBar(_ state: OptionsBarState) { calls.append("update bar") }
    func closeBar() { calls.append("close bar") }
    func showCountdown(_ digit: Int, in frame: CGRect) { calls.append("countdown \(digit)") }
    func closeCountdown() { calls.append("close countdown") }
    func setBubble(_ wish: BubbleWish?, area: CGRect) { calls.append(wish == nil ? "no bubble" : "bubble") }
    func moveBubble(area: CGRect) {}
    func confirm(_ kind: ConfirmKind) async -> Bool {
        calls.append("confirm \(kind.rawValue)")
        return answer
    }
    func dismissConfirm() { calls.append("dismiss") }
    var bubbleWindowID: CGWindowID? { 77 }
}

@MainActor @Suite struct RecordingControllerTests {
    @MainActor struct Rig {
        let home: TempDirectory
        let context: AppContext
        let selector: FakeAreaSelector
        let surfaces = FakeSurfaces()
        let notifier = FakeNotifier()
        let recorders = RecorderBox()
        let controller: RecordingController
        let events: CaptureEventRecorder

        init(
            selection: SelectionResult = .display(DisplayID(1)), convertOutcome: MovieConverter.Outcome? = nil,
            stopDeadline: Duration = .seconds(10)
        ) throws {
            home = try TempDirectory("home")
            let settings = InMemorySettingsStore([
                OutputSettings.Key.saveToFolder: .bool(false), OutputSettings.Key.copyToClipboard: .bool(false),
            ])
            context = AppContext.testing(home: home.url.path, settings: settings, notifier: notifier)
            selector = FakeAreaSelector(results: [selection])
            context.areaSelector.target = selector
            events = CaptureEventRecorder(context.captureEvents)
            let recorders = recorders
            controller = RecordingController(
                context: context,
                dependencies: RecordingController.Dependencies(
                    makeRecorder: { recorders.make($0) }, surfaces: surfaces, overlays: nil,
                    permissions: FakeMediaPermissions([.accessibility: .denied]), reader: nil,
                    devices: { ([], []) }, freeBytes: { _ in 50_000_000_000 }, hostNow: { 1000 },
                    convert: { mov, mp4, _, progress in
                        progress(0.5)
                        if let convertOutcome { return convertOutcome }
                        try? FileManager.default.moveItem(at: mov, to: mp4)
                        return .converted(mp4)
                    },
                    firstFrame: { _ in nil },
                    // Display 2 sits above and to the left of the primary: negative Quartz origin.
                    display: { id in
                        id == DisplayID(2)
                            ? (CGRect(x: -1512, y: -300, width: 1512, height: 982), 2)
                            : (CGRect(x: 0, y: 0, width: 1512, height: 982), 2)
                    },
                    primaryHeight: { 982 }, stopDeadline: stopDeadline))
        }
    }

    final class RecorderBox: @unchecked Sendable {
        private(set) var made: [FakeRecorder] = []
        /// Applied to each recorder as it is made.
        var configure: (FakeRecorder) -> Void = { _ in }
        func make(_ callbacks: StreamRecorder.Callbacks) -> FakeRecorder {
            let recorder = FakeRecorder(callbacks: callbacks)
            configure(recorder)
            made.append(recorder)
            return recorder
        }
    }

    /// Waits for async effects to settle (bounded; no run-loop spinning).
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func s1() -> SessionID { SessionID(1) }

    @Test func aRecordingRunsFromToggleToDelivery() async throws {
        let rig = try Rig()
        defer { rig.home.remove() }
        rig.controller.toggle()
        #expect(rig.context.screenActivity.active == [.recordingSetup])
        await settle { rig.surfaces.calls.contains("bar") }
        #expect(rig.selector.requests.first?.purpose == .recording)
        #expect(rig.surfaces.calls.prefix(2) == ["border dashed", "bar"])

        rig.controller.bar(.record)
        await settle { rig.recorders.made.first?.calls.contains("prepare") == true }
        let recorder = try #require(rig.recorders.made.first)
        #expect(recorder.request?.sourceRect == CGRect(x: 0, y: 0, width: 1512, height: 982))
        // The bubble's window stays in the video.
        #expect(recorder.request?.overlayWindowIDs == [77])
        #expect(
            recorder.request?.output.deletingLastPathComponent().standardizedFileURL
                == CaptureFolders.recordingsInProgress(home: rig.home.url.path).standardizedFileURL)
        await settle { if case .countingDown(_, _, _, _, true) = rig.controller.flow.state { true } else { false } }
        for _ in 0..<3 { rig.controller.send(.countdownTick(s1())) }
        #expect(rig.context.screenActivity.active == [.recording])
        #expect(recorder.calls.contains("begin"))
        #expect(rig.context.statusItem.override?.accessibilityLabel == "Recording, 00:00")
        rig.controller.send(.takeStarted(s1(), hostTime: 990, date: Date(timeIntervalSince1970: 1_795_788_192)))

        rig.controller.toggle()
        #expect(rig.context.statusItem.override?.badge == .finishing)
        await settle { rig.controller.flow.state == .idle }
        #expect(recorder.calls.contains("stop"))
        #expect(rig.context.statusItem.override == nil)
        #expect(rig.context.screenActivity.active.isEmpty)
        let created = try #require(rig.events.events.first)
        #expect(created.change == .created)
        #expect(created.item.kind == .recording)
        #expect(created.item.duration == 12.5)
        #expect(created.item.fileURL.pathExtension == "mp4")
        #expect(FileManager.default.fileExists(atPath: created.item.fileURL.path))
        #expect(rig.context.thumbnailDecorations.decorations(for: created.item.id) == [.mediaBadge(text: "▶ 00:12")])
    }

    @Test func aMovFallbackIsDeliveredWithItsNotice() async throws {
        let rig = try Rig(convertOutcome: .keptMovie(reason: "timed out"))
        defer { rig.home.remove() }
        try await record(rig)
        rig.controller.toggle()
        await settle { rig.controller.flow.state == .idle }
        #expect(rig.events.events.first?.item.fileURL.pathExtension == "mov")
        #expect(rig.notifier.posts.map(\.title) == ["Recording saved as a QuickTime movie"])
    }

    @Test func quitStopsDeliversThenReturns() async throws {
        let rig = try Rig()
        defer { rig.home.remove() }
        try await record(rig)
        await rig.controller.finishForQuit()
        #expect(rig.controller.flow.state == .idle)
        #expect(rig.events.events.count == 1)
    }

    @Test func aCancelledSelectionEndsSetUp() async throws {
        let rig = try Rig(selection: .cancelled)
        defer { rig.home.remove() }
        rig.controller.toggle()
        await settle { rig.controller.flow.state == .idle }
        #expect(rig.context.screenActivity.active.isEmpty)
        #expect(rig.surfaces.calls.isEmpty)
    }

    @Test func theStopEntryShowsTheCurrentBinding() async throws {
        let rig = try Rig()
        defer { rig.home.remove() }
        rig.context.settingsStore.setValue(.string("⌥⇧⌘5"), forKey: "recording.hotkey.toggle")
        try await record(rig)
        let stop = rig.context.statusItem.override?.menu.first { $0.id == RecordingMenu.stop }
        #expect(stop?.shownKey == KeyCombo("5", [.option, .shift, .command]))
    }

    /// PR #23 review C1: Esc while the recorder is still preparing. The cancel finds nothing to stop then, so
    /// what `prepare` started is stopped when it returns.
    @Test func aRecorderCancelledWhilePreparingIsStoppedWhenItReturns() async throws {
        let rig = try Rig()
        defer { rig.home.remove() }
        rig.recorders.configure = { $0.holdsPrepare = true }
        rig.controller.toggle()
        await settle { rig.surfaces.calls.contains("bar") }
        rig.controller.bar(.record)
        await settle { rig.recorders.made.first?.calls.contains("prepare") == true }
        let recorder = try #require(rig.recorders.made.first)
        rig.controller.send(.cancel(s1()))
        await settle { rig.controller.flow.state == .idle }
        recorder.holdsPrepare = false
        await settle { recorder.calls.last == "cancel" && recorder.calls.contains("prepared") }
        let calls = recorder.calls
        let prepared = try #require(calls.firstIndex(of: "prepared"))
        let lastCancel = try #require(calls.lastIndex(of: "cancel"))
        #expect(lastCancel > prepared)
        #expect(rig.controller.flow.state == .idle)
    }

    /// PR #23 review I1: a window's move during the countdown keeps the border dashed; a stale session's moves
    /// change nothing.
    @Test func windowMovesFollowOnlyTheCurrentSessionAndStayDashedUntilLive() async throws {
        let window = SelectionResult.window(
            WindowID(9), display: DisplayID(1), frame: Rect2D(x: 100, y: 100, width: 400, height: 300))
        let rig = try Rig(selection: window)
        defer { rig.home.remove() }
        rig.controller.toggle()
        await settle { rig.surfaces.calls.contains("bar") }
        rig.controller.bar(.record)
        await settle { if case .countingDown(_, _, _, _, true) = rig.controller.flow.state { true } else { false } }
        let recorder = try #require(rig.recorders.made.first)
        recorder.callbacks.areaMoved(CGRect(x: 10, y: 20, width: 400, height: 300))
        #expect(rig.surfaces.calls.last == "border dashed")
        #expect(rig.surfaces.borders.last == CGRect(x: 10, y: 982 - 320, width: 400, height: 300))
        let before = rig.surfaces.calls.count
        for _ in 0..<3 { rig.controller.send(.countdownTick(s1())) }
        rig.controller.send(.takeStarted(s1(), hostTime: 990, date: Date(timeIntervalSince1970: 1_795_788_192)))
        // At go-live the border is where the window went, not where it was selected (review I2).
        #expect(rig.surfaces.borders.last == CGRect(x: 10, y: 982 - 320, width: 400, height: 300))
        #expect(rig.surfaces.calls.count > before)
        // Stop ends the take (Cancel isn't an event while recording); the session's late moves change nothing.
        rig.controller.toggle()
        await settle { rig.controller.flow.state == .idle }
        #expect(rig.controller.flow.state == .idle)
        let after = rig.surfaces.calls.count
        recorder.callbacks.areaMoved(CGRect(x: 50, y: 50, width: 400, height: 300))
        #expect(rig.surfaces.calls.count == after)
    }

    /// Backlog M6, PR #23 review I3: a Stop that throws or never returns still ends the take.
    @Test func aStopThatThrowsOrHangsStillEnds() async throws {
        for behaviour in [FakeRecorder.StopBehaviour.throwing, .hanging] {
            let rig = try Rig(stopDeadline: .milliseconds(200))
            defer { rig.home.remove() }
            rig.recorders.configure = { $0.stopBehaviour = behaviour }
            try await record(rig)
            await rig.controller.finishForQuit()
            #expect(rig.controller.flow.state == .idle)
            #expect(rig.events.events.isEmpty)
            #expect(rig.context.screenActivity.active.isEmpty)
        }
    }

    /// A display with a negative Quartz origin: the stream gets display-local points, the border Cocoa points.
    @Test func aSecondaryDisplayMapsBothWays() async throws {
        let rig = try Rig(selection: .display(DisplayID(2)))
        defer { rig.home.remove() }
        rig.controller.toggle()
        await settle { rig.surfaces.calls.contains("bar") }
        #expect(rig.surfaces.borders.first == CGRect(x: -1512, y: 300, width: 1512, height: 982))
        rig.controller.bar(.record)
        await settle { rig.recorders.made.first?.calls.contains("prepare") == true }
        let recorder = try #require(rig.recorders.made.first)
        #expect(recorder.request?.sourceRect == CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(recorder.request?.display == 2)
    }

    /// Toggle, select, Record, ready, countdown: recording.
    private func record(_ rig: Rig) async throws {
        rig.controller.toggle()
        await settle { rig.surfaces.calls.contains("bar") }
        rig.controller.bar(.record)
        await settle { if case .countingDown(_, _, _, _, true) = rig.controller.flow.state { true } else { false } }
        for _ in 0..<3 { rig.controller.send(.countdownTick(s1())) }
        rig.controller.send(.takeStarted(s1(), hostTime: 990, date: Date(timeIntervalSince1970: 1_795_788_192)))
        guard case .recording = rig.controller.flow.state else {
            Issue.record("not recording: \(rig.controller.flow.state)")
            return
        }
    }
}

@MainActor @Suite struct RecordingWindowTests {
    @Test func theOptionsPanelTakesEscBothWays() {
        let panel = OptionsPanel()
        var cancels = 0
        panel.onCancel = { cancels += 1 }
        #expect(panel.canBecomeKey)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .statusBar)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]))
        panel.cancelOperation(nil)
        let esc = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        panel.keyDown(with: esc)
        #expect(cancels == 2)
    }

    @Test func theCountdownPanelTakesEscAndIs140Points() {
        let panel = CountdownPanel()
        var cancels = 0
        panel.onCancel = { cancels += 1 }
        #expect(panel.canBecomeKey)
        panel.show(3, centredIn: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(panel.frame == CGRect(x: 130, y: 80, width: 140, height: 140))
        panel.cancelOperation(nil)
        #expect(cancels == 1)
        panel.orderOut(nil)
    }

    @Test func theBorderIsClickThroughAndOutsideTheArea() {
        let border = BorderWindow()
        border.show(around: CGRect(x: 100, y: 100, width: 200, height: 100), recording: false, wholeDisplay: false)
        #expect(border.ignoresMouseEvents)
        #expect(border.level == .statusBar)
        #expect(border.frame == CGRect(x: 95, y: 95, width: 210, height: 110))
        border.orderOut(nil)
    }

    @Test func theRecordingPaneWritesOneKey() {
        let store = InMemorySettingsStore()
        RecordingSettings.write(.codec(.hevc), to: store)
        _ = RecordingPane(store: store)
        #expect(store.all == ["recording.codec": .string("hevc")])
    }
}
