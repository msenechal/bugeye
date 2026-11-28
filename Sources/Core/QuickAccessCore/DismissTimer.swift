/// A thumbnail's auto-dismiss countdown (`design/02` §2.12). Times are monotonic seconds (plan P2). A nil duration
/// never expires (Auto-dismiss Never).
public struct DismissTimer: Hashable, Sendable {
    /// Seconds left when the timer last stopped or (re)started; nil never expires.
    public private(set) var remaining: Double?
    /// When it last started running; nil while paused.
    public private(set) var runningSince: Double?

    /// A running timer.
    public init(duration: Double?, startedAt now: Double) {
        remaining = duration
        runningSince = now
    }

    public var isRunning: Bool { runningSince != nil }

    /// Banks the time elapsed since it started running. No-op while paused.
    public mutating func pause(at now: Double) {
        guard let since = runningSince else { return }
        if let left = remaining { remaining = left - max(0, now - since) }
        runningSince = nil
    }

    /// No-op while running.
    public mutating func resume(at now: Double) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    /// The full `duration` again, running.
    public mutating func restart(duration: Double?, at now: Double) {
        remaining = duration
        runningSince = now
    }

    public func isExpired(at now: Double) -> Bool {
        guard let left = remaining else { return false }
        guard let since = runningSince else { return left <= 0 }
        return now - since >= left
    }
}
