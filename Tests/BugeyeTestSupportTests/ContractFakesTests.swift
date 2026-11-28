import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

/// The fakes the contracts PR adds (contracts §4.3).
@Suite struct ContractFakesTests {
    @MainActor @Test func theRecorderKeepsEveryEventInOrder() {
        let bus = CaptureEventBus()
        let recorder = CaptureEventRecorder(bus)
        let item = CaptureItem(
            id: CaptureID(), fileURL: URL(fileURLWithPath: "/tmp/a.png"), isSaved: false, kind: .screenshot,
            createdAt: Date(), pixelsPerPoint: 2)
        bus.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        bus.publish(CaptureEvent(change: .deleted, item: item, origin: "quickAccess"))
        #expect(recorder.changes == [.created, .deleted])
        #expect(recorder.events.map(\.origin) == ["capture", "quickAccess"])
    }

    @Test func theNotifierRecordsPosts() async {
        let notifier = FakeNotifier()
        await withTaskGroup(of: Void.self) { group in
            for n in 0..<50 { group.addTask { notifier.post(title: "T\(n)", body: "B") } }
        }
        #expect(notifier.posts.count == 50)
        notifier.post(title: "Couldn't save to folder", body: "x")
        #expect(notifier.posts.last == FakeNotifier.Post(title: "Couldn't save to folder", body: "x"))
    }

    @Test func thePermissionAnswersAndCountsRequests() {
        let permission = FakeScreenCapturePermission(granted: false)
        #expect(!permission.preflight())
        permission.requestAccess()
        permission.requestAccess()
        #expect(permission.requestCount == 2)
        permission.granted = true
        #expect(permission.preflight())
    }

    @MainActor @Test func theSelectorAnswersInOrderThenCancels() async {
        let area = StoredArea(
            display: DisplayID(1), rect: Rect2D(x: 0, y: 0, width: 10, height: 10),
            displaySize: Size2D(width: 100, height: 100))
        let selector = FakeAreaSelector(results: [.area(area), .busy])
        let request = SelectionRequest(purpose: .recording)
        #expect(await selector.select(request) == .area(area))
        #expect(await selector.select(request) == .busy)
        #expect(await selector.select(request) == .cancelled)
        selector.cancel(.recording)
        #expect(selector.requests.count == 3)
        #expect(selector.cancels == [.recording])
    }

    @Test func theMeasurerIsProportionalToSizeAndLength() {
        let metrics = FakeTextMeasurer().measure("abcde", font: FontDescriptor(name: "system", size: 10))
        #expect(metrics == TextLineMetrics(width: 30, ascent: 8, descent: 2))
        #expect(FakeTextMeasurer().measure("", font: FontDescriptor(name: "x", size: 20)).width == 0)
        #expect(FakeTextMeasurer().measure("é👍", font: FontDescriptor(name: "x", size: 10)).width == 12)
    }
}
