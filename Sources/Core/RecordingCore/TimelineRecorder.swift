import BugeyeCore
import Foundation
import Synchronization

/// A key press as the input monitor sees it. `characters` is the key's character with no modifiers applied
/// (`NSEvent.characters(byApplyingModifiers: [])`). Only a `TimelineKey` built from it reaches the file.
public struct KeyPress: Hashable, Sendable {
    public var keyCode: UInt16
    public var characters: String?
    public var modifiers: Set<TimelineModifier>
    public var isRepeat: Bool

    public init(keyCode: UInt16, characters: String?, modifiers: Set<TimelineModifier>, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

/// Input for the timeline, in Quartz global points (top-left of the primary display).
public enum TimelineInput: Hashable, Sendable {
    /// A cursor sample (the shell samples at 30 Hz; the recorder also filters).
    case move(Point2D)
    case down(TimelineButton, Point2D, clicks: Int)
    case up(TimelineButton, Point2D)
    case scroll(Point2D, dx: Double, dy: Double)
    case key(KeyPress)
    /// The shell reports a change of active app or of its frontmost window; never a window title (V14).
    case focus(app: String, name: String, window: WindowID?, frame: Rect2D?)
    /// A followed window moved: the recorded area's new rect.
    case area(Rect2D)
}

public struct TimelineSummary: Hashable, Sendable {
    /// Event lines written (every line but the header and `end`).
    public var events: Int
    /// The file's size.
    public var bytes: Int
    public var truncations: [TimelineTruncation]
    /// A write error that stopped the timeline early, if any.
    public var error: String?
}

/// Records one take's event timeline (spec §7): maps host time to video time with the take's clock, filters and
/// coalesces input, looks up the element under each click, and appends lines off the main actor.
public actor TimelineRecorder {
    public struct Configuration: Sendable {
        public var url: URL
        public var header: TimelineHeader
        public var limits: TimelineLimits
        /// The element lookup's deadline (250 ms).
        public var lookupTimeout: Duration
        /// How often `startFlushing` appends the buffer (1 s).
        public var flushInterval: Duration

        public init(
            url: URL, header: TimelineHeader, limits: TimelineLimits = TimelineLimits(),
            lookupTimeout: Duration = .milliseconds(250), flushInterval: Duration = .seconds(1)
        ) {
            self.url = url
            self.header = header
            self.limits = limits
            self.lookupTimeout = lookupTimeout
            self.flushInterval = flushInterval
        }
    }

    /// Scrolls within this many ms of a group's first are summed into it (P6).
    static let scrollWindowMs = 100
    /// Cursor lines are at least 0.5 pt apart.
    static let minimumMove = 0.5

    private let configuration: Configuration
    private let reader: (any AXReader)?
    private let writer: TimelineWriter
    private var clock = RecordingClock()
    private var areaOrigin: Point2D
    private var lastT = 0
    private var lastMove: (t: Int, at: Point2D)?
    private var nextClickID = 1
    private var openClicks: [TimelineButton: [Int]] = [:]
    private var pendingScroll: (t: Int, at: Point2D, dx: Double, dy: Double)?
    /// The lookup whose line isn't written yet (it ends at the reader's answer or the deadline).
    private var lookup: Task<Void, Never>?
    /// The reader call itself, which may outlive its deadline when the reader ignores cancellation: while it
    /// runs, later clicks are `skipped`, so hung Accessibility calls never pile up (V3).
    private var readerCall: Task<AXElementInfo?, Never>?
    private var flushing: Task<Void, Never>?
    private var isClosed = false
    /// Set when `finish` begins: input is refused from then on.
    private var isFinishing = false

    /// Creates the file and buffers the header. `startedAt` is the first frame's host time.
    public init(_ configuration: Configuration, reader: (any AXReader)?, startedAt host: Double) throws {
        self.configuration = configuration
        self.reader = reader
        var header = configuration.header
        // Without a reader no element line can appear: the header says so.
        header.hasElements = header.hasElements && reader != nil
        writer = try TimelineWriter(url: configuration.url, header: header, limits: configuration.limits)
        areaOrigin = configuration.header.target.area.origin
        clock.begin(at: host)
    }

    private var watchesKeys: Bool { configuration.header.hasKeys }
    private var watchesElements: Bool { configuration.header.hasElements && reader != nil }

    /// Appends the buffer every `flushInterval` until `finish` or `discard`.
    public func startFlushing() {
        guard flushing == nil, !isClosed else { return }
        let interval = configuration.flushInterval
        flushing = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await self.flush()
            }
        }
    }

