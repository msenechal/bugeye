import BugeyeCore
import BugeyeFeatures
import Foundation

/// Identifies one attempt, from ⇧⌘5 (or Restart) to idle. Every async result carries the session that asked
/// for it (`design/04` §2.3).
public struct SessionID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (a: SessionID, b: SessionID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { String(rawValue) }
}

/// What is recorded.
public enum RecordingTarget: Hashable, Sendable {
    /// Display-local, top-left, points, with the display's size at selection time (contracts K29).
    case area(StoredArea)
    case display(DisplayID)
    /// `frame` in Cocoa global points; followed while recording (§5.5).
    case window(WindowID, display: DisplayID, frame: Rect2D)

    public var display: DisplayID {
        switch self {
        case .area(let area): area.display
        case .display(let display): display
        case .window(_, let display, _): display
        }
    }
}

/// What the shell's recorder is asked to prepare: always effective options (R8).
public struct RecorderRequest: Hashable, Sendable {
    public var target: RecordingTarget
    public var options: RecordingOptions

    public init(target: RecordingTarget, options: RecordingOptions) {
        self.target = target
        self.options = options
    }
}

/// The camera bubble the flow wants; nil for none. The shell turns it into a `BubbleChange` against its
/// current bubble.
public struct BubbleWish: Hashable, Sendable {
    public var cameraDevice: String
    public var size: BubbleSize

    public init(cameraDevice: String, size: BubbleSize) {
        self.cameraDevice = cameraDevice
        self.size = size
    }
}

public enum ConfirmKind: String, Hashable, Sendable { case restart, discard }

public enum RecorderFailure: Hashable, Sendable {
    /// Screen Recording was refused (`SCStreamError.userDeclined`): Capture's alert, not a notice.
    case userDeclined
    /// Anything else, with its `localizedDescription`.
    case other(String)
}

public enum StopResult: Hashable, Sendable {
    case movie(URL, duration: Double)
    case noFrames
}

public enum FinishingStep: Hashable, Sendable { case stopping, converting, delivering }

/// A take from go-live to stop.
public struct Take: Hashable, Sendable {
    public var target: RecordingTarget
    /// Effective options.
    public var options: RecordingOptions
    public var clock = RecordingClock()
    /// The first frame's wall clock (`takeStarted`).
    public var startedAt: Date?
    var ticks = 0

    public init(target: RecordingTarget, options: RecordingOptions) {
        self.target = target
        self.options = options
    }

    func elapsed(at host: Double) -> Double { clock.elapsed(at: host) }
}

public enum RecordingState: Hashable, Sendable {
    case idle
    case selecting(SessionID)
    /// `options` are the user's; `permissions` and `devices` give the effective ones.
    case configuring(
        SessionID, RecordingTarget, RecordingOptions, permissions: RecordingPermissions, devices: CaptureDeviceList)
    /// From here on, `options` are effective.
    case countingDown(SessionID, RecordingTarget, RecordingOptions, remaining: Int, recorderReady: Bool)
    case starting(SessionID, RecordingTarget, RecordingOptions)
    case recording(SessionID, Take)
    case paused(SessionID, Take)
    case finishing(SessionID, FinishingStep, notice: RecordingNotice?, startedAt: Date?, duration: Double?)

    public var session: SessionID? {
        switch self {
        case .idle: nil
        case .selecting(let s), .configuring(let s, _, _, _, _), .countingDown(let s, _, _, _, _),
            .starting(let s, _, _), .recording(let s, _), .paused(let s, _), .finishing(let s, _, _, _, _):
            s
        }
    }
}

