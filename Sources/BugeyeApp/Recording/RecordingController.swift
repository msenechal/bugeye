import AVFoundation
import AppKit
import BugeyeCore
import BugeyeFeatures
import CoreMedia
import Foundation
import RecordingCore
import Synchronization
import os

/// What the controller needs from a recorder: `StreamRecorder` in the app, a fake in tests.
protocol RecorderDriving: AnyObject, Sendable {
    func prepare(_ request: StreamRequest) async throws
    func beginTake()
    func pause(_ stamped: @escaping @Sendable (Double) -> Void)
    func resume(_ stamped: @escaping @Sendable (Double) -> Void)
    func stop() async throws -> MovieWriter.Result
    func cancel() async
}

/// The windows the flow drives (border, bar, countdown, bubble, alerts): `RecordingWindows` in the app.
@MainActor
protocol RecordingSurfaces: AnyObject {
    func showBorder(_ frame: CGRect, recording: Bool)
    func closeBorder()
    func showBar(around selection: CGRect, wholeDisplay: Bool, state: OptionsBarState)
    func updateBar(_ state: OptionsBarState)
    func closeBar()
    func showCountdown(_ digit: Int, in frame: CGRect)
    func closeCountdown()
    func setBubble(_ wish: BubbleWish?, area: CGRect)
    func moveBubble(area: CGRect)
    func confirm(_ kind: ConfirmKind) async -> Bool
    func dismissConfirm()
    /// The bubble's window, an exception to the app's exclusion (in the video), while it is shown.
    var bubbleWindowID: CGWindowID? { get }
}

/// The click rings and keystroke badge window (slice 7 draws it through the Editor's executor).
@MainActor
protocol OverlayPresenting: AnyObject {
    /// Shows the (empty) window over `area` before the stream starts: ScreenCaptureKit lists on-screen windows
    /// only, so it must be there to be kept in the video.
    func show(area: CGRect)
    func start(area: CGRect, clicks: Bool, keys: Bool, showAllKeys: Bool)
    func click(_ button: TimelineButton, at quartz: Point2D)
    func key(_ press: KeyPress)
    func move(area: CGRect)
    func stop()
    /// The window ids ScreenCaptureKit must keep in the video.
    var windowIDs: [CGWindowID] { get }
}

/// What the options bar shows.
struct OptionsBarState: Equatable {
    var options: RecordingOptions
    var effective: RecordingOptions
    var permissions: RecordingPermissions
    var microphones: [CaptureDevices.Device]
    var cameras: [CaptureDevices.Device]
}

/// The bar's controls, sent back to the controller.
enum OptionsBarAction: Equatable {
    case record
    case cancel
    case change(RecordingOptionChange)
}

/// Executes `RecordingFlow`'s effects and turns every callback into an event (V1). Owns the sessions' recorders,
/// the countdown and status timers, the input monitor and the timeline. Main actor; slow work in tasks.
@MainActor
final class RecordingController {
    struct Dependencies {
        var makeRecorder: @MainActor (StreamRecorder.Callbacks) -> any RecorderDriving
        var surfaces: any RecordingSurfaces
        var overlays: (any OverlayPresenting)?
        var permissions: any MediaPermissions
        var reader: (any AXReader)?
        var devices: @MainActor () -> (microphones: [CaptureDevices.Device], cameras: [CaptureDevices.Device])
        var freeBytes: @Sendable (URL) -> Int64?
        var hostNow: @Sendable () -> Double
        var convert:
            @Sendable (URL, URL, Duration, @escaping @Sendable (Double) -> Void) async -> MovieConverter.Outcome
        var firstFrame: @Sendable (URL) async -> PixelBuffer?
        /// Display geometry: Quartz global bounds and pixels per point.
        var display: @MainActor (DisplayID) -> (bounds: CGRect, scale: Double)?
        /// The primary display's height, for Cocoa ↔ Quartz.
        var primaryHeight: @MainActor () -> CGFloat
        /// How long Stop (the stream's stop and the movie's finish) and the first-frame preview may take before
        /// the take is ended without them, so ⌘Q never waits forever (backlog M6, PR #23 review I3).
        var stopDeadline: Duration = .seconds(10)
    }

