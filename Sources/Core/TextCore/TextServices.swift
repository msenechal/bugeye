import BugeyeCore

/// What OCR's wiring hands the shell (contracts §4.5, OCR §5.4): the per-capture store, fed from the bus.
@MainActor
public final class TextServices {
    /// The per-capture text maps. Nil only for the contract's stub, until the wiring PR (plan P10).
    public let maps: CaptureTextMaps?
    private var subscription: CaptureSubscription?
    private var drain: Task<Void, Never>?

    /// The contract's stub: no store, no subscription.
    public init() {
        maps = nil
    }

    /// Subscribes to `bus` on the main actor and forwards each event into one stream, which a single task drains
    /// into `maps.handle`, so events reach the store in bus order. The handler only yields.
    public init(maps: CaptureTextMaps, bus: CaptureEventBus) {
        self.maps = maps
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        subscription = bus.subscribe { continuation.yield($0) }
        drain = Task.detached {
            for await event in stream { await maps.handle(event) }
        }
    }

    isolated deinit {
        subscription?.cancel()
        drain?.cancel()
    }
}