public enum RecordingEvent: Hashable, Sendable {
    /// ⇧⌘5, Record Screen, the ● menu's Stop.
    case toggle(screenPermitted: Bool, activityAllows: Bool, lastArea: StoredArea?)
    /// Settings, permissions and devices are read when the selection returns (the bar opens).
    case selected(
        SessionID, SelectionResult, options: RecordingOptions, permissions: RecordingPermissions,
        devices: CaptureDeviceList)
    case option(SessionID, RecordingOptionChange)
    case permissionAnswered(SessionID, MediaPermission, PermissionState)
    case record(SessionID, freeBytes: Int64)
    /// ✕, Esc.
    case cancel(SessionID)
    case countdownTick(SessionID)
    case recorderReady(SessionID)
    case recorderFailed(SessionID, RecorderFailure)
    /// The first complete frame after the countdown: its host time and wall clock.
    case takeStarted(SessionID, hostTime: Double, date: Date)
    /// The user's actions carry the host time they happened at, for the ● timer.
    case pause(SessionID, hostNow: Double)
    case resume(SessionID, hostNow: Double)
    case restart(SessionID, hostNow: Double)
    case discard(SessionID, hostNow: Double)
    case confirmed(SessionID, ConfirmKind)
    case declined(SessionID, ConfirmKind)
    /// Every 0.5 s.
    case tick(SessionID, hostNow: Double)
    case diskChecked(SessionID, freeBytes: Int64)
    case cameraUnavailable(SessionID)
    /// The display or window went away.
    case targetGone(SessionID)
    case stopped(SessionID, StopResult)
    /// 0…1 of the MP4 conversion.
    case conversionProgress(SessionID, Double)
    case converted(SessionID, URL, isMov: Bool)
    /// nil when even the temp folder refused the file (the shell posts that notice itself).
    case delivered(SessionID, CaptureItem?)
    case quitRequested
}

public enum ActivityChange: Hashable, Sendable {
    case begin(ScreenActivity.Activity)
    case end(ScreenActivity.Activity)
}

public enum BorderStyle: Hashable, Sendable { case dashed, recording }

public enum TimelineCommand: Hashable, Sendable { case start, finish, discard }

public enum RecordingEffect: Hashable, Sendable {
    case selection(SelectionRequest)
    case cancelSelection
    case activity(ActivityChange)
    case showBorder(RecordingTarget, BorderStyle)
    case closeBorder
    /// The user's options and the effective ones (which controls are unavailable).
    case showBar(options: RecordingOptions, effective: RecordingOptions)
    case updateBar(options: RecordingOptions, effective: RecordingOptions)
    case closeBar
    case bubble(BubbleWish?)
    case countdown(Int)
    case closeCountdown
    case prepareRecorder(SessionID, RecorderRequest)
    case beginTake(SessionID)
    case pauseRecorder(SessionID)
    case resumeRecorder(SessionID)
    case stopRecorder(SessionID)
    /// Stops and deletes the .mov; also cancels a recorder still preparing. Idempotent in the shell.
    case cancelRecorder(SessionID)
    case overlays(start: Bool, clicks: Bool, keys: Bool, showAllKeys: Bool)
    case inputMonitor(start: Bool)
    /// The shell builds the header from the stream once the first frame is known (`recording.timeline` on).
    case timeline(TimelineCommand)
    case ticker(start: Bool)
    case statusItem(StatusItemOverride?)
    case confirm(SessionID, ConfirmKind)
    /// Seconds from now.
    case convert(SessionID, URL, deadline: Double)
    case deliver(SessionID, URL, date: Date?, duration: Double)
    case persist(key: String, value: SettingValue)
    case storeLastArea(StoredArea)
    case requestPermission(MediaPermission)
    case notify(RecordingNotice)
    case screenPermissionAlert
    case diskCheck
    case allowQuit
    case log(String)
}

/// The single owner of a recording (V1): a pure reducer, state + event → state + effects (spec §6). The shell
/// executes the effects and turns callbacks into events, nothing else.
public struct RecordingFlow: Sendable {
    public static let confirmAfterSeconds = 10.0
    public static let ticksPerDiskCheck = 10
    public static let countdownStart = 3

    public private(set) var state: RecordingState = .idle
    /// Set by a quit during a recording; `allowQuit` follows once the recording is delivered.
    public private(set) var quitPending = false
    /// The alert on screen, if any.
    public private(set) var confirming: (session: SessionID, kind: ConfirmKind)?
    /// The ● menu's Stop shows this (the current ⇧⌘5 binding). The shell sets it before each event.
    public var stopKey: KeyCombo?

    private var lastSession = 0
    /// Sessions whose recorder was prepared and not yet stopped or cancelled (R3).
    private var liveRecorders: Set<SessionID> = []
    private var progress: Double?

    public init(stopKey: KeyCombo? = nil) {
        self.stopKey = stopKey
    }

