import BugeyeCore
import Synchronization

/// Replays recorded lines and records every call. Thread-safe (OCR §3.3).
public final class FakeTextReader: TextReader, Sendable {
    public enum Step: Sendable {
        case lines([OCRLine])
        /// Throws `FakeFailure(message)`.
        case failure(String)
        /// Suspends until its task is cancelled, then throws `CancellationError`.
        case hang
        /// Suspends until the gate opens, then returns the lines; throws `CancellationError` if cancelled first
        /// (OCR plan P3).
        case gate(FakeGate, [OCRLine])
    }

    private struct State {
        var steps: [Step]
        var calls: [(width: Int, height: Int)] = []
    }

    private let state: Mutex<State>
    private let fallback: Step

    /// Steps are used in call order; once they run out, `fallback` answers.
    public init(steps: [Step] = [], fallback: Step = .lines([])) {
        state = Mutex(State(steps: steps))
        self.fallback = fallback
    }

    /// The Wave 0 initialiser: every call returns `lines`.
    public convenience init(lines: [OCRLine]) {
        self.init(fallback: .lines(lines))
    }

    /// The width and height of each image read, in call order.
    public var calls: [(width: Int, height: Int)] { state.withLock { $0.calls } }

    public func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] {
        let step = state.withLock { state in
            state.calls.append((image.width, image.height))
            return state.steps.isEmpty ? fallback : state.steps.removeFirst()
        }
        switch step {
        case .lines(let lines):
            return lines
        case .failure(let message):
            throw FakeFailure(message)
        case .hang:
            while true { try await Task.sleep(for: .seconds(3600)) }
        case .gate(let gate, let lines):
            try await gate.wait()
            return lines
        }
    }
}
