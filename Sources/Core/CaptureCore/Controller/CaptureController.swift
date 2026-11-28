import BugeyeCore
import Foundation

/// Runs captures (plan P2): owns the `CaptureFlow`, performs its effects through ports and the shell, runs the
/// output order (save → copy → publish `created`), holds `ScreenActivity.screenshotSelection` while a screenshot is
/// out of `idle`, and implements `AreaSelector` for Recording (Capture C4, §6.1).
@MainActor
public final class CaptureController: AreaSelector {
    private let environment: CaptureEnvironment
    private let bus: CaptureEventBus
    private let activity: ScreenActivity
    private let registrar: any HotkeyRegistrar
    private weak var shell: (any CaptureShell)?
    private let output: OutputRouter

    private var flow: CaptureFlow
    /// Events waiting to be handled, each with the settings read at its request (nil for any other event).
    private var queue: [(event: FlowEvent, settings: CaptureSettings?)] = []
    private var handling = false
    private var nextTicket = 1
    private var continuations: [SelectionTicket: CheckedContinuation<SelectionResult, Never>] = [:]

    // Per-session data the flow doesn't hold (pixels, settings, log numbers), dropped when the session ends.
    private var frames: [SessionID: [FrozenDisplay]] = [:]
    private var windowTasks: [SessionID: Task<[WindowInfo], Never>] = [:]
    private var windowImages: [SessionID: CapturedImage] = [:]
    private var sessionSettings: [SessionID: CaptureSettings] = [:]
    private var overlayNumbers: [SessionID: [Int]] = [:]
    private var inFlight: [Int: Task<Void, Never>] = [:]
    private var phaseWaiters: [(CaptureFlow.Phase, CheckedContinuation<Void, Never>)] = []
    private var nextTask = 0

    public init(
        environment: CaptureEnvironment, bus: CaptureEventBus, activity: ScreenActivity, registrar: any HotkeyRegistrar,
        shell: any CaptureShell
    ) {
        self.environment = environment
        self.bus = bus
        self.activity = activity
        self.registrar = registrar
        self.shell = shell
        output = OutputRouter(writer: environment.writer, clipboard: environment.clipboard)
        flow = CaptureFlow(ownPID: environment.ownPID)
    }

    // MARK: Inputs

    /// A screenshot request from a hotkey or a menu item. Settings are read now (Capture §5.7).
    public func request(_ kind: CaptureRequestKind) {
        let pointer = shell?.pointerLocation() ?? CocoaPoint(x: 0, y: 0)
        enqueue(
            .request(
                kind, permitted: environment.permission.preflight(), activityAllows: activity.allows(.screenshot),
                pointer: pointer, lastArea: LastAreaStore.load(from: environment.settings)),
            settings: CaptureSettings.load(from: environment.settings))
    }

    /// Feeds one event to the flow. Events sent while effects run are queued and handled after them, in order.
    public func send(_ event: FlowEvent) {
        enqueue(event, settings: nil)
    }

    private func enqueue(_ event: FlowEvent, settings: CaptureSettings?) {
        queue.append((event, settings))
        guard !handling else { return }
        handling = true
        defer { handling = false }
        while !queue.isEmpty {
            let (next, requestSettings) = queue.removeFirst()
            let wasSession = flow.session
            let effects = flow.handle(next)
            if wasSession == nil, let session = flow.session, let settings = requestSettings {
                sessionSettings[session] = settings
            }
            for effect in effects { perform(effect) }
            updateActivity()
            if let wasSession, flow.session != wasSession { forget(wasSession) }
            resumePhaseWaiters()
        }
    }

    /// Returns once the flow is in `phase`: now, or the next time it enters it. A phase entered and left before the
    /// call isn't seen, so callers wait for a phase they know is coming. Tests use it instead of polling.
    public func waitUntil(_ phase: CaptureFlow.Phase) async {
        guard flow.phase != phase else { return }
        await withCheckedContinuation { phaseWaiters.append((phase, $0)) }
    }

    private func resumePhaseWaiters() {
        let current = flow.phase
        let ready = phaseWaiters.filter { $0.0 == current }
        phaseWaiters.removeAll { $0.0 == current }
        for (_, continuation) in ready { continuation.resume() }
    }

    public func select(_ request: SelectionRequest) async -> SelectionResult {
        let ticket = SelectionTicket(nextTicket)
        nextTicket += 1
        return await withCheckedContinuation { continuation in
            continuations[ticket] = continuation
            send(.select(ticket, request))
        }
    }

    public func cancel(_ purpose: SelectionPurpose) {
        send(.externalCancel(purpose))
    }

    // MARK: Outputs for the shell

    /// What `display`'s overlay draws now.
    public func overlay(for display: DisplayID) -> OverlayRender? { flow.overlay(for: display) }

    /// The live session's phase.
    public var phase: CaptureFlow.Phase { flow.phase }

    /// The live session, if any.
    public var session: SessionID? { flow.session }

    /// Sessions whose frozen frames are still held (tests: a finished or cancelled session holds none).
    public var heldFrameSessions: Int { frames.count }