    /// The next state's effects, or nil when the event means nothing now (the shell ignores it).
    public mutating func next(_ event: RecordingEvent) -> [RecordingEffect]? {
        if let session = event.session, session != state.session {
            return staleEvent(event, session)
        }
        if case .confirmed(_, let kind) = event, confirming?.kind != kind { return nil }
        if case .declined(_, let kind) = event {
            guard confirming?.kind == kind else { return nil }
            confirming = nil
            return []
        }
        let before = state
        let effects = transition(event)
        if effects != nil, !sameCase(before, state) { confirming = nil }
        return effects
    }

    // MARK: Transitions

    private mutating func transition(_ event: RecordingEvent) -> [RecordingEffect]? {
        switch (state, event) {
        // idle
        case (.idle, .toggle(let permitted, let allows, let lastArea)):
            guard allows else { return [.log("busy: dropped toggle")] }
            guard permitted else { return [.screenPermissionAlert] }
            lastSession += 1
            let s = SessionID(lastSession)
            state = .selecting(s)
            let request = SelectionRequest(
                purpose: .recording, hint: RecordingStrings.selectionHint, clickSelectsDisplay: true,
                windowNeedsDisplayCentre: true, lastArea: lastArea)
            return [.activity(.begin(.recordingSetup)), .selection(request), .log("begin \(s)")]
        case (.idle, .quitRequested):
            return [.allowQuit]

        // selecting
        case (.selecting(let s), .selected(_, let result, let options, let permissions, let devices)):
            let target: RecordingTarget
            var effects: [RecordingEffect] = []
            switch result {
            case .cancelled, .busy:
                state = .idle
                return [.activity(.end(.recordingSetup)), .log("finish \(s)")]
            case .area(let area):
                target = .area(area)
                effects.append(.storeLastArea(area))
            case .display(let display):
                target = .display(display)
            case .window(let window, let display, let frame):
                target = .window(window, display: display, frame: frame)
            }
            state = .configuring(s, target, options, permissions: permissions, devices: devices)
            let effective = effectiveOptions(options, permissions: permissions, devices: devices)
            effects += [.showBorder(target, .dashed), .showBar(options: options, effective: effective)]
            if effective.camera { effects.append(.bubble(wish(effective))) }
            return effects
        case (.selecting(let s), .toggle), (.selecting(let s), .cancel):
            state = .idle
            return [.cancelSelection, .activity(.end(.recordingSetup)), .log("finish \(s)")]
        case (.selecting(let s), .quitRequested):
            state = .idle
            return [.cancelSelection, .activity(.end(.recordingSetup)), .log("finish \(s)"), .allowQuit]

        // configuring
        case (.configuring(let s, let target, let options, let permissions, let devices), .option(_, let change)):
            let updated = options.applying(change)
            state = .configuring(s, target, updated, permissions: permissions, devices: devices)
            let setting = change.setting
            var effects: [RecordingEffect] = [.persist(key: setting.key, value: setting.value)]
            if let permission = permissionToAsk(change, permissions) { effects.append(.requestPermission(permission)) }
            effects += barAndBubble(old: options, new: updated, permissions: permissions, devices: devices)
            return effects
        case (
            .configuring(let s, let target, let options, var permissions, let devices),
            .permissionAnswered(_, let permission, let answer)
        ):
            let old = permissions
            permissions[permission] = answer
            state = .configuring(s, target, options, permissions: permissions, devices: devices)
            return barAndBubble(
                old: options, new: options, oldPermissions: old, permissions: permissions, devices: devices)
        case (.configuring(let s, let target, let options, let permissions, let devices), .record(_, let free)):
            guard DiskGuard.canStart(freeBytes: free) else { return [.notify(RecordingStrings.Notice.diskLow)] }
            let effective = effectiveOptions(options, permissions: permissions, devices: devices)
            state = .countingDown(s, target, effective, remaining: Self.countdownStart, recorderReady: false)
            liveRecorders.insert(s)
            return [
                .closeBar, .countdown(Self.countdownStart),
                .prepareRecorder(s, RecorderRequest(target: target, options: effective)),
            ]
        case (.configuring(let s, let target, let options, let permissions, let devices), .cameraUnavailable):
            let updated = options.applying(.camera(false))
            state = .configuring(s, target, updated, permissions: permissions, devices: devices)
            let effective = effectiveOptions(updated, permissions: permissions, devices: devices)
            return cameraLost(s) + [.updateBar(options: updated, effective: effective)]
        case (.configuring(let s, _, _, _, _), .cancel), (.configuring(let s, _, _, _, _), .toggle),
            (.configuring(let s, _, _, _, _), .targetGone):
            state = .idle
            return teardown(endActivity: .recordingSetup) + [.log("finish \(s)")]
        case (.configuring(let s, _, _, _, _), .quitRequested):
            state = .idle
            return teardown(endActivity: .recordingSetup) + [.log("finish \(s)"), .allowQuit]

        // countingDown
        case (.countingDown(let s, let target, let options, let remaining, let ready), .countdownTick):
            if remaining > 1 {
                state = .countingDown(s, target, options, remaining: remaining - 1, recorderReady: ready)
                return [.countdown(remaining - 1)]
            }
            let ends: [RecordingEffect] = [
                .closeCountdown, .activity(.end(.recordingSetup)), .activity(.begin(.recording)),
            ]
            guard ready else {
                state = .starting(s, target, options)
                return ends
            }
            return ends + goLive(s, target, options)
        case (.countingDown(let s, let target, let options, let remaining, _), .recorderReady):
            state = .countingDown(s, target, options, remaining: remaining, recorderReady: true)
            return []
        case (.countingDown(let s, _, _, _, _), .recorderFailed(_, let failure)):
            return failedToStart(s, failure, endActivity: .recordingSetup)
        case (.countingDown(let s, _, _, _, _), .cancel), (.countingDown(let s, _, _, _, _), .toggle),
            (.countingDown(let s, _, _, _, _), .targetGone):
            return cancelStart(s, endActivity: .recordingSetup)
        case (.countingDown(let s, _, _, _, _), .quitRequested):
            return cancelStart(s, endActivity: .recordingSetup) + [.allowQuit]
        case (.countingDown(let s, let target, var options, let remaining, let ready), .cameraUnavailable):
            options.camera = false
            state = .countingDown(s, target, options, remaining: remaining, recorderReady: ready)
            return cameraLost(s)

        // starting
        case (.starting(let s, let target, let options), .recorderReady):
            return goLive(s, target, options)
        case (.starting(let s, _, _), .recorderFailed(_, let failure)):
            return failedToStart(s, failure, endActivity: .recording)
        case (.starting(let s, _, _), .cancel), (.starting(let s, _, _), .toggle),
            (.starting(let s, _, _), .targetGone):
            return cancelStart(s, endActivity: .recording)
        case (.starting(let s, _, _), .quitRequested):
            return cancelStart(s, endActivity: .recording) + [.allowQuit]
        case (.starting(let s, let target, var options), .cameraUnavailable):
            options.camera = false
            state = .starting(s, target, options)
            return cameraLost(s)

        // recording and paused
        case (.recording(let s, var take), .takeStarted(_, let host, let date)):
            guard take.startedAt == nil else { return nil }
            take.clock.begin(at: host)
            take.startedAt = date
            state = .recording(s, take)
            return [.log("first frame")]
        case (.recording(let s, var take), .pause(_, let host)):
            take.clock.pause(at: host)
            state = .paused(s, take)
            return [.pauseRecorder(s), .statusItem(override(paused: true, take, host)), .log("pause")]
        case (.paused(let s, var take), .resume(_, let host)):
            take.clock.resume(at: host)
            state = .recording(s, take)
            return [.resumeRecorder(s), .statusItem(override(paused: false, take, host)), .log("resume")]
        case (.recording(let s, var take), .tick(_, let host)), (.paused(let s, var take), .tick(_, let host)):
            take.ticks += 1
            let paused = isPaused
            state = paused ? .paused(s, take) : .recording(s, take)
            var effects: [RecordingEffect] = [.statusItem(override(paused: paused, take, host))]
            if take.ticks % Self.ticksPerDiskCheck == 0 { effects.append(.diskCheck) }
            return effects
        case (.recording(let s, let take), .restart(_, let host)), (.paused(let s, let take), .restart(_, let host)):
            if take.elapsed(at: host) > Self.confirmAfterSeconds {
                confirming = (s, .restart)
                return [.confirm(s, .restart)]
            }
            return restart(s, take)
        case (.recording(let s, let take), .discard(_, let host)), (.paused(let s, let take), .discard(_, let host)):
            if take.elapsed(at: host) > Self.confirmAfterSeconds {
                confirming = (s, .discard)
                return [.confirm(s, .discard)]
            }
            return discard(s, take)
        case (.recording(let s, let take), .confirmed(_, let kind)),
            (.paused(let s, let take), .confirmed(_, let kind)):
            confirming = nil
            return kind == .restart ? restart(s, take) : discard(s, take)
        case (.recording(let s, let take), .toggle), (.paused(let s, let take), .toggle):
            return stop(s, take, notice: nil, reason: "user")
        case (.recording(let s, let take), .quitRequested), (.paused(let s, let take), .quitRequested):
            quitPending = true
            return stop(s, take, notice: nil, reason: "quit")
        case (.recording(let s, let take), .recorderFailed(_, let failure)),
            (.paused(let s, let take), .recorderFailed(_, let failure)):
            return stop(
                s, take, notice: RecordingStrings.Notice.stopped(error: failure.text), reason: "failed: \(failure.text)"
            )
        case (.recording(let s, let take), .diskChecked(_, let free)),
            (.paused(let s, let take), .diskChecked(_, let free)):
            guard DiskGuard.mustStop(freeBytes: free) else { return [] }
            return stop(s, take, notice: RecordingStrings.Notice.diskFull, reason: "disk")
        case (.recording(let s, var take), .cameraUnavailable), (.paused(let s, var take), .cameraUnavailable):
            take.options.camera = false
            state = isPaused ? .paused(s, take) : .recording(s, take)
            return cameraLost(s)

        // finishing
        case (.finishing(let s, .stopping, let notice, let startedAt, _), .stopped(_, .movie(let url, let duration))):
            state = .finishing(s, .converting, notice: notice, startedAt: startedAt, duration: duration)
            progress = nil
            return [
                .timeline(.finish),
                .convert(s, url, deadline: DiskGuard.conversionDeadline(duration: duration)),
            ]
        case (.finishing(let s, .stopping, _, _, _), .stopped(_, .noFrames)):
            state = .idle
            return [.timeline(.discard), .notify(RecordingStrings.Notice.nothingRecorded)] + done(s)
        case (.finishing(let s, .converting, _, _, _), .conversionProgress(_, let fraction)):
            progress = min(max(fraction, 0), 1)
            return [.statusItem(finishingOverride)]
        case (
            .finishing(let s, .converting, let notice, let startedAt, let duration), .converted(_, let url, let isMov)
        ):
            state = .finishing(s, .delivering, notice: notice, startedAt: startedAt, duration: duration)
            var effects: [RecordingEffect] = [.deliver(s, url, date: startedAt, duration: duration ?? 0)]
            if isMov { effects.append(.notify(RecordingStrings.Notice.keptMovie)) }
            return effects
        case (.finishing(let s, .delivering, let notice, _, _), .delivered):
            state = .idle
            return (notice.map { [.notify($0)] } ?? []) + done(s)
        case (.finishing, .quitRequested):
            quitPending = true
            return []

        default:
            return nil
        }
    }