    /// What the timeline gets, in order: one consumer per timeline (PR #22 review, outside the PR).
    enum TimelineCommand: Sendable {
        case input(TimelineInput, Double)
        case pause(Double)
        case resume(Double)
        case finish(Double)
        case discard
    }

    private let context: AppContext
    private let deps: Dependencies
    private let delivery: RecordingDelivery
    private let logger = Logger(subsystem: CaptureFolders.bundleID, category: "recording")
    private let timelineLogger = Logger(subsystem: CaptureFolders.bundleID, category: "timeline")

    private(set) var flow = RecordingFlow()
    private var recorders: [SessionID: any RecorderDriving] = [:]
    private var requests: [SessionID: StreamRequest] = [:]
    private var countdownTimer: Timer?
    private var ticker: Timer?
    private var monitor: InputMonitor?
    private var timeline: TimelineRecorder?
    private var timelineURL: URL?
    private var wantsTimeline = false
    private var firstFrameHost: Double?
    private var firstFrameDate = Date()
    private var quitWaiters: [CheckedContinuation<Void, Never>] = []
    private var bubbleWish: BubbleWish?
    /// The timeline's ordered feed, once it exists.
    private var timelineFeed: AsyncStream<TimelineCommand>.Continuation?
    /// Pause and resume stamps that came before the timeline existed (a pause before the first frame, or while
    /// it was being created): replayed into it (PR #23 review I4).
    private var pendingStamps: [TimelineCommand] = []
    /// A followed window's latest recorded rect, Quartz global, clamped like the stream's (review I2).
    private var followedWindow: (id: WindowID, quartz: CGRect)?

    init(context: AppContext, dependencies: Dependencies) {
        self.context = context
        deps = dependencies
        delivery = RecordingDelivery(
            ports: RecordingDelivery.Ports(
                fileWriter: context.fileWriter, bus: context.captureEvents, decorations: context.thumbnailDecorations,
                clipboard: context.clipboard, notifier: context.notifier,
                timelines: TimelineStore(home: context.home), settings: context.settingsStore, home: context.home,
                saveFolder: { [general = context.general] in general.folderURL }))
    }

    // MARK: Inputs

    /// ⇧⌘5, Record Screen, the ● menu's Stop.
    func toggle() {
        send(
            .toggle(
                screenPermitted: context.screenPermission.preflight(),
                activityAllows: context.screenActivity.allows(.startRecording),
                lastArea: RecordingSettings.lastArea(in: context.settingsStore)))
    }

    /// The ● menu (override entries).
    func menu(_ id: String) {
        guard let s = flow.state.session else { return }
        let now = deps.hostNow()
        switch id {
        case RecordingMenu.pause: send(.pause(s, hostNow: now))
        case RecordingMenu.resume: send(.resume(s, hostNow: now))
        case RecordingMenu.stop: toggle()
        case RecordingMenu.restart: send(.restart(s, hostNow: now))
        case RecordingMenu.discard: send(.discard(s, hostNow: now))
        default: break
        }
    }

    func bar(_ action: OptionsBarAction) {
        guard let s = flow.state.session else { return }
        switch action {
        case .record:
            let folder = CaptureFolders.recordingsInProgress(home: context.home)
            let free = deps.freeBytes
            Task {
                let bytes = await Task.detached { free(folder) ?? .max }.value
                self.send(.record(s, freeBytes: bytes))
            }
        case .cancel: send(.cancel(s))
        case .change(let change): send(.option(s, change))
        }
    }

    /// The bubble was double-clicked: the next size.
    func bubbleDoubleClicked() {
        guard let s = flow.state.session, let wish = bubbleWish else { return }
        send(.option(s, .bubbleSize(wish.size.next)))
    }