    public func flush() {
        writePendingScroll()
        writer.flush()
    }

    /// False once `finish` has begun or after `discard`.
    public var acceptsInput: Bool { !isClosed && !isFinishing }

    public func pause(at host: Double) {
        guard acceptsInput, !clock.isPaused else { return }
        writePendingScroll()
        // A press open across the pause can't be paired: its release is in the cut.
        openClicks = [:]
        clock.pause(at: host)
        write(.pause, t: milliseconds(clock.elapsed(at: host)))
    }

    public func resume(at host: Double) {
        guard acceptsInput, clock.isPaused else { return }
        clock.resume(at: host)
        write(.resume, t: milliseconds(clock.elapsed(at: host)))
    }

    public func record(_ input: TimelineInput, at host: Double) {
        guard acceptsInput, let ms = clock.milliseconds(for: host) else { return }
        let t = max(ms, lastT)
        switch input {
        case .move(let point):
            let relative = relativeTo(point)
            if let last = lastMove {
                // Three quarters of the sampling period, so a sampler's jitter doesn't drop samples.
                let minimumGap = 750 / max(configuration.header.cursorHz, 1)
                let dx = relative.x - last.at.x
                let dy = relative.y - last.at.y
                guard t - last.t >= minimumGap, (dx * dx + dy * dy).squareRoot() >= Self.minimumMove else { return }
            }
            writePendingScroll()
            lastMove = (t, relative)
            write(.move(relative), t: t)
        case .down(let button, let point, let clicks):
            writePendingScroll()
            let id = nextClickID
            nextClickID += 1
            openClicks[button, default: []].append(id)
            write(.down(id: id, button: button, at: relativeTo(point), clicks: clicks), t: t)
            if watchesElements { lookUpElement(click: id, at: point, t: t) }
        case .up(let button, let point):
            guard let id = openClicks[button]?.popLast() else { return }
            writePendingScroll()
            write(.up(id: id, button: button, at: relativeTo(point)), t: t)
        case .scroll(let point, let dx, let dy):
            let relative = relativeTo(point)
            if let pending = pendingScroll, t - pending.t <= Self.scrollWindowMs {
                pendingScroll = (pending.t, relative, pending.dx + dx, pending.dy + dy)
            } else {
                writePendingScroll()
                pendingScroll = (t, relative, dx, dy)
                lastT = t
            }
        case .key(let press):
            guard watchesKeys, !press.isRepeat,
                let base = KeystrokeFormatter.baseKey(keyCode: press.keyCode, characters: press.characters),
                let key = TimelineKey(key: base, modifiers: press.modifiers)
            else { return }
            writePendingScroll()
            write(.key(key), t: t)
        case .focus(let app, let name, let window, let frame):
            writePendingScroll()
            write(.focus(app: app, name: name, window: window, frame: frame), t: t)
        case .area(let rect):
            writePendingScroll()
            areaOrigin = rect.origin
            write(.area(rect), t: t)
        }
    }

    /// Returns once the in-flight element lookup, if any, has written its line (at most the lookup timeout).
    public func waitForLookup() async {
        while let lookup { await lookup.value }
    }

    /// Writes the in-flight element line, `end`, flushes and fsyncs. Later calls do nothing.
    public func finish(at host: Double) async -> TimelineSummary {
        if !isClosed, !isFinishing {
            isFinishing = true
            writePendingScroll()
            await waitForLookup()
            close()
            writer.finish(t: milliseconds(clock.elapsed(at: host)))
        }
        return summary
    }