    // MARK: Composite steps (spec §6)

    /// *Go live*.
    private mutating func goLive(
        _ s: SessionID, _ target: RecordingTarget, _ options: RecordingOptions
    ) -> [RecordingEffect] {
        let take = Take(target: target, options: options)
        state = .recording(s, take)
        var effects: [RecordingEffect] = [.beginTake(s), .showBorder(target, .recording)]
        if options.clicks || options.keys {
            effects.append(
                .overlays(start: true, clicks: options.clicks, keys: options.keys, showAllKeys: options.showAllKeys))
        }
        effects.append(.inputMonitor(start: true))
        if options.timeline { effects.append(.timeline(.start)) }
        effects += [.ticker(start: true), .statusItem(override(paused: false, take, nil))]
        return effects
    }

    /// *Wind down*.
    private func windDown(_ take: Take, stopping: Bool, keepBubble: Bool = false) -> [RecordingEffect] {
        var effects: [RecordingEffect] = [.ticker(start: false), .inputMonitor(start: false)]
        if take.options.clicks || take.options.keys {
            effects.append(
                .overlays(
                    start: false, clicks: take.options.clicks, keys: take.options.keys,
                    showAllKeys: take.options.showAllKeys))
        }
        if !keepBubble { effects.append(.bubble(nil)) }
        if stopping { effects.append(.statusItem(finishingOverride)) }
        return effects
    }

