/// Maps host-clock seconds onto the output timeline with paused spans removed (V6, `design/04` §2.8).
/// The same clock times video samples, audio samples and timeline input.
public struct RecordingClock: Hashable, Sendable {
    private struct Pause: Hashable, Sendable {
        var start: Double
        var end: Double?
    }

    /// Host seconds of the first video frame; nil before it.
    public private(set) var origin: Double?
    private var pauses: [Pause] = []

    public init() {}

    public var isPaused: Bool { pauses.last.map { $0.end == nil } ?? false }

    /// Sets the origin at the first frame. A second call is ignored.
    public mutating func begin(at host: Double) {
        if origin == nil { origin = host }
    }

    /// Ignored before `begin` and while paused.
    public mutating func pause(at host: Double) {
        guard let origin, !isPaused else { return }
        pauses.append(Pause(start: max(host, origin)))
    }

    /// Ignored unless paused. A resume stamped before its pause ends the pause at the pause point.
    public mutating func resume(at host: Double) {
        guard isPaused else { return }
        pauses[pauses.count - 1].end = max(host, pauses[pauses.count - 1].start)
    }

    /// Output seconds for something captured at `host`; nil before the origin and for anything captured
    /// inside a pause, even when it is handled after the resume, so the output never goes backwards.
    public func outputTime(for host: Double) -> Double? {
        guard let origin, host >= origin else { return nil }
        var cut = 0.0
        for pause in pauses {
            if host < pause.start { break }
            guard let end = pause.end, host >= end else { return nil }
            cut += end - pause.start
        }
        return host - origin - cut
    }

    /// Whole milliseconds of output time (rounded down), for the timeline.
    public func milliseconds(for host: Double) -> Int? {
        outputTime(for: host).map { Int(($0 * 1000).rounded(.down)) }
    }

    /// Output seconds recorded by `host`: 0 before the origin, frozen while paused.
    public func elapsed(at host: Double) -> Double {
        guard let origin, host >= origin else { return 0 }
        var cut = 0.0
        for pause in pauses {
            if host < pause.start { break }
            guard let end = pause.end, host >= end else { return pause.start - origin - cut }
            cut += end - pause.start
        }
        return host - origin - cut
    }
}
