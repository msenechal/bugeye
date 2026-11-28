import BugeyeCore
import Synchronization

/// Records every event published on a bus, in order.
@MainActor
public final class CaptureEventRecorder {
    public private(set) var events: [CaptureEvent] = []
    private var subscription: CaptureSubscription?

    public init(_ bus: CaptureEventBus) {
        subscription = bus.subscribe { [weak self] in self?.events.append($0) }
    }

    public var changes: [CaptureChange] { events.map(\.change) }
}

/// Records every notification posted. Thread-safe.
public final class FakeNotifier: Notifier {
    public struct Post: Hashable, Sendable {
        public let title: String
        public let body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    private let state = Mutex<[Post]>([])
    public init() {}
    public var posts: [Post] { state.withLock { $0 } }
    public func post(title: String, body: String) { state.withLock { $0.append(Post(title: title, body: body)) } }
}

/// A Screen Recording permission the test sets, counting the requests.
public final class FakeScreenCapturePermission: ScreenCapturePermission {
    private let state: Mutex<(granted: Bool, requests: Int)>

    public init(granted: Bool) {
        state = Mutex((granted, 0))
    }

    public var granted: Bool {
        get { state.withLock { $0.granted } }
        set { state.withLock { $0.granted = newValue } }
    }

    public var requestCount: Int { state.withLock { $0.requests } }

    public func preflight() -> Bool { granted }
    public func requestAccess() { state.withLock { $0.requests += 1 } }
}

/// Answers the given results in order, then `.cancelled`; records requests and cancels.
@MainActor
public final class FakeAreaSelector: AreaSelector {
    private var results: [SelectionResult]
    public private(set) var requests: [SelectionRequest] = []
    public private(set) var cancels: [SelectionPurpose] = []

    public init(results: [SelectionResult]) {
        self.results = results
    }

    public func select(_ request: SelectionRequest) async -> SelectionResult {
        requests.append(request)
        return results.isEmpty ? .cancelled : results.removeFirst()
    }

    public func cancel(_ purpose: SelectionPurpose) {
        cancels.append(purpose)
    }
}

/// Width = 0.6 × size × characters, ascent = 0.8 × size, descent = 0.2 × size.
public struct FakeTextMeasurer: TextMeasuring {
    public init() {}
    public func measure(_ line: String, font: FontDescriptor) -> TextLineMetrics {
        TextLineMetrics(width: 0.6 * font.size * Double(line.count), ascent: 0.8 * font.size, descent: 0.2 * font.size)
    }
}