    /// *Teardown*.
    private func teardown(endActivity: ScreenActivity.Activity) -> [RecordingEffect] {
        [.closeBar, .closeCountdown, .closeBorder, .bubble(nil), .activity(.end(endActivity))]
    }

    /// *Done*.
    private mutating func done(_ s: SessionID) -> [RecordingEffect] {
        var effects: [RecordingEffect] = [.statusItem(nil), .activity(.end(.recording))]
        if quitPending {
            quitPending = false
            effects.append(.allowQuit)
        }
        effects.append(.log("finish \(s)"))
        return effects
    }

    private mutating func cancelRecorder(_ s: SessionID) -> [RecordingEffect] {
        liveRecorders.remove(s) == nil ? [] : [.cancelRecorder(s)]
    }

    private mutating func cancelStart(_ s: SessionID, endActivity: ScreenActivity.Activity) -> [RecordingEffect] {
        state = .idle
        return cancelRecorder(s) + teardown(endActivity: endActivity) + [.log("finish \(s)")]
    }

    private mutating func failedToStart(
        _ s: SessionID, _ failure: RecorderFailure, endActivity: ScreenActivity.Activity
    ) -> [RecordingEffect] {
        let report: RecordingEffect =
            failure == .userDeclined
            ? .screenPermissionAlert : .notify(RecordingStrings.Notice.couldNotStart(error: failure.text))
        return cancelStart(s, endActivity: endActivity).dropLast() + [
            report, .log("failed: \(failure.text)"), .log("finish \(s)"),
        ]
    }