    /// Sessions whose live window capture is still held.
    public var heldWindowImages: Int { windowImages.count }

    /// Freezes, window captures and deliveries still running.
    public var inFlightCount: Int { inFlight.count }

    /// Waits until every freeze, window capture and delivery started so far has finished (tests, debug).
    public func settle() async {
        while let (key, task) = inFlight.first {
            await task.value
            inFlight[key] = nil
        }
    }

    // MARK: Temp purge (C11, C28)

    /// Purges the temp folder. The hourly purge skips captures the bus still knows.
    @discardableResult
    public func purgeTemp(skippingKnown: Bool) async -> Int {
        let janitor = TempJanitor(metadata: environment.metadata)
        let folder = CaptureFolders.temp(home: environment.home)
        let now = environment.now()
        let candidates = await Task.detached { janitor.candidates(in: folder, now: now) }.value
        let doomed = skippingKnown ? candidates.filter { $0.id.map { bus.item($0) == nil } ?? true } : candidates
        let removed = await Task.detached { janitor.remove(doomed) }.value
        if removed > 0 { shell?.log(.capture, "purged \(removed) temp files") }
        return removed
    }

    // MARK: Effects

    private func perform(_ effect: FlowEffect) {
        switch effect {
        case .readWindowList(let session):
            let reader = environment.windowList
            windowTasks[session] = Task.detached { await reader.windows() }
        case .freeze(let session, let target):
            freeze(session, target)
        case .showOverlays(let session, let displays, let mode):
            let shown = (frames[session] ?? []).filter { displays.contains($0.display.id) }
            shell?.showOverlays(session, frames: shown, mode: mode)
        case .closeOverlays(let session):
            shell?.closeOverlays(session)
            shell?.sweepLeftovers(keeping: nil)
        case .sweepLeftovers:
            shell?.sweepLeftovers(keeping: flow.phase == .selecting ? flow.session : nil)
        case .makeKey(let session, let display):
            shell?.makeKey(session, display: display)
        case .redraw(let session, let display, let damage):
            shell?.redraw(session, display: display, damage: damage)
        case .registerEscape:
            let ok = registrar.register(CaptureModule.ID.escape, key: .escape) { [weak self] in
                self?.send(.globalEscape)
            }
            shell?.log(.hotkeys, ok ? "escape on" : "escape taken")
        case .unregisterEscape:
            registrar.unregister(CaptureModule.ID.escape)
            shell?.log(.hotkeys, "escape off")
        case .activateBugeye:
            shell?.activateBugeye()
        case .reactivatePreviousApp:
            shell?.reactivatePreviousApp()
        case .beep:
            shell?.beep()
        case .captureWindow(let session, let id, let size, let scale):
            captureWindow(session, id, size: size, scale: scale)
        case .deliver(let session, let deliveries):
            deliver(session, deliveries)
        case .storeLastArea(let area):
            LastAreaStore.save(area, to: environment.settings)
        case .showPermissionAlert:
            shell?.showPermissionAlert()
        case .notify(let title, let body):
            environment.notifier.post(title: title, body: body)
        case .log(let category, let message):
            shell?.log(category, message)
        case .logSelectionBegin(let session, let purpose):
            let numbers = shell?.overlayWindowNumbers(session) ?? []
            overlayNumbers[session] = numbers
            shell?.log(.selection, "begin \(purpose.rawValue) overlays \(numbers)")
        case .logSelectionFinish(let session, let outcome):
            shell?.log(.selection, "finish \(outcome.rawValue) overlays \(overlayNumbers[session] ?? [])")
        case .answer(let ticket, let result):
            continuations.removeValue(forKey: ticket)?.resume(returning: result)
        }
    }

    private func updateActivity() {
        if flow.purpose == .screenshot {
            activity.begin(.screenshotSelection)
        } else {
            activity.end(.screenshotSelection)
        }
    }

    private func forget(_ session: SessionID) {
        frames[session] = nil
        windowTasks[session]?.cancel()
        windowTasks[session] = nil
        windowImages[session] = nil
        sessionSettings[session] = nil
        overlayNumbers[session] = nil
    }

    private func track(_ work: @escaping @MainActor () async -> Void) {
        let key = nextTask
        nextTask += 1
        inFlight[key] = Task { @MainActor [weak self] in
            await work()
            self?.inFlight[key] = nil
        }
    }

