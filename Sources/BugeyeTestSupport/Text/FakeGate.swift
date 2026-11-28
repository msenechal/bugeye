import Synchronization

/// A latch a test opens to release whatever waits on it (OCR plan P3). Thread-safe.
public final class FakeGate: Sendable {
    private struct State {
        var isOpen = false
        var next: UInt64 = 0
        var waiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// How many callers are suspended in `wait()` right now.
    public var waiting: Int { state.withLock { $0.waiters.count } }

    /// Releases every waiter, and every later `wait()` returns at once.
    public func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    /// Returns once the gate is open. Throws `CancellationError` if the task is cancelled first.
    public func wait() async throws {
        let id: UInt64? = state.withLock { state in
            if state.isOpen { return nil }
            state.next += 1
            return state.next
        }
        guard let id else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Bool? = state.withLock { state in
                    if state.isOpen { return true }
                    if Task.isCancelled { return false }
                    state.waiters[id] = continuation
                    return nil
                }
                switch outcome {
                case true?: continuation.resume()
                case false?: continuation.resume(throwing: CancellationError())
                case nil: break
                }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }
}