    private mutating func stop(
        _ s: SessionID, _ take: Take, notice: RecordingNotice?, reason: String
    ) -> [RecordingEffect] {
        state = .finishing(s, .stopping, notice: notice, startedAt: take.startedAt, duration: nil)
        progress = nil
        liveRecorders.remove(s)
        return windDown(take, stopping: true) + [.closeBorder, .stopRecorder(s), .log("stop \(reason)")]
    }

    private mutating func restart(_ s: SessionID, _ take: Take) -> [RecordingEffect] {
        lastSession += 1
        let next = SessionID(lastSession)
        state = .countingDown(next, take.target, take.options, remaining: Self.countdownStart, recorderReady: false)
        liveRecorders.insert(next)
        // The bubble stays through the new countdown (it is shown during set-up).
        var effects = windDown(take, stopping: false, keepBubble: take.options.camera) + cancelRecorder(s)
        effects += [
            .timeline(.discard), .statusItem(nil), .showBorder(take.target, .dashed), .activity(.end(.recording)),
            .activity(.begin(.recordingSetup)), .countdown(Self.countdownStart),
            .prepareRecorder(next, RecorderRequest(target: take.target, options: take.options)),
            .log("finish \(s)"), .log("begin \(next)"),
        ]
        return effects
    }

    private mutating func discard(_ s: SessionID, _ take: Take) -> [RecordingEffect] {
        state = .idle
        return windDown(take, stopping: false) + cancelRecorder(s) + [
            .timeline(.discard), .closeBorder, .statusItem(nil), .activity(.end(.recording)), .log("finish \(s)"),
        ]
    }

    private func cameraLost(_ s: SessionID) -> [RecordingEffect] {
        [
            .bubble(nil), .persist(key: RecordingSettings.Key.camera, value: .bool(false)),
            .notify(RecordingStrings.Notice.cameraUnavailable),
        ]
    }

    /// The first time a control that needs a permission is turned on (§5.2): the microphone and camera prompt
    /// only while undetermined; Accessibility whenever it isn't granted.
    private func permissionToAsk(_ change: RecordingOptionChange, _ permissions: RecordingPermissions)
        -> MediaPermission?
    {
        switch change {
        case .mic(true) where permissions.microphone == .notDetermined: .microphone
        case .camera(true) where permissions.camera == .notDetermined: .camera
        case .keys(true) where permissions.accessibility != .granted: .accessibility
        default: nil
        }
    }