    func cameraFailed() {
        guard let s = flow.state.session else { return }
        send(.cameraUnavailable(s))
    }

    /// The termination gate's finish participant: stops and delivers, returns on `allowQuit`.
    func finishForQuit() async {
        await withCheckedContinuation { continuation in
            quitWaiters.append(continuation)
            send(.quitRequested)
        }
    }

    /// V15: delivers what a crash left in the in-progress folder, each with the "Recovered a recording" notice.
    func recoverTakes() async {
        let folder = CaptureFolders.recordingsInProgress(home: context.home)
        // Runs at launch, before any take: nothing in the folder is live (a debug build beside the installed
        // app is covered by the plan's quiet period).
        let live: Set<UUID> = []
        let files = await Task.detached { Self.listing(folder) }.value
        let plan = TakeRecovery.plan(files: files, liveTakes: live, now: Date())
        for name in plan.delete { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        for recovery in plan.recover {
            let movie = folder.appendingPathComponent(recovery.movie)
            let duration = (try? await AVURLAsset(url: movie).load(.duration).seconds) ?? 0
            let preview = await deps.firstFrame(movie)
            let item = await delivery.deliver(
                movie: movie, date: recovery.createdAt, duration: duration.isFinite ? duration : 0,
                pixelsPerPoint: lastScale, timeline: recovery.timeline.map { folder.appendingPathComponent($0) },
                preview: preview)
            if let item {
                logger.info("recovered \(item.fileURL.lastPathComponent, privacy: .private)")
                context.notifier.post(
                    title: RecordingStrings.Notice.recovered.title, body: RecordingStrings.Notice.recovered.body)
            }
        }
    }

    nonisolated private static func listing(_ folder: URL) -> [TakeRecovery.File] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let created = values.creationDate ?? Date.distantPast
            return TakeRecovery.File(
                name: url.lastPathComponent, created: created, modified: values.contentModificationDate ?? created,
                size: Int64(values.fileSize ?? 0))
        }
    }

    /// Debug channel `recording.state`.
    var stateDescription: String { String(describing: flow.state) }

    // MARK: The loop

    func send(_ event: RecordingEvent) {
        flow.stopKey = HotkeyBindings.current(RecordingModule.toggleHotkey, in: context.settingsStore)
        let session = flow.state.session
        guard let effects = flow.next(event) else { return }
        for effect in effects { execute(effect, session: session) }
    }

    private func execute(_ effect: RecordingEffect, session: SessionID?) {
        switch effect {
        case .selection(let request):
            guard let s = flow.state.session else { return }
            followedWindow = nil
            Task {
                let result = await context.areaSelector.select(request)
                let devices = deps.devices()
                send(
                    .selected(
                        s, result, options: RecordingSettings.load(from: context.settingsStore),
                        permissions: permissions(),
                        devices: CaptureDeviceList(
                            microphones: devices.microphones.map(\.id), cameras: devices.cameras.map(\.id))))
            }
        case .cancelSelection:
            context.areaSelector.cancel(.recording)
        case .activity(.begin(let activity)):
            context.screenActivity.begin(activity)
        case .activity(.end(let activity)):
            context.screenActivity.end(activity)
        case .showBorder(let target, let style):
            if let frame = frame(of: target) { deps.surfaces.showBorder(frame, recording: style == .recording) }
        case .closeBorder:
            deps.surfaces.closeBorder()
        case .showBar(let options, let effective):
            guard case .configuring(_, let target, _, _, _) = flow.state, let frame = frame(of: target) else { return }
            deps.surfaces.showBar(
                around: frame, wholeDisplay: isWholeDisplay(target), state: barState(options, effective))
        case .updateBar(let options, let effective):
            deps.surfaces.updateBar(barState(options, effective))
        case .closeBar:
            deps.surfaces.closeBar()
        case .bubble(let wish):
            bubbleWish = wish
            let area = currentTarget.flatMap(frame(of:)) ?? .zero
            deps.surfaces.setBubble(wish, area: area)
        case .countdown(let digit):
            countdown(digit)
        case .closeCountdown:
            countdownTimer?.invalidate()
            countdownTimer = nil
            deps.surfaces.closeCountdown()
        case .prepareRecorder(let s, let request):
            prepare(s, request)
        case .beginTake(let s):
            recorders[s]?.beginTake()
        case .pauseRecorder(let s):
            recorders[s]?.pause { host in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.feedTimeline(.pause(host)) } }
            }
        case .resumeRecorder(let s):
            recorders[s]?.resume { host in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.feedTimeline(.resume(host)) } }
            }
        case .stopRecorder(let s):
            stopRecorder(s)
        case .cancelRecorder(let s):
            if recorders[s] != nil { deps.overlays?.stop() }
            let recorder = recorders.removeValue(forKey: s)
            requests[s] = nil
            Task { await recorder?.cancel() }
        case .overlays(let start, let clicks, let keys, let showAllKeys):
            if start, let target = currentTarget, let frame = frame(of: target) {
                deps.overlays?.start(area: frame, clicks: clicks, keys: keys, showAllKeys: showAllKeys)
            } else if !start {
                deps.overlays?.stop()
            }
        case .inputMonitor(let start):
            start ? startMonitor() : stopMonitor()
        case .timeline(.start):
            wantsTimeline = true
            if let host = firstFrameHost { startTimeline(at: host) }
        case .timeline(.finish):
            finishTimeline()
        case .timeline(.discard):
            discardTimeline()
        case .ticker(let start):
            start ? startTicker() : stopTicker()
        case .statusItem(let item):
            context.statusItem.setOverride(item, owner: RecordingDelivery.origin)
        case .confirm(let s, let kind):
            Task {
                let yes = await deps.surfaces.confirm(kind)
                send(yes ? .confirmed(s, kind) : .declined(s, kind))
            }
        case .dismissConfirm:
            deps.surfaces.dismissConfirm()
        case .convert(let s, let url, let deadline):
            convert(s, url, deadline: deadline)
        case .deliver(let s, let url, let date, let duration):
            deliver(s, url, date: date, duration: duration)
        case .persist(let key, let value):
            context.settingsStore.setValue(value, forKey: key)
        case .storeLastArea(let area):
            RecordingSettings.storeLastArea(area, in: context.settingsStore)
        case .requestPermission(let permission):
            guard let s = flow.state.session else { return }
            let permissions = deps.permissions
            Task {
                let state = await permissions.request(permission)
                send(.permissionAnswered(s, permission, state))
            }
        case .notify(let notice):
            context.notifier.post(title: notice.title, body: notice.body)
        case .screenPermissionAlert:
            context.screenRecordingAlert.show()
        case .diskCheck:
            guard let s = flow.state.session else { return }
            let folder = CaptureFolders.recordingsInProgress(home: context.home)
            let free = deps.freeBytes
            Task {
                let bytes = await Task.detached { free(folder) ?? .max }.value
                logger.info("disk \(bytes / 1_000_000) MB")
                send(.diskChecked(s, freeBytes: bytes))
            }
        case .allowQuit:
            let waiters = quitWaiters
            quitWaiters = []
            for waiter in waiters { waiter.resume() }
        case .log(let message):
            logger.info("\(message, privacy: .public)")
        }
    }

    // MARK: Effects

    private var currentTarget: RecordingTarget? {
        switch flow.state {
        case .configuring(_, let target, _, _, _), .countingDown(_, let target, _, _, _), .starting(_, let target, _):
            target
        case .recording(_, let take), .paused(_, let take): take.target
        default: nil
        }
    }

    private func permissions() -> RecordingPermissions {
        RecordingPermissions(
            microphone: deps.permissions.state(.microphone), camera: deps.permissions.state(.camera),
            accessibility: deps.permissions.state(.accessibility))
    }

    private func barState(_ options: RecordingOptions, _ effective: RecordingOptions) -> OptionsBarState {
        let devices = deps.devices()
        return OptionsBarState(
            options: options, effective: effective, permissions: permissions(), microphones: devices.microphones,
            cameras: devices.cameras)
    }

    private func isWholeDisplay(_ target: RecordingTarget) -> Bool {
        if case .display = target { return true }
        return false
    }

    /// The target in Cocoa global points (what windows are placed in).
    func frame(of target: RecordingTarget) -> CGRect? {
        guard let quartz = quartzFrame(of: target) else { return nil }
        return CGRect(
            x: quartz.minX, y: deps.primaryHeight() - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    /// The target in Quartz global points (what the stream and the timeline use).
    func quartzFrame(of target: RecordingTarget) -> CGRect? {
        guard let display = deps.display(target.display) else { return nil }
        switch target {
        case .area(let area):
            return CGRect(
                x: display.bounds.minX + area.rect.minX, y: display.bounds.minY + area.rect.minY,
                width: area.rect.width, height: area.rect.height)
        case .display:
            return display.bounds
        case .window(let id, _, let cocoa):
            if let followed = followedWindow, followed.id == id { return followed.quartz }
            let quartzY = deps.primaryHeight() - (cocoa.origin.y + cocoa.size.height)
            return CGRect(x: cocoa.origin.x, y: quartzY, width: cocoa.size.width, height: cocoa.size.height)
        }
    }

    private func countdown(_ digit: Int) {
        guard let s = flow.state.session, let target = currentTarget, let frame = frame(of: target) else { return }
        deps.surfaces.showCountdown(digit, in: frame)
        guard countdownTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.countdownTick(s)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func prepare(_ s: SessionID, _ request: RecorderRequest) {
        guard let display = deps.display(request.target.display), let quartz = quartzFrame(of: request.target) else {
            send(.recorderFailed(s, .other(StreamRecorder.Failure.noDisplay.localizedDescription)))
            return
        }
        let local = RecordingGeometry.clampedSourceRect(
            Rect2D(
                x: quartz.minX - display.bounds.minX, y: quartz.minY - display.bounds.minY, width: quartz.width,
                height: quartz.height),
            display: Size2D(width: display.bounds.width, height: display.bounds.height))
        var window: CGWindowID?
        if case .window(let id, _, _) = request.target {
            window = id.rawValue
            followedWindow = (
                id,
                CGRect(
                    x: display.bounds.minX + local.origin.x, y: display.bounds.minY + local.origin.y,
                    width: local.width, height: local.height)
            )
        }
        if request.options.clicks || request.options.keys, let cocoa = frame(of: request.target) {
            deps.overlays?.show(area: cocoa)
        }
        let exceptions = (deps.overlays?.windowIDs ?? []) + [deps.surfaces.bubbleWindowID].compactMap { $0 }
        let take = UUID()
        let folder = CaptureFolders.recordingsInProgress(home: context.home)
        try? SaveFolder.ensureExists(at: folder)
        let streamRequest = StreamRequest(
            display: request.target.display.rawValue,
            sourceRect: CGRect(x: local.origin.x, y: local.origin.y, width: local.width, height: local.height),
            options: request.options, window: window,
            overlayWindowIDs: exceptions,
            output: folder.appendingPathComponent(TakeRecovery.movieName(take: take)))
        let callbacks = StreamRecorder.Callbacks(
            firstFrame: { [weak self] host, date in self?.firstFrame(s, host: host, date: date) },
            failed: { [weak self] failure in self?.send(.recorderFailed(s, Self.failure(failure))) },
            areaMoved: { [weak self] rect in self?.areaMoved(s, rect) },
            log: { [weak self] text in self?.logger.info("\(text, privacy: .public)") })
        lastScale = display.scale
        let recorder = deps.makeRecorder(callbacks)
        recorders[s] = recorder
        requests[s] = streamRequest
        let kind =
            switch request.target {
            case .area: "area"
            case .display: "display"
            case .window: "window"
            }
        logger.info("target \(kind, privacy: .public) on display \(request.target.display.rawValue)")
        Task {
            do {
                try await recorder.prepare(streamRequest)
                // Cancelled or stopped while it was preparing: the effect found nothing to stop then, so stop
                // what `prepare` started now (PR #23 review C1, R3).
                guard recorders[s] === recorder else {
                    await recorder.cancel()
                    return
                }
                send(.recorderReady(s))
            } catch let failure as StreamRecorder.Failure {
                send(.recorderFailed(s, Self.failure(failure)))
            } catch {
                send(.recorderFailed(s, .other(error.localizedDescription)))
            }
        }
    }

    private static func failure(_ failure: StreamRecorder.Failure) -> RecorderFailure {
        failure == .userDeclined ? .userDeclined : .other(failure.localizedDescription)
    }

    private func firstFrame(_ s: SessionID, host: Double, date: Date) {
        guard flow.state.session == s else { return }
        firstFrameHost = host
        firstFrameDate = date
        if wantsTimeline, timeline == nil { startTimeline(at: host) }
        send(.takeStarted(s, hostTime: host, date: date))
    }

    /// A followed window moved. Only the current session's recorder moves anything; the border is red only once
    /// the take is live (§5.1, PR #23 review I1).
    private func areaMoved(_ s: SessionID, _ displayLocal: CGRect) {
        guard flow.state.session == s, case .window(let id, let display, _)? = currentTarget,
            let bounds = deps.display(display)?.bounds
        else { return }
        let quartz = displayLocal.offsetBy(dx: bounds.minX, dy: bounds.minY)
        followedWindow = (id, quartz)
        let cocoa = CGRect(
            x: quartz.minX, y: deps.primaryHeight() - quartz.maxY, width: quartz.width, height: quartz.height)
        let live: Bool
        switch flow.state {
        case .recording, .paused: live = true
        default: live = false
        }
        deps.surfaces.showBorder(cocoa, recording: live)
        deps.surfaces.moveBubble(area: cocoa)
        deps.overlays?.move(area: cocoa)
        feedTimeline(
            .input(
                .area(Rect2D(x: quartz.minX, y: quartz.minY, width: quartz.width, height: quartz.height)),
                deps.hostNow()))
    }

    private func stopRecorder(_ s: SessionID) {
        guard let recorder = recorders.removeValue(forKey: s) else {
            send(.stopped(s, .noFrames))
            return
        }
        let request = requests.removeValue(forKey: s)
        let deadline = deps.stopDeadline
        Task {
            let result: StopResult
            switch await Deadline.race(deadline, { try await recorder.stop() }) {
            case .success(.movie(let url, let duration))?:
                result = .movie(url, duration: duration)
            case .success(.noFrames)?:
                result = .noFrames
            case .failure(let error)?:
                logger.error("failed: \(error.localizedDescription, privacy: .public)")
                result = await Self.fragments(request?.output)
            case nil:
                logger.error("failed: stop timed out")
                result = await Self.fragments(request?.output)
            }
            send(.stopped(s, result))
        }
    }

    /// A failed or stuck writer leaves its fragments: keep them if anything is there (`design/04` §3), with the
    /// duration they hold.
    nonisolated private static func fragments(_ url: URL?) async -> StopResult {
        guard let url, let size = size(of: url), size >= TakeRecovery.minimumMovieBytes else { return .noFrames }
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return .movie(url, duration: duration.isFinite ? duration : 0)
    }

    nonisolated private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private func convert(_ s: SessionID, _ url: URL, deadline: Double) {
        let output = url.deletingPathExtension().appendingPathExtension("mp4")
        let home = CaptureFolders.recordingsInProgress(home: context.home)
        let free = deps.freeBytes
        let convert = deps.convert
        let started = ContinuousClock.now
        Task {
            let movieBytes = Self.size(of: url) ?? 0
            let freeBytes = await Task.detached { free(home) ?? .max }.value
            guard DiskGuard.canConvert(movieBytes: movieBytes, freeBytes: freeBytes) else {
                logger.info("kept mov: disk")
                send(.converted(s, url, isMov: true))
                return
            }
            let outcome = await convert(url, output, .seconds(deadline)) { [weak self] fraction in
                Task { @MainActor in self?.send(.conversionProgress(s, fraction)) }
            }
            switch outcome {
            case .converted(let mp4):
                let ms = (ContinuousClock.now - started).components.seconds * 1000
                logger.info("converted in \(ms) ms")
                send(.converted(s, mp4, isMov: false))
            case .keptMovie(let reason):
                logger.info("kept mov: \(reason, privacy: .public)")
                send(.converted(s, url, isMov: true))
            }
        }
    }

    private func deliver(_ s: SessionID, _ url: URL, date: Date?, duration: Double) {
        let scale = currentScale
        let timelineURL = timelineURL
        self.timelineURL = nil
        let firstFrame = deps.firstFrame
        let deadline = deps.stopDeadline
        Task {
            let preview: PixelBuffer?
            if case .success(let image)? = await Deadline.race(deadline, { await firstFrame(url) }) {
                preview = image
            } else {
                preview = nil
            }
            let item = await delivery.deliver(
                movie: url, date: date ?? Date(), duration: duration, pixelsPerPoint: scale, timeline: timelineURL,
                preview: preview)
            if let item { logger.info("delivered \(item.fileURL.lastPathComponent, privacy: .private) \(duration) s") }
            send(.delivered(s, item))
        }
    }

    private var lastScale: Double = 2
    private var currentScale: Double { lastScale }

    // MARK: Timers and monitors

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let s = self.flow.state.session else { return }
                self.send(.tick(s, hostNow: self.deps.hostNow()))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func startMonitor() {
        stopMonitor()
        let keys = permissions().accessibility == .granted
        let monitor = InputMonitor(
            sinks: InputMonitor.Sinks(
                input: { [weak self] input, host in self?.input(input, host: host) },
                key: { [weak self] press, host in self?.key(press, host: host) }))
        monitor.start(keys: keys)
        self.monitor = monitor
    }

    private func stopMonitor() {
        monitor?.stop()
        monitor = nil
    }

    private func input(_ input: TimelineInput, host: Double) {
        if case .down(let button, let point, _) = input { deps.overlays?.click(button, at: point) }
        feedTimeline(.input(input, host))
    }

    private func key(_ press: KeyPress, host: Double) {
        if !press.isRepeat { deps.overlays?.key(press) }
        feedTimeline(.input(.key(press), host))
    }

    /// Everything for the timeline goes through here, in order. Before the timeline exists, inputs are dropped
    /// (they come before its origin) and pause and resume stamps wait for it.
    private func feedTimeline(_ command: TimelineCommand) {
        if let feed = timelineFeed {
            feed.yield(command)
            return
        }
        switch command {
        case .pause, .resume:
            if wantsTimeline { pendingStamps.append(command) }
        case .input, .finish, .discard:
            break
        }
    }

    /// The single consumer of one timeline's commands.
    private func attach(_ recorder: TimelineRecorder, startedAt host: Double) {
        let (stream, feed) = AsyncStream.makeStream(of: TimelineCommand.self)
        timelineFeed = feed
        for stamp in pendingStamps {
            switch stamp {
            case .pause(let at): feed.yield(.pause(max(at, host)))
            case .resume(let at): feed.yield(.resume(max(at, host)))
            default: break
            }
        }
        pendingStamps = []
        let logger = timelineLogger
        Task {
            for await command in stream {
                switch command {
                case .input(let input, let at): await recorder.record(input, at: at)
                case .pause(let at): await recorder.pause(at: at)
                case .resume(let at): await recorder.resume(at: at)
                case .finish(let at):
                    let summary = await recorder.finish(at: at)
                    logger.info("finish \(summary.events) events \(summary.bytes) bytes")
                    for reason in summary.truncations {
                        logger.info("truncated \(reason.rawValue, privacy: .public)")
                    }
                case .discard:
                    await recorder.discard()
                    logger.info("discarded")
                }
            }
        }
        // The focus line sent when the monitor started came before the timeline: send it again (PR #22 review I8).
        monitor?.resendFocus()
    }

    // MARK: Timeline (§7)

    private func startTimeline(at host: Double) {
        guard let s = flow.state.session, let request = requests[s], let target = currentTarget,
            let quartz = quartzFrame(of: target), let display = deps.display(target.display)
        else { return }
        lastScale = display.scale
        let take =
            UUID(uuidString: String(request.output.deletingPathExtension().lastPathComponent.dropFirst(5)))
            ?? UUID()
        let url = TimelineStore.takeURL(take: take, home: context.home)
        let accessibility = permissions().accessibility == .granted
        var kind: TimelineHeader.Target.Kind = .area
        var window: WindowID?
        switch target {
        case .display: kind = .display
        case .window(let id, _, _):
            kind = .window
            window = id
        case .area: kind = .area
        }
        let size = RecordingGeometry.outputSize(
            points: Size2D(width: request.sourceRect.width, height: request.sourceRect.height), scale: display.scale,
            codec: request.options.codec)
        let header = TimelineHeader(
            take: take, startedAt: firstFrameDate,
            target: TimelineHeader.Target(
                kind: kind, display: target.display, scale: display.scale, window: window,
                area: Rect2D(x: quartz.minX, y: quartz.minY, width: quartz.width, height: quartz.height)),
            video: TimelineHeader.Video(width: size.width, height: size.height, fps: request.options.fps),
            cursorHz: 30, hasKeys: accessibility, hasElements: accessibility)
        let reader = accessibility ? deps.reader : nil
        timelineURL = url
        // Created off the main actor (PR #4 review M6), then handed back.
        Task {
            let recorder = await Task.detached {
                try? TimelineRecorder(
                    TimelineRecorder.Configuration(url: url, header: header), reader: reader, startedAt: host)
            }.value
            guard let recorder else {
                timelineLogger.error("start failed")
                return
            }
            await recorder.startFlushing()
            if self.wantsTimeline, self.timelineURL == url {
                self.timeline = recorder
                self.attach(recorder, startedAt: host)
                timelineLogger.info("start \(take.uuidString.lowercased(), privacy: .public)")
            } else {
                await recorder.discard()
            }
        }
    }

    private func finishTimeline() {
        wantsTimeline = false
        firstFrameHost = nil
        pendingStamps = []
        guard timeline != nil, let feed = timelineFeed else { return }
        timeline = nil
        timelineFeed = nil
        feed.yield(.finish(deps.hostNow()))
        feed.finish()
    }

    private func discardTimeline() {
        wantsTimeline = false
        firstFrameHost = nil
        timelineURL = nil
        pendingStamps = []
        guard timeline != nil, let feed = timelineFeed else { return }
        timeline = nil
        timelineFeed = nil
        feed.yield(.discard)
        feed.finish()
    }
}

/// Races work against a deadline: nil when the deadline passes first. The work keeps running, unobserved.
enum Deadline {
    /// Resumes its continuation once.
    private final class Once<T: Sendable>: Sendable {
        private let state = Mutex<CheckedContinuation<T, Never>?>(nil)

        func set(_ continuation: CheckedContinuation<T, Never>) { state.withLock { $0 = continuation } }

        func resume(_ value: T) {
            let waiting = state.withLock { stored -> CheckedContinuation<T, Never>? in
                defer { stored = nil }
                return stored
            }
            waiting?.resume(returning: value)
        }
    }

    static func race<T: Sendable>(
        _ limit: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async -> Result<T, any Error>? {
        let once = Once<Result<T, any Error>?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled { once.resume(nil) }
            }
            Task {
                do {
                    once.resume(.success(try await work()))
                } catch {
                    once.resume(.failure(error))
                }
                timer.cancel()
            }
        }
    }
}
