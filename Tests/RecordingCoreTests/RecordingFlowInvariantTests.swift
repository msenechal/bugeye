import BugeyeCore
import BugeyeFeatures
import Foundation
import RecordingCore
import Testing

/// Invariants R1–R9 of spec §6, checked after every event of random sequences.
@Suite struct RecordingFlowInvariantTests {
    /// What the effects so far have opened, as the shell would see it.
    struct World {
        var activities: Set<ScreenActivity.Activity> = []
        var prepared: Set<SessionID> = []
        var ended: Set<SessionID> = []
        var cancelled: Set<SessionID> = []
        var stopped: Set<SessionID> = []
        /// Sessions whose take's timeline was discarded: never delivered (R6).
        var discardedTakes: Set<SessionID> = []
        var lastElapsed: (session: SessionID, seconds: Int, paused: Bool)?
        var bar = false
        var countdown = false
        var border = false
        var bubble = false
        var overlays = false
        var inputMonitor = false
        var timeline = false
        var statusItem = false
        var quitAsked = false
        var permissions = RecordingPermissions()
        var devices = CaptureDeviceList()
        var violations: [String] = []

        mutating func fail(_ text: String) { violations.append(text) }

        mutating func apply(_ effects: [RecordingEffect]) {
            for effect in effects {
                switch effect {
                case .activity(.begin(let a)):
                    if !activities.insert(a).inserted { fail("R2 begin \(a) twice") }
                case .activity(.end(let a)):
                    if activities.remove(a) == nil { fail("R2 end \(a) not held") }
                case .prepareRecorder(let s, let request):
                    if !prepared.insert(s).inserted { fail("R3 prepare \(s) twice") }
                    if !(prepared.subtracting(ended).count <= 1) { fail("R3 two live recorders") }
                    // R8: the request's options are already effective.
                    let again = effectiveOptions(request.options, permissions: permissions, devices: devices)
                    if again != request.options { fail("R8 raw options in prepareRecorder") }
                case .stopRecorder(let s):
                    if !prepared.contains(s) { fail("R3 stop of unprepared \(s)") }
                    if cancelled.contains(s) || !stopped.insert(s).inserted { fail("R3 \(s) stopped after an end") }
                    ended.insert(s)
                case .cancelRecorder(let s):
                    // A repeated cancel is allowed (a late ready, idempotent in the shell); a cancel after a stop isn't.
                    if !prepared.contains(s) { fail("R3 cancel of unprepared \(s)") }
                    if stopped.contains(s) { fail("R3 \(s) cancelled after its stop") }
                    cancelled.insert(s)
                    ended.insert(s)
                case .deliver(let s, _, _, _):
                    if discardedTakes.contains(s) { fail("R6 a discarded take delivered") }
                case .showBar: bar = true
                case .closeBar: bar = false
                case .countdown: countdown = true
                case .closeCountdown: countdown = false
                case .showBorder: border = true
                case .closeBorder: border = false
                case .bubble(let wish): bubble = wish != nil
                case .overlays(let start, _, _, _): overlays = start
                case .inputMonitor(let start): inputMonitor = start
                case .timeline(.start):
                    if timeline { fail("R6 start twice") }
                    timeline = true
                case .timeline(.finish):
                    if !timeline { fail("R6 finish without start") }
                    timeline = false
                case .timeline(.discard):
                    if !timeline { fail("R6 discard without start") }
                    timeline = false
                    if let s = currentSession { discardedTakes.insert(s) }
                case .statusItem(let item):
                    statusItem = item != nil
                    checkTimer(item)
                case .allowQuit:
                    if !quitAsked { fail("R7 allowQuit without a quit") }
                    quitAsked = false
                default: break
                }
            }
        }

        /// The session the effects being applied belong to (set by the feeder before `apply`).
        var currentSession: SessionID?

        /// The ● timer never runs backwards in a take, and never moves while paused (catches a lost clock).
        mutating func checkTimer(_ item: StatusItemOverride?) {
            guard let item, let session = currentSession else { return }
            let text: String
            let paused: Bool
            switch item.badge {
            case .recording(let e):
                text = e
                paused = false
            case .paused(let e):
                text = e
                paused = true
            case .finishing: return
            }
            let parts = text.split(separator: ":").compactMap { Int($0) }
            let seconds = parts.reduce(0) { $0 * 60 + $1 }
            if let last = lastElapsed, last.session == session {
                if seconds < last.seconds { fail("timer ran backwards \(last.seconds) → \(seconds)") }
                if last.paused, paused, seconds != last.seconds { fail("timer moved while paused") }
            }
            lastElapsed = (session, seconds, paused)
        }