    private func barAndBubble(
        old: RecordingOptions, new: RecordingOptions, oldPermissions: RecordingPermissions? = nil,
        permissions: RecordingPermissions, devices: CaptureDeviceList
    ) -> [RecordingEffect] {
        let oldEffective = effectiveOptions(old, permissions: oldPermissions ?? permissions, devices: devices)
        let effective = effectiveOptions(new, permissions: permissions, devices: devices)
        var effects: [RecordingEffect] = [.updateBar(options: new, effective: effective)]
        let oldWish = oldEffective.camera ? wish(oldEffective) : nil
        let newWish = effective.camera ? wish(effective) : nil
        if oldWish != newWish { effects.append(.bubble(newWish)) }
        return effects
    }

    private func wish(_ options: RecordingOptions) -> BubbleWish {
        BubbleWish(cameraDevice: options.cameraDevice, size: options.bubbleSize)
    }

    private var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    // MARK: Stale sessions (R9)

    private mutating func staleEvent(_ event: RecordingEvent, _ session: SessionID) -> [RecordingEffect]? {
        // A recorder that becomes ready for a session that moved on is cancelled (R3), once.
        guard case .recorderReady = event, liveRecorders.contains(session) else { return nil }
        return cancelRecorder(session)
    }

    // MARK: Status item (§5.3)

    private func override(paused: Bool, _ take: Take, _ host: Double?) -> StatusItemOverride {
        let elapsed = MediaTime.text(seconds: host.map { take.elapsed(at: $0) } ?? 0)
        let menu: [StatusItemOverride.Entry] = [
            paused
                ? StatusItemOverride.Entry(id: RecordingMenu.resume, title: RecordingStrings.resume)
                : StatusItemOverride.Entry(id: RecordingMenu.pause, title: RecordingStrings.pause),
            StatusItemOverride.Entry(id: RecordingMenu.stop, title: RecordingStrings.stop, shownKey: stopKey),
            .separator,
            StatusItemOverride.Entry(id: RecordingMenu.restart, title: RecordingStrings.restart),
            StatusItemOverride.Entry(id: RecordingMenu.discard, title: RecordingStrings.discard),
        ]
        return paused
            ? StatusItemOverride(
                badge: .paused(elapsed: elapsed), accessibilityLabel: RecordingStrings.pausedLabel(elapsed: elapsed),
                menu: menu)
            : StatusItemOverride(
                badge: .recording(elapsed: elapsed),
                accessibilityLabel: RecordingStrings.recordingLabel(elapsed: elapsed), menu: menu)
    }

    private var finishingOverride: StatusItemOverride {
        let percent = progress.map { Int(($0 * 100).rounded(.down)) }
        return StatusItemOverride(
            badge: .finishing, accessibilityLabel: RecordingStrings.finishingLabel,
            menu: [
                StatusItemOverride.Entry(
                    id: RecordingMenu.finishing, title: RecordingStrings.finishing(percent: percent), isEnabled: false)
            ])
    }

    private func sameCase(_ a: RecordingState, _ b: RecordingState) -> Bool {
        switch (a, b) {
        case (.recording, .recording), (.paused, .paused): a.session == b.session
        default: false
        }
    }
}

/// The ● menu's entry ids, routed through `ActionRouter.performMenuItem`.
public enum RecordingMenu {
    public static let pause = "recording.pause"
    public static let resume = "recording.resume"
    public static let stop = "recording.stop"
    public static let restart = "recording.restart"
    public static let discard = "recording.discard"
    /// Disabled; shows the progress.
    public static let finishing = "recording.finishing"
}

extension RecorderFailure {
    var text: String {
        switch self {
        case .userDeclined: "Screen Recording was declined"
        case .other(let description): description
        }
    }
}

extension RecordingEvent {
    /// The session an async event belongs to; nil for toggle and quit.
    var session: SessionID? {
        switch self {
        case .toggle, .quitRequested: nil
        case .selected(let s, _, _, _, _), .option(let s, _), .permissionAnswered(let s, _, _), .record(let s, _),
            .cancel(let s), .countdownTick(let s), .recorderReady(let s), .recorderFailed(let s, _),
            .takeStarted(let s, _, _), .pause(let s, _), .resume(let s, _), .restart(let s, _), .discard(let s, _),
            .confirmed(let s, _), .declined(let s, _), .tick(let s, _), .diskChecked(let s, _),
            .cameraUnavailable(let s), .targetGone(let s), .stopped(let s, _), .conversionProgress(let s, _),
            .converted(let s, _, _), .delivered(let s, _):
            s
        }
    }
}
