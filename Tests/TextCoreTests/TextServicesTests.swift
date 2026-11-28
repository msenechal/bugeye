import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@testable import TextCore

@MainActor @Suite struct TextServicesTests {
    @Test func theContractStubHasNoStore() {
        #expect(TextServices().maps == nil)
    }

    @Test func busEventsReachTheStoreInOrder() async throws {
        let h = StoreHarness()
        let bus = CaptureEventBus()
        let services = TextServices(maps: h.store, bus: bus)
        #expect(services.maps === h.store)
        let a = try h.capture(width: 1)
        bus.publish(CaptureEvent(change: .created, item: a, origin: "capture"))
        let store = h.store
        #expect(await eventually { await store.cached(a.id) != nil })
        // created then deleted, in bus order: the map is evicted, never re-added.
        bus.publish(CaptureEvent(change: .deleted, item: a, origin: "quickAccess"))
        #expect(await eventually { await store.cached(a.id) == nil })
        #expect(h.reads == [1])
    }

    @Test func eventsPublishedBackToBackKeepTheirOrder() async throws {
        // a is created then deleted at once: in bus order it ends evicted with no stored read; reversed, `created`
        // would come last and a would be read and cached. (Whether a's read started before the delete is a race, so
        // the test checks the outcome, not the reader's calls.)
        let h = StoreHarness()
        let bus = CaptureEventBus()
        let services = TextServices(maps: h.store, bus: bus)
        let a = try h.capture(width: 1)
        bus.publish(CaptureEvent(change: .created, item: a, origin: "capture"))
        bus.publish(CaptureEvent(change: .deleted, item: a, origin: "quickAccess"))
        let b = try h.capture(width: 2)
        bus.publish(CaptureEvent(change: .created, item: b, origin: "capture"))
        let store = h.store
        #expect(await eventually { await store.cached(b.id) != nil })
        #expect(await store.cached(a.id) == nil)
        #expect(!h.logs.contains { if case .read(a.id, _, _, _, _, _, _, _) = $0 { true } else { false } })
        _ = services
    }

    @Test func droppedServicesStopForwardingEvents() async throws {
        let h = StoreHarness()
        let bus = CaptureEventBus()
        var services: TextServices? = TextServices(maps: h.store, bus: bus)
        _ = services
        services = nil
        bus.publish(CaptureEvent(change: .created, item: try h.capture(width: 1), origin: "capture"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.reads.isEmpty)
    }
}
