/// The one "capture changed" channel (design/02 §5.9). Main actor, synchronous, deterministic.
///
/// Publishers in Wave 1 (contracts K31): `created` by Capture, Recording, Quick Access (the Save As… copy) and
/// the Editor (a gone-file Save As…); `saved` and `deleted` by Quick Access; `moved`, `edited`, `editingStarted`
/// and `editingEnded` by the Editor. Every module may subscribe to any of them.
@MainActor
public final class CaptureEventBus {
    private struct Entry {
        /// Weak, so dropping the subscription stops delivery (plan P6).
        weak var subscription: CaptureSubscription?
        let handler: @MainActor (CaptureEvent) -> Void
    }

    private var entries: [Entry] = []
    private var queue: [CaptureEvent] = []
    private var delivering = false
    private var items: [CaptureID: CaptureItem] = [:]

    public init() {}

    /// Handlers run in subscription order. An event published from inside a handler is queued and
    /// delivered after the current one has reached every subscriber, so all subscribers see one order.
    public func subscribe(_ handler: @escaping @MainActor (CaptureEvent) -> Void) -> CaptureSubscription {
        let subscription = CaptureSubscription()
        entries.append(Entry(subscription: subscription, handler: handler))
        return subscription
    }

    public func publish(_ event: CaptureEvent) {
        queue.append(event)
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            remember(next)
            entries.removeAll { $0.subscription?.isActive != true }
            for entry in entries where entry.subscription?.isActive == true {
                entry.handler(next)
            }
        }
    }

    /// The latest item for a capture after every event so far; nil if never created, or deleted.
    public func item(_ id: CaptureID) -> CaptureItem? {
        items[id]
    }

    /// `created` always stores; `saved`, `moved` and `edited` update a known capture only (plan P5).
    private func remember(_ event: CaptureEvent) {
        let id = event.item.id
        switch event.change {
        case .created:
            items[id] = event.item
        case .saved, .moved, .edited:
            if items[id] != nil { items[id] = event.item }
        case .deleted:
            items[id] = nil
        default:
            break
        }
    }
}

@MainActor
public final class CaptureSubscription {
    fileprivate var isActive = true

    fileprivate init() {}

    /// Stops delivery. Dropping the subscription also cancels it.
    public func cancel() {
        isActive = false
    }
}