    /// Stops and deletes the file (Restart, Discard, nothing recorded).
    public func discard() async {
        close()
        lookup?.cancel()
        readerCall?.cancel()
        writer.discard()
    }

    private var summary: TimelineSummary {
        TimelineSummary(
            events: writer.events, bytes: writer.bytes, truncations: writer.truncations, error: writer.error)
    }

    private func close() {
        isClosed = true
        flushing?.cancel()
        flushing = nil
    }

    private func milliseconds(_ seconds: Double) -> Int {
        max(RecordingClock.milliseconds(seconds), lastT)
    }

    private func relativeTo(_ point: Point2D) -> Point2D {
        Point2D(x: point.x - areaOrigin.x, y: point.y - areaOrigin.y)
    }

    private func write(_ event: TimelineEvent, t: Int) {
        lastT = max(lastT, t)
        writer.append(TimelineLine(t: t, event: event))
    }

    private func writePendingScroll() {
        guard let scroll = pendingScroll else { return }
        pendingScroll = nil
        writer.append(TimelineLine(t: scroll.t, event: .scroll(at: scroll.at, dx: scroll.dx, dy: scroll.dy)))
    }

    // MARK: Element lookups (V3: one in flight, 250 ms, off the main actor)

    private enum LookupOutcome: Sendable {
        case found(AXElementInfo?)
        case timedOut
    }

    private func lookUpElement(click: Int, at point: Point2D, t: Int) {
        guard let reader, lookup == nil, readerCall == nil else {
            writer.append(TimelineLine(t: t, event: .elementStatus(click: click, .skipped)))
            return
        }
        let call = Task<AXElementInfo?, Never> { try? await reader.element(at: point) }
        readerCall = call
        Task {
            _ = await call.value
            self.readerCallEnded(call)
        }
        let timeout = configuration.lookupTimeout
        let origin = areaOrigin
        lookup = Task {
            let outcome = await Self.race(call, timeout)
            self.lookupFinished(click: click, t: t, origin: origin, outcome: outcome)
        }
    }

    private func readerCallEnded(_ call: Task<AXElementInfo?, Never>) {
        if readerCall == call { readerCall = nil }
    }

    private func lookupFinished(click: Int, t: Int, origin: Point2D, outcome: LookupOutcome) {
        lookup = nil
        guard writer.isOpen else { return }
        let event: TimelineEvent
        switch outcome {
        case .timedOut:
            event = .elementStatus(click: click, .timeout)
        case .found(nil):
            event = .elementStatus(click: click, .none)
        case .found(let info?):
            if let element = TimelineElement(info: info, origin: origin) {
                event = .element(click: click, element)
            } else {
                event = .elementStatus(click: click, .withheld)
            }
        }
        writer.append(TimelineLine(t: t, event: event))
    }

    /// The reader's answer against the deadline. Doesn't wait for a reader that ignores cancellation; the
    /// deadline cancels the call, and an answer cancels the timer.
    private static func race(_ call: Task<AXElementInfo?, Never>, _ timeout: Duration) async -> LookupOutcome {
        let once = Once<LookupOutcome>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                call.cancel()
                once.resume(.timedOut)
            }
            Task {
                let info = await call.value
                timer.cancel()
                once.resume(.found(info))
            }
        }
    }
}

/// Resumes a continuation with the first value only.
private final class Once<Value: Sendable>: Sendable {
    private let state = Mutex<(CheckedContinuation<Value, Never>?, Value?)>((nil, nil))

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        let early = state.withLock { state -> Value? in
            if let value = state.1 { return value }
            state.0 = continuation
            return nil
        }
        if let early { continuation.resume(returning: early) }
    }

    func resume(_ value: Value) {
        let continuation = state.withLock { state -> CheckedContinuation<Value, Never>? in
            guard state.1 == nil else { return nil }
            state.1 = value
            defer { state.0 = nil }
            return state.0
        }
        continuation?.resume(returning: value)
    }
}