        mutating func check(_ flow: RecordingFlow, after effects: [RecordingEffect]) {
            let state = flow.state
            let setup: Bool
            let recording: Bool
            var configuring = false
            var counting = false
            var finishing = false
            switch state {
            case .idle:
                setup = false
                recording = false
            case .selecting:
                setup = true
                recording = false
            case .configuring:
                setup = true
                recording = false
                configuring = true
            case .countingDown:
                setup = true
                recording = false
                counting = true
            case .starting, .recording, .paused:
                setup = false
                recording = true
            case .finishing:
                setup = false
                recording = true
                finishing = true
            }
            if activities.contains(.recordingSetup) != setup { fail("R2 recordingSetup in \(state)") }
            if activities.contains(.recording) != recording { fail("R2 recording in \(state)") }
            if bar != configuring { fail("R4 bar in \(state)") }
            if countdown != counting { fail("R4 countdown in \(state)") }
            let borderExpected: Bool =
                switch state {
                case .configuring, .countingDown, .starting, .recording, .paused: true
                default: false
                }
            if border != borderExpected { fail("R4 border in \(state)") }
            if (finishing || state == .idle) && (overlays || bubble || inputMonitor) {
                fail("R4 overlay, bubble or monitor open in \(state)")
            }
            if bubble && !borderExpected { fail("R4 bubble in \(state)") }
            if statusItem != (recording && !isStarting(state)) { fail("R5 override in \(state)") }
            if state == .idle {
                if timeline { fail("R6 timeline open at idle") }
                if !prepared.subtracting(ended).isEmpty { fail("R3 live recorder at idle") }
                if quitAsked { fail("R7 quit not allowed at idle") }
            }
            if finishing, effects.contains(.allowQuit) { fail("R7 allowQuit while finishing") }
        }

        func isStarting(_ state: RecordingState) -> Bool {
            if case .starting = state { return true }
            return false
        }
    }

    static let options: [RecordingOptions] = [
        RecordingOptions(),
        RecordingOptions(mic: true, systemAudio: true, clicks: true, keys: true, camera: true, micDevice: "gone"),
        RecordingOptions(clicks: true, camera: true, cameraDevice: "cam", timeline: false),
    ]
    static let permissionSets: [RecordingPermissions] = [
        RecordingPermissions(),
        RecordingPermissions(microphone: .granted, camera: .granted, accessibility: .granted),
        RecordingPermissions(microphone: .denied, camera: .granted, accessibility: .denied),
    ]
    static let deviceSets: [CaptureDeviceList] = [
        CaptureDeviceList(), CaptureDeviceList(microphones: ["mic"], cameras: ["cam"]),
    ]

