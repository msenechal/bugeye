import BugeyeCore
import Foundation

/// The single owner of a capture (Capture §6): pure, no AppKit, tested on Linux. The shell feeds it events and
/// performs the effects it returns. Overlays exist only in `selecting` (I1); leaving it closes them and releases the
/// Esc hotkey exactly once (I2, I3); every request out of `idle` returns there exactly once (I4).
public struct CaptureFlow: Sendable {
    public enum Phase: Hashable, Sendable { case idle, freezing, selecting, finishing }

    enum Job: Hashable, Sendable {
        case screenshot(CaptureRequestKind, lastArea: StoredArea?)
        case selector(SelectionTicket, SelectionRequest)

        var purpose: SelectionPurpose {
            switch self {
            case .screenshot: .screenshot
            case .selector(_, let request): request.purpose
            }
        }

        var logName: String {
            switch self {
            case .screenshot(let kind, _): kind.rawValue
            case .selector(_, let request): request.purpose.rawValue
            }
        }
    }

    struct Selecting: Hashable, Sendable {
        var session: SessionID
        var job: Job
        var frames: [FrameInfo]
        var windows: [WindowInfo]
        var mode: OverlayMode
        var drag: Drag?
        var hovered: WindowInfo?
    }

    enum State: Hashable, Sendable {
        case idle
        case freezing(SessionID, Job)
        case selecting(Selecting)
        case finishing(SessionID, Job, scale: Double)
    }

    private(set) var state: State = .idle
    private var nextSession = 1
    public let ownPID: Int32

    public init(ownPID: Int32) {
        self.ownPID = ownPID
    }

    public var phase: Phase {
        switch state {
        case .idle: .idle
        case .freezing: .freezing
        case .selecting: .selecting
        case .finishing: .finishing
        }
    }

    /// The live session; nil in `idle`.
    public var session: SessionID? {
        switch state {
        case .idle: nil
        case .freezing(let s, _), .finishing(let s, _, _): s
        case .selecting(let selecting): selecting.session
        }
    }

    /// The purpose of the job out of `idle`; nil in `idle`.
    public var purpose: SelectionPurpose? {
        switch state {
        case .idle: nil
        case .freezing(_, let job), .finishing(_, let job, _): job.purpose
        case .selecting(let selecting): selecting.job.purpose
        }
    }

    /// What `display`'s overlay draws; nil outside `selecting` or for a display that wasn't frozen.
    public func overlay(for display: DisplayID) -> OverlayRender? {
        guard case .selecting(let s) = state, let frame = s.frames.first(where: { $0.display.id == display }) else {
            return nil
        }
        let hint: String? =
            if case .selector(_, let request) = s.job { request.hint } else { nil }
        switch s.mode {
        case .area:
            let selection = s.drag.flatMap { drag -> DisplayRect? in
                guard drag.display == display else { return nil }
                let rect = drag.rect(displaySize: frame.display.pointSize)
                return rect.raw.isEmpty ? nil : rect
            }
            return OverlayRender(mode: .area, selection: selection, hovered: nil, hint: hint)
        case .window:
            let hovered = s.hovered.map {
                QuartzRect($0.bounds).displayLocal(displayQuartzFrame: quartzFrame(frame, in: s.frames))
            }
            return OverlayRender(mode: .window, selection: nil, hovered: hovered, hint: hint)
        }
    }

    // MARK: Events

    public mutating func handle(_ event: FlowEvent) -> [FlowEffect] {
        switch event {
        case .request(let kind, let permitted, let activityAllows, let pointer, let lastArea):
            return request(
                kind, permitted: permitted, activityAllows: activityAllows, pointer: pointer, lastArea: lastArea)
        case .select(let ticket, let request):
            guard case .idle = state else { return [.answer(ticket, .busy)] }
            let session = startSession()
            state = .freezing(session, .selector(ticket, request))
            return [.readWindowList(session), .freeze(session, .all)]
        case .externalCancel(let purpose):
            return externalCancel(purpose)
        case .frozen(let session, let frames, let windows, let pointer):
            guard case .freezing(session, let job) = state else { return [] }
            return frozen(session, job, frames: frames, windows: windows, pointer: pointer)
        case .freezeFailed(let session, let error):
            guard case .freezing(session, let job) = state else { return [] }
            state = .idle
            return failure(error, job: job) + answer(job, .cancelled)
        case .windowCaptured(let session, let time):
            guard case .finishing(session, let job, let scale) = state else { return [] }
            state = .finishing(session, job, scale: scale)
            return [.deliver(session, [Delivery(source: .window, scale: scale, time: time)])]
        case .windowCaptureFailed(let session, let error):
            guard case .finishing(session, let job, _) = state else { return [] }
            state = .idle
            return failure(error, job: job)
        case .delivered(let session, let notices):
            guard case .finishing(session, _, _) = state else { return [] }
            state = .idle
            return notices.map { .notify(title: $0.title, body: $0.body) }
        case .globalEscape, .displaysChanged:
            guard case .selecting(let s) = state else { return [] }
            return cancel(s)
        case .pointerMoved(let session, _, _), .pointerEntered(let session, _, _), .mouseDown(let session, _, _, _),
            .mouseDragged(let session, _, _, _), .mouseUp(let session, _, _), .rightMouseDown(let session),
            .key(let session, _):
            guard case .selecting(let s) = state, s.session == session else {
                // A view of another session is a leftover; the live session's views outside `selecting` do nothing.
                return session == self.session ? [] : [.sweepLeftovers]
            }
            return viewEvent(event, s)
        }
    }

