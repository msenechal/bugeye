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
        #expect(!h.reads.contains(1))
        _ = services
    }
}
