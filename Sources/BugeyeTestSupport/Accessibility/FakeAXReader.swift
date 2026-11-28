import BugeyeCore
import Synchronization

/// An Accessibility tree given by the test: the element at a point is the last one containing it.
/// `delay` sleeps before each point lookup (cancellable); `gate` holds each point lookup until the test opens it.
public struct FakeAXReader: AXReader {
    /// Holds lookups until `open()`. Counts the lookups that reached it.
    public final class Gate: Sendable {
        private struct State {
            var isOpen = false
            var entered = 0
            var waiters: [CheckedContinuation<Void, Never>] = []
        }
        private let state = Mutex(State())

        public init() {}

        public var entered: Int { state.withLock { $0.entered } }

        public func open() {
            let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.isOpen = true
                defer { state.waiters = [] }
                return state.waiters
            }
            for waiter in waiters { waiter.resume() }
        }

        /// Returns once `count` lookups have reached the gate, or after `limit` so a regression fails its test
        /// instead of hanging the suite. Polls; for tests only.
        public func waitUntilEntered(count: Int, limit: Duration = .seconds(5)) async {
            let deadline = ContinuousClock.now + limit
            while entered < count, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        }

        func pass() async {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state -> Bool in
                    state.entered += 1
                    if state.isOpen { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
    }

    public var elementsByProcess: [Int32: [AXElementInfo]]
    public var delay: Duration
    public var gate: Gate?

    public init(elementsByProcess: [Int32: [AXElementInfo]] = [:], delay: Duration = .zero, gate: Gate? = nil) {
        self.elementsByProcess = elementsByProcess
        self.delay = delay
        self.gate = gate
    }

    public func element(at point: Point2D) async throws -> AXElementInfo? {
        if let gate { await gate.pass() }
        if delay > .zero { try await Task.sleep(for: delay) }
        return elementsByProcess.values.flatMap { $0 }.last { $0.frame.contains(point) }
    }

    public func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo] {
        elementsByProcess[processID] ?? []
    }
}