    private mutating func startSession() -> SessionID {
        defer { nextSession += 1 }
        return SessionID(nextSession)
    }

    private mutating func request(
        _ kind: CaptureRequestKind, permitted: Bool, activityAllows: Bool, pointer: CocoaPoint, lastArea: StoredArea?
    ) -> [FlowEffect] {
        guard case .idle = state, activityAllows else { return [.log(.capture, "busy: dropped \(kind.rawValue)")] }
        guard permitted else { return [.showPermissionAlert] }
        let session = startSession()
        state = .freezing(session, .screenshot(kind, lastArea: lastArea))
        switch kind {
        case .fullscreen: return [.freeze(session, .underPointer(pointer))]
        case .allDisplays: return [.freeze(session, .all)]
        case .area, .window: return [.readWindowList(session), .freeze(session, .all)]
        }
    }

    private mutating func externalCancel(_ purpose: SelectionPurpose) -> [FlowEffect] {
        switch state {
        case .freezing(_, let job) where isSelector(job, purpose):
            state = .idle
            return answer(job, .cancelled)
        case .selecting(let s) where isSelector(s.job, purpose):
            return cancel(s)
        default:
            return []
        }
    }

    private func isSelector(_ job: Job, _ purpose: SelectionPurpose) -> Bool {
        if case .selector(_, let request) = job { request.purpose == purpose } else { false }
    }

    private mutating func frozen(
        _ session: SessionID, _ job: Job, frames: [FrameInfo], windows: [WindowInfo], pointer: CocoaPoint
    ) -> [FlowEffect] {
        guard !frames.isEmpty else {
            state = .idle
            return failure(.displayNotFound, job: job) + answer(job, .cancelled)
        }
        if case .screenshot(let kind, _) = job, kind == .fullscreen || kind == .allDisplays {
            let ordered = Self.displayOrder(frames)
            state = .finishing(session, job, scale: ordered[0].scale)
            return [
                .deliver(
                    session,
                    ordered.map { Delivery(source: .frame($0.display.id, crop: nil), scale: $0.scale, time: $0.time) })
            ]
        }
        let startInWindow: Bool
        switch job {
        case .screenshot(let kind, _): startInWindow = kind == .window
        case .selector(_, let request): startInWindow = request.startInWindowMode
        }
        let mode: OverlayMode = startInWindow ? .window : .area
        state = .selecting(Selecting(session: session, job: job, frames: frames, windows: windows, mode: mode))
        let key = frames.first { $0.display.cocoaFrame.contains(pointer) } ?? frames[0]
        return [
            .sweepLeftovers, .showOverlays(session, displays: frames.map(\.display.id), mode: mode),
            .registerEscape(session), .activateBugeye, .makeKey(session, key.display.id),
            .logSelectionBegin(session, job.purpose),
        ]
    }

    /// Primary display first, then the source's order (C10).
    static func displayOrder(_ frames: [FrameInfo]) -> [FrameInfo] {
        let isPrimary = { (f: FrameInfo) in f.display.frame.minX == 0 && f.display.frame.minY == 0 }
        return frames.filter(isPrimary) + frames.filter { !isPrimary($0) }
    }

    // MARK: Selecting