    private func freeze(_ session: SessionID, _ target: FreezeTarget) {
        let source = environment.screenSource
        let clock = environment.now
        track { [weak self] in
            let start = clock()
            let result: Result<[FrozenDisplay], ScreenSourceError> = await Task.detached {
                do {
                    let wanted: [DisplayID]?
                    switch target {
                    case .all: wanted = nil
                    case .underPointer(let pointer):
                        let displays = try await source.displays()
                        let under = displays.first { $0.cocoaFrame.contains(pointer) } ?? displays.first
                        guard let under else { throw ScreenSourceError.displayNotFound }
                        wanted = [under.id]
                    }
                    return .success(try await source.freeze(displays: wanted))
                } catch {
                    return .failure(Self.map(error))
                }
            }.value
            guard let self else { return }
            let windows = await windowTasks[session]?.value ?? []
            // A freeze that outlived its session (cancelled meanwhile) changes nothing and keeps no frames.
            guard flow.session == session, flow.phase == .freezing else { return }
            switch result {
            case .success(let frozen):
                let ms = Int((clock().timeIntervalSince(start) * 1000).rounded())
                shell?.log(.capture, "freeze \(frozen.count) displays in \(ms) ms")
                frames[session] = frozen
                let infos = frozen.map {
                    FrameInfo(
                        display: $0.display, pixelWidth: $0.image.pixelWidth, pixelHeight: $0.image.pixelHeight,
                        time: $0.time)
                }
                send(
                    .frozen(
                        session, infos, windows: windows, pointer: shell?.pointerLocation() ?? CocoaPoint(x: 0, y: 0)))
            case .failure(let error):
                send(.freezeFailed(session, error))
            }
        }
    }

    private func captureWindow(_ session: SessionID, _ id: WindowID, size: Size2D, scale: Double) {
        let source = environment.screenSource
        let pipeline = environment.pipeline
        let clock = environment.now
        track { [weak self] in
            let result: Result<CapturedImage, ScreenSourceError> = await Task.detached {
                do {
                    let image = try await WindowShadow.atFullScale(
                        windowSize: size, scale: scale,
                        capture: { try await source.captureWindow(id, pixelSize: $0) },
                        measure: { pipeline.pixelBuffer($0) })
                    return .success(image)
                } catch {
                    return .failure(Self.map(error))
                }
            }.value
            guard let self else { return }
            // A result that outlived its session changes nothing and keeps no image (design/11 §6). The flow can't
            // leave `finishing` while a window capture is awaited today; this keeps it so if that ever changes.
            guard flow.session == session, flow.phase == .finishing else { return }
            switch result {
            case .success(let image):
                windowImages[session] = image
                send(.windowCaptured(session, time: clock()))
            case .failure(let error):
                send(.windowCaptureFailed(session, error))
            }
        }
    }

    private func deliver(_ session: SessionID, _ deliveries: [Delivery]) {
        let settings = sessionSettings[session] ?? CaptureSettings.load(from: environment.settings)
        let folder = environment.saveFolder()
        let temp = CaptureFolders.temp(home: environment.home)
        let pipeline = environment.pipeline
        let router = output
        let timeZone = environment.timeZone
        // The crop itself runs off the main actor, in `prepare`.
        let sources: [(Delivery, CapturedImage?, PixelRect?)] = deliveries.map { delivery in
            switch delivery.source {
            case .window: (delivery, windowImages[session], nil)
            case .frame(let display, let crop):
                (delivery, frames[session]?.first { $0.display.id == display }?.image, crop)
            }
        }
        track { [weak self] in
            var notices: [Notice] = []
            for (delivery, image, crop) in sources {
                let prepared: Prepared = await Task.detached {
                    Self.prepare(image, crop: crop, delivery: delivery, settings: settings, pipeline: pipeline)
                }.value
                guard let self else { return }
                switch prepared {
                case .failed(let body):
                    shell?.log(.capture, "failed screenshot: \(body)")
                    notices.append(Notice(title: CaptureStrings.captureFailedTitle, body: body))
                case .encoded(let png, let ppp, let preview):
                    let request = OutputRequest(
                        png: png, id: CaptureID(), createdAt: delivery.time, pixelsPerPoint: ppp, settings: settings,
                        saveFolder: folder.url, displayedSaveFolder: folder.displayed, tempFolder: temp,
                        timeZone: timeZone)
                    let result = await Task.detached { router.deliver(request) }.value
                    for line in result.logs { shell?.log(.capture, line) }
                    notices += result.notices
                    if let item = result.item {
                        bus.publish(
                            CaptureEvent(
                                change: .created, item: item, preview: preview, origin: CaptureModule.ID.module))
                    }
                }
            }
            self?.send(.delivered(session, notices: notices))
        }
    }

    enum Prepared: Sendable {
        case encoded(Data, pixelsPerPoint: Double, preview: PixelBuffer?)
        case failed(String)
    }

    /// Crop, downscale (when on and scale > 1), encode, preview. Off the main actor.
    nonisolated static func prepare(
        _ image: CapturedImage?, crop: PixelRect?, delivery: Delivery, settings: CaptureSettings,
        pipeline: any ImagePipeline
    ) -> Prepared {
        guard let source = image, var image = crop.map({ pipeline.crop(source, to: $0.raw) }) ?? source else {
            return .failed(CaptureStrings.displayDisconnected)
        }
        var ppp = delivery.scale
        if settings.downscaleToPoints, delivery.scale > 1, let small = pipeline.downscale(image, by: 1 / delivery.scale)
        {
            image = small
            ppp = 1
        }
        guard let png = pipeline.pngData(image) else { return .failed(CaptureStrings.encodeFailed) }
        return .encoded(png, pixelsPerPoint: ppp, preview: pipeline.preview(image))
    }

    nonisolated static func map(_ error: any Error) -> ScreenSourceError {
        (error as? ScreenSourceError) ?? .failed(error.localizedDescription)
    }
}
