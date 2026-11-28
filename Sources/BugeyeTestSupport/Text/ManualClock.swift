import Synchronization

/// A clock that moves only when the test advances it (OCR plan P4). Thread-safe.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public init(offset: Duration) { self.offset = offset }

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var next: UInt64 = 0
        var sleepers: [UInt64: Sleeper] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .zero }

    /// How many callers are sleeping right now.
    public var sleepers: Int { state.withLock { $0.sleepers.count } }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    public func advance(by duration: Duration) {
        let woken = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for key in due.keys { state.sleepers[key] = nil }
            return due.values.map(\.continuation)
        }
        for continuation in woken { continuation.resume() }
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id: UInt64? = state.withLock { state in
            if deadline <= state.now { return nil }
            state.next += 1
            return state.next
        }
        guard let id else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Bool? = state.withLock { state in
                    if deadline <= state.now { return true }
                    if Task.isCancelled { return false }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                switch outcome {
                case true?: continuation.resume()
                case false?: continuation.resume(throwing: CancellationError())
                case nil: break
                }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
}