    private mutating func viewEvent(_ event: FlowEvent, _ s: Selecting) -> [FlowEffect] {
        var s = s
        switch event {
        case .pointerEntered(_, let display, let buttonDown):
            return buttonDown || !s.frames.contains { $0.display.id == display } ? [] : [.makeKey(s.session, display)]
        case .rightMouseDown, .key(_, .escape):
            return cancel(s)
        case .key(_, .space):
            s.mode = s.mode == .area ? .window : .area
            s.drag = nil
            s.hovered = nil
            state = .selecting(s)
            return s.frames.map { .redraw(s.session, $0.display.id, damage: nil) }
        case .key(_, .return):
            return recaptureLast(s)
        case .pointerMoved(_, let display, let point):
            guard s.mode == .window, let frame = s.frames.first(where: { $0.display.id == display }) else { return [] }
            let hit = hitTest(point, on: frame, in: s)
            guard hit?.id != s.hovered?.id else { return [] }
            s.hovered = hit
            state = .selecting(s)
            return s.frames.map { .redraw(s.session, $0.display.id, damage: nil) }
        case .mouseDown(_, let display, let point, let modifiers):
            guard let frame = s.frames.first(where: { $0.display.id == display }) else { return [] }
            if s.mode == .window { return windowClick(point, on: frame, s) }
            let damage = s.drag.flatMap { damageRect(of: $0, in: s) }
            let local = point.displayLocal(displayHeight: frame.display.frame.height)
            s.drag = Drag(display: display, anchor: local, fromCentre: modifiers.option)
            state = .selecting(s)
            return damage.map { [.redraw(s.session, $0.0, damage: $0.1)] } ?? []
        case .mouseDragged(_, _, let point, let modifiers):
            guard s.mode == .area, var drag = s.drag,
                let frame = s.frames.first(where: { $0.display.id == drag.display })
            else { return [] }
            let size = frame.display.pointSize
            let old = drag.rect(displaySize: size)
            drag.update(
                to: point.displayLocal(displayHeight: size.height), shift: modifiers.shift, option: modifiers.option,
                displaySize: size)
            s.drag = drag
            state = .selecting(s)
            let new = drag.rect(displaySize: size)
            let union = Self.union(old.raw.isEmpty ? nil : old, new.raw.isEmpty ? nil : new)
            return union.map { [.redraw(s.session, drag.display, damage: Self.outset($0))] } ?? []
        case .mouseUp:
            return areaMouseUp(s)
        default:
            return []
        }
    }

    private mutating func areaMouseUp(_ s: Selecting) -> [FlowEffect] {
        var s = s
        guard s.mode == .area, let drag = s.drag, let frame = s.frames.first(where: { $0.display.id == drag.display })
        else { return [] }
        let rect = drag.rect(displaySize: frame.display.pointSize)
        guard SelectionGeometry.isCapturable(rect) else {
            if case .selector(_, let request) = s.job, request.clickSelectsDisplay {
                return leave(s, .display) + answer(s.job, .display(drag.display))
            }
            let damage = damageRect(of: drag, in: s)
            s.drag = nil
            state = .selecting(s)
            return damage.map { [.redraw(s.session, $0.0, damage: $0.1)] } ?? []
        }
        let area = StoredArea(display: drag.display, rect: rect.raw, displaySize: frame.display.pointSize)
        return finishArea(area, frame: frame, s)
    }

    private mutating func recaptureLast(_ s: Selecting) -> [FlowEffect] {
        let last: StoredArea? =
            switch s.job {
            case .screenshot(_, let lastArea): lastArea
            case .selector(_, let request): request.lastArea
            }
        guard let last, let frame = s.frames.first(where: { $0.display.id == last.display }),
            frame.display.pointSize == last.displaySize,
            DisplayRect(last.rect).pixelRect(
                scale: frame.scale, imageWidth: frame.pixelWidth, imageHeight: frame.pixelHeight) != nil
        else { return [.beep] }
        return finishArea(last, frame: frame, s)
    }

    private mutating func finishArea(_ area: StoredArea, frame: FrameInfo, _ s: Selecting) -> [FlowEffect] {
        guard case .screenshot = s.job else { return leave(s, .area) + answer(s.job, .area(area)) }
        guard
            let crop = DisplayRect(area.rect).pixelRect(
                scale: frame.scale, imageWidth: frame.pixelWidth, imageHeight: frame.pixelHeight)
        else { return [.beep] }
        let effects = [FlowEffect.storeLastArea(area)] + leave(s, .area)
        state = .finishing(s.session, s.job, scale: frame.scale)
        return effects + [
            .deliver(
                s.session, [Delivery(source: .frame(area.display, crop: crop), scale: frame.scale, time: frame.time)])
        ]
    }