    /// One random event, mostly for the current session.
    static func randomEvent(
        _ flow: RecordingFlow, _ random: inout SplitMix64, host: inout Double
    ) -> RecordingEvent {
        func pick<T>(_ items: [T]) -> T { items[Int(random.next() % UInt64(items.count))] }
        host += Double(random.next() % 1500) / 100
        let current = flow.state.session ?? SessionID(1)
        let s: SessionID =
            random.next() % 6 == 0 ? SessionID(current.rawValue + pick([-2, -1, 1])) : current
        let results: [SelectionResult] = [
            .area(FlowTesting.area), .display(DisplayID(1)),
            .window(WindowID(3), display: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 300, height: 200)),
            .cancelled, .busy,
        ]
        let changes: [RecordingOptionChange] = [
            .mic(true), .mic(false), .camera(true), .camera(false), .keys(true), .clicks(true),
            .bubbleSize(.large), .cameraDevice("cam"), .fps(60),
        ]
        let events: [RecordingEvent] = [
            .toggle(screenPermitted: random.next() % 5 != 0, activityAllows: random.next() % 5 != 0, lastArea: nil),
            .selected(
                s, pick(results), options: pick(options), permissions: pick(permissionSets), devices: pick(deviceSets)),
            .option(s, pick(changes)),
            .permissionAnswered(s, pick(MediaPermission.allCases), pick([.granted, .denied])),
            .record(s, freeBytes: pick([500_000_000, 50_000_000_000])),
            .cancel(s), .countdownTick(s), .countdownTick(s), .recorderReady(s),
            .recorderFailed(s, pick([.userDeclined, .other("x")])),
            .takeStarted(s, hostTime: host, date: Date(timeIntervalSince1970: host)),
            .pause(s, hostNow: host), .resume(s, hostNow: host), .restart(s, hostNow: host),
            .discard(s, hostNow: host), .confirmed(s, pick([.restart, .discard])),
            .declined(s, pick([.restart, .discard])), .tick(s, hostNow: host),
            .diskChecked(s, freeBytes: pick([100_000_000, 50_000_000_000])), .cameraUnavailable(s), .targetGone(s),
            .stopped(s, pick([.movie(FlowTesting.movie, duration: 3), .noFrames])), .conversionProgress(s, 0.5),
            .converted(s, FlowTesting.movie, isMov: random.next() % 2 == 0), .delivered(s, nil), .quitRequested,
        ]
        // More than half the time, the event that moves the flow forward, so runs reach every state.
        if random.next() % 20 < 11, let forward = forwardEvent(flow, host: host, pick: pick) { return forward }
        return pick(events)
    }

    static func forwardEvent(
        _ flow: RecordingFlow, host: Double, pick: ([RecordingEvent]) -> RecordingEvent
    ) -> RecordingEvent? {
        switch flow.state {
        case .idle: return .toggle(screenPermitted: true, activityAllows: true, lastArea: nil)
        case .selecting(let s):
            return .selected(
                s, .area(FlowTesting.area), options: options[1], permissions: permissionSets[1], devices: deviceSets[1])
        case .configuring(let s, _, _, _, _): return .record(s, freeBytes: 50_000_000_000)
        case .countingDown(let s, _, _, _, _): return pick([.countdownTick(s), .recorderReady(s)])
        case .starting(let s, _, _): return .recorderReady(s)
        case .recording(let s, _):
            return pick([
                .takeStarted(s, hostTime: host, date: Date(timeIntervalSince1970: host)), .tick(s, hostNow: host),
                .pause(s, hostNow: host),
                .toggle(screenPermitted: true, activityAllows: true, lastArea: nil),
            ])
        case .paused(let s, _): return pick([.resume(s, hostNow: host), .tick(s, hostNow: host)])
        case .finishing: return drainEvent(flow)
        }
    }

    /// The event that moves `flow` toward idle, through failure paths when `failing`.
    static func drainEvent(_ flow: RecordingFlow, failing: Bool = false) -> RecordingEvent? {
        if failing {
            switch flow.state {
            case .countingDown(let s, _, _, _, _), .starting(let s, _, _): return .recorderFailed(s, .other("x"))
            case .recording(let s, _), .paused(let s, _): return .diskChecked(s, freeBytes: 1)
            case .finishing(let s, .stopping, _, _, _): return .stopped(s, .noFrames)
            default: break
            }
        }
        return switch flow.state {
        case .idle: nil
        case .selecting(let s):
            .selected(
                s, .cancelled, options: RecordingOptions(), permissions: RecordingPermissions(),
                devices: CaptureDeviceList())
        case .configuring(let s, _, _, _, _), .countingDown(let s, _, _, _, _), .starting(let s, _, _): .cancel(s)
        case .recording, .paused: .toggle(screenPermitted: true, activityAllows: true, lastArea: nil)
        case .finishing(let s, .stopping, _, _, _): .stopped(s, .movie(FlowTesting.movie, duration: 2))
        case .finishing(let s, .converting, _, _, _): .converted(s, FlowTesting.movie, isMov: false)
        case .finishing(let s, .delivering, _, _, _): .delivered(s, nil)
        }
    }

    @Test(arguments: 0..<60)
    func randomSequencesKeepEveryInvariant(seed: Int) {
        var random = SplitMix64(seed: UInt64(seed) &+ 0xF10)
        var flow = RecordingFlow()
        var world = World()
        var host = 100.0
        var leftIdle = 0
        var returnedToIdle = 0
        func feed(_ event: RecordingEvent) {
            let stale = event.session.map { $0 != flow.state.session } ?? false
            let wasIdle = flow.state == .idle
            if case .quitRequested = event { world.quitAsked = true }
            if case .selected(_, _, _, let permissions, let devices) = event, !stale, case .selecting = flow.state {
                world.permissions = permissions
                world.devices = devices
            }
            if case .permissionAnswered(_, let permission, let answer) = event, !stale,
                case .configuring = flow.state
            {
                world.permissions[permission] = answer
            }
            world.currentSession = flow.state.session
            let effects = flow.next(event)
            if stale, let effects {
                // R9: nothing but R3's cancel.
                if !effects.allSatisfy({ if case .cancelRecorder = $0 { true } else { false } }) {
                    world.fail("R9 stale \(event) gave \(effects)")
                }
            }
            if case .quitRequested = event, effects == nil { world.fail("quit not taken") }
            world.apply(effects ?? [])
            world.check(flow, after: effects ?? [])
            if wasIdle, flow.state != .idle { leftIdle += 1 }
            if !wasIdle, flow.state == .idle { returnedToIdle += 1 }
        }
        for _ in 0..<400 { feed(Self.randomEvent(flow, &random, host: &host)) }
        var guardCount = 0
        let failing = seed % 2 == 1
        while let event = Self.drainEvent(flow, failing: failing), guardCount < 20 {
            feed(event)
            guardCount += 1
        }
        #expect(flow.state == .idle)
        // R1: every attempt that left idle came back to it, exactly once.
        #expect(leftIdle == returnedToIdle)
        #expect(world.violations.isEmpty, "\(world.violations.prefix(5))")
    }

    @Test func randomSequencesReachEveryState() {
        var reached: Set<String> = []
        for seed in 0..<60 {
            var random = SplitMix64(seed: UInt64(seed) &+ 0xF10)
            var flow = RecordingFlow()
            var host = 100.0
            for _ in 0..<400 {
                _ = flow.next(Self.randomEvent(flow, &random, host: &host))
                reached.insert(String(describing: flow.state).components(separatedBy: "(").first ?? "")
            }
        }
        #expect(
            reached.isSuperset(of: [
                "idle", "selecting", "configuring", "countingDown", "starting", "recording", "paused", "finishing",
            ]))
    }
}
