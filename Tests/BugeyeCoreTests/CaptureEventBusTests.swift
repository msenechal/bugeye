import BugeyeCore
import Foundation
import Testing

@MainActor @Suite struct CaptureEventBusTests {
    let id = CaptureID()

    func item(_ id: CaptureID, _ path: String = "/tmp/a.png", saved: Bool = false) -> CaptureItem {
        CaptureItem(
            id: id, fileURL: URL(fileURLWithPath: path), isSaved: saved, kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 0), pixelsPerPoint: 2)
    }

    func event(_ change: CaptureChange, _ item: CaptureItem) -> CaptureEvent {
        CaptureEvent(change: change, item: item, origin: "capture")
    }

    @Test func kindsHaveTheirPrefixesAndExtensions() {
        #expect(CaptureKind.allCases.map(\.namePrefix) == ["Screenshot", "Recording", "Recording", "Collection"])
        #expect(CaptureKind.allCases.map(\.fileExtension) == ["png", "mp4", "gif", "bugeye"])
        #expect(CaptureEvent.previewMaxWidth == 480)
    }

    @Test func changesHaveStableRawValues() {
        let all: [CaptureChange] = [.created, .saved, .moved, .edited, .deleted, .editingStarted, .editingEnded]
        #expect(
            all.map(\.rawValue) == [
                "created", "saved", "moved", "edited", "deleted", "editingStarted", "editingEnded",
            ])
        #expect(CaptureChange(rawValue: "created") == .created)
    }

    @Test func publishReachesSubscribersInOrder() {
        let bus = CaptureEventBus()
        var log: [String] = []
        let a = bus.subscribe { _ in log.append("a") }
        let b = bus.subscribe { _ in log.append("b") }
        bus.publish(event(.created, item(id)))
        #expect(log == ["a", "b"])
        withExtendedLifetime((a, b)) {}
    }

    @Test func cancelledAndDroppedSubscriptionsGetNothing() {
        let bus = CaptureEventBus()
        var log: [String] = []
        let a = bus.subscribe { _ in log.append("a") }
        var b: CaptureSubscription? = bus.subscribe { _ in log.append("b") }
        let c = bus.subscribe { _ in log.append("c") }
        a.cancel()
        #expect(b != nil)
        b = nil
        bus.publish(event(.created, item(id)))
        #expect(log == ["c"])
        withExtendedLifetime(c) {}
    }

    @Test func nestedPublishesAreDeliveredAfterTheCurrentEventToEveryone() {
        let bus = CaptureEventBus()
        var log: [String] = []
        let other = CaptureID()
        let a = bus.subscribe { event in
            log.append("a:\(event.change.rawValue)")
            if event.change == .created {
                bus.publish(CaptureEvent(change: .edited, item: event.item, origin: "editor"))
                bus.publish(CaptureEvent(change: .deleted, item: self.item(other), origin: "editor"))
            }
        }
        let b = bus.subscribe { event in log.append("b:\(event.change.rawValue)") }
        bus.publish(event(.created, item(id)))
        #expect(log == ["a:created", "b:created", "a:edited", "b:edited", "a:deleted", "b:deleted"])
        withExtendedLifetime((a, b)) {}
    }

    @Test func aSubscriptionCancelledDuringDeliveryGetsNoMore() {
        let bus = CaptureEventBus()
        var log: [String] = []
        var b: CaptureSubscription?
        let a = bus.subscribe { _ in
            log.append("a")
            b?.cancel()
        }
        b = bus.subscribe { _ in log.append("b") }
        bus.publish(event(.created, item(id)))
        #expect(log == ["a"])
        withExtendedLifetime(a) {}
    }

    @Test func itemFollowsTheCaptureAndForgetsOnDelete() {
        let bus = CaptureEventBus()
        #expect(bus.item(id) == nil)
        bus.publish(event(.created, item(id, "/tmp/a.png")))
        #expect(bus.item(id)?.fileURL.path == "/tmp/a.png")
        bus.publish(event(.saved, item(id, "/s/a.png", saved: true)))
        #expect(bus.item(id)?.isSaved == true)
        bus.publish(event(.moved, item(id, "/s/b.png", saved: true)))
        #expect(bus.item(id)?.fileURL.path == "/s/b.png")
        var edited = item(id, "/s/b.png", saved: true)
        edited.pixelsPerPoint = 1
        bus.publish(event(.edited, edited))
        #expect(bus.item(id)?.pixelsPerPoint == 1)
        bus.publish(event(.deleted, edited))
        #expect(bus.item(id) == nil)
    }

    @Test func editingAndUnknownChangesNeitherStoreNorForget() {
        let bus = CaptureEventBus()
        bus.publish(event(.created, item(id, "/tmp/a.png")))
        for change in [CaptureChange.editingStarted, .editingEnded, CaptureChange(rawValue: "starred")] {
            bus.publish(event(change, item(id, "/elsewhere.png")))
            #expect(bus.item(id)?.fileURL.path == "/tmp/a.png")
        }
        let unknown = CaptureID()
        bus.publish(event(.editingStarted, item(unknown)))
        #expect(bus.item(unknown) == nil)
    }

    @Test func aChangeForAnUnknownIDIsDeliveredButNotStored() {
        let bus = CaptureEventBus()
        var delivered: [CaptureChange] = []
        let s = bus.subscribe { delivered.append($0.change) }
        bus.publish(event(.saved, item(id)))
        bus.publish(event(.moved, item(id)))
        bus.publish(event(.edited, item(id)))
        #expect(delivered == [.saved, .moved, .edited])
        #expect(bus.item(id) == nil)
        withExtendedLifetime(s) {}
    }
}