    private mutating func windowClick(_ point: ViewPoint, on frame: FrameInfo, _ s: Selecting) -> [FlowEffect] {
        guard let window = hitTest(point, on: frame, in: s) else { return [.beep] }
        let bounds = QuartzRect(window.bounds)
        let displays = s.frames.map { ($0.display.id, quartzFrame($0, in: s.frames)) }
        let centreDisplay = WindowHitTest.display(containingCentreOf: bounds, in: displays)
        switch s.job {
        case .selector(_, let request):
            if request.windowNeedsDisplayCentre && centreDisplay == nil { return [.beep] }
            let cocoa = bounds.toCocoa(primaryHeight: DisplayInfo.primaryHeight(of: s.frames.map(\.display)))
            return leave(s, .window)
                + answer(s.job, .window(window.id, display: centreDisplay ?? frame.display.id, frame: cocoa.raw))
        case .screenshot:
            let scale = s.frames.first { $0.display.id == centreDisplay }?.scale ?? s.frames.first?.scale ?? 2
            let effects = leave(s, .window)
            state = .finishing(s.session, s.job, scale: scale)
            return effects + [
                .captureWindow(
                    s.session, window.id, windowSize: Size2D(width: bounds.raw.width, height: bounds.raw.height),
                    scale: scale)
            ]
        }
    }

    private func hitTest(_ point: ViewPoint, on frame: FrameInfo, in s: Selecting) -> WindowInfo? {
        let local = point.displayLocal(displayHeight: frame.display.frame.height)
        let quartz = local.quartz(displayQuartzFrame: quartzFrame(frame, in: s.frames))
        return WindowHitTest.topmost(at: quartz, in: s.windows, excludingPID: ownPID)
    }

    private func quartzFrame(_ frame: FrameInfo, in frames: [FrameInfo]) -> QuartzRect {
        frame.display.quartzFrame(primaryHeight: DisplayInfo.primaryHeight(of: frames.map(\.display)))
    }

    private func damageRect(of drag: Drag, in s: Selecting) -> (DisplayID, DisplayRect)? {
        guard let frame = s.frames.first(where: { $0.display.id == drag.display }) else { return nil }
        let rect = drag.rect(displaySize: frame.display.pointSize)
        return rect.raw.isEmpty ? nil : (drag.display, Self.outset(rect))
    }

    /// The selection plus its 1 pt border.
    static func outset(_ rect: DisplayRect) -> DisplayRect {
        DisplayRect(x: rect.raw.minX - 1, y: rect.raw.minY - 1, width: rect.width + 2, height: rect.height + 2)
    }

    static func union(_ a: DisplayRect?, _ b: DisplayRect?) -> DisplayRect? {
        guard let a else { return b }
        guard let b else { return a }
        let x0 = min(a.raw.minX, b.raw.minX)
        let y0 = min(a.raw.minY, b.raw.minY)
        return DisplayRect(
            x: x0, y: y0, width: max(a.raw.maxX, b.raw.maxX) - x0, height: max(a.raw.maxY, b.raw.maxY) - y0)
    }

    // MARK: Leaving

    private mutating func cancel(_ s: Selecting) -> [FlowEffect] {
        leave(s, .cancelled) + answer(s.job, .cancelled)
    }

    /// Closes the overlays, releases Esc, gives focus back and logs, in that order; the state becomes `idle`
    /// (a caller that finishes sets `finishing` afterwards).
    private mutating func leave(_ s: Selecting, _ outcome: SelectionOutcome) -> [FlowEffect] {
        state = .idle
        return [
            .closeOverlays(s.session), .unregisterEscape(s.session), .reactivatePreviousApp,
            .logSelectionFinish(s.session, outcome),
        ]
    }

    private func answer(_ job: Job, _ result: SelectionResult) -> [FlowEffect] {
        if case .selector(let ticket, _) = job { [.answer(ticket, result)] } else { [] }
    }

    private func failure(_ error: ScreenSourceError, job: Job) -> [FlowEffect] {
        guard let body = Self.failureBody(error) else { return [.showPermissionAlert] }
        return [
            .log(.capture, "failed \(job.logName): \(body)"),
            .notify(title: CaptureStrings.captureFailedTitle, body: body),
        ]
    }

    /// The `Capture failed` body for an error; nil for a missing permission (the alert shows instead).
    public static func failureBody(_ error: ScreenSourceError) -> String? {
        switch error {
        case .permissionDenied: nil
        case .displayNotFound: CaptureStrings.displayDisconnected
        case .windowNotFound: CaptureStrings.windowClosed
        case .failed(let description): description
        }
    }
}
