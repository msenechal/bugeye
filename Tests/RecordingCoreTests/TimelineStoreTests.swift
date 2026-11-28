import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@Suite struct TimelineStoreTests {
    private func item(_ id: CaptureID, _ kind: CaptureKind) -> CaptureItem {
        CaptureItem(
            id: id, fileURL: URL(fileURLWithPath: "/tmp/x.\(kind.fileExtension)"), isSaved: true, kind: kind,
            createdAt: Date(), pixelsPerPoint: 2, duration: kind == .recording ? 3 : nil)
    }

    @Test func aTakesTimelineLivesBesideItsMovie() throws {
        let take = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(
            TimelineStore.takeURL(take: take, home: "/Users/m").path
                == "/Users/m/Library/Caches/dev.msenechal.bugeye/Recordings/Take-6f9619ff-8b86-d011-b42d-00c04fc964ff.timeline.jsonl"
        )
    }

    @Test func adoptMovesTheTakesTimelineUnderTheCaptureID() throws {
        let home = try TempDirectory("home")
        defer { home.remove() }
        let store = TimelineStore(home: home.url.path)
        let take = TimelineStore.takeURL(take: UUID(), home: home.url.path)
        try FileManager.default.createDirectory(
            at: take.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x\n".utf8).write(to: take)
        let id = CaptureID()
        let stored = try store.adopt(take, as: id)
        #expect(stored == EventTimeline.url(for: id, home: home.url.path))
        #expect(try Data(contentsOf: stored) == Data("x\n".utf8))
        #expect(!FileManager.default.fileExists(atPath: take.path))
    }

    @Test func adoptingAMissingTakeThrowsAndCreatesNothing() throws {
        let home = try TempDirectory("home")
        defer { home.remove() }
        let store = TimelineStore(home: home.url.path)
        let id = CaptureID()
        #expect(throws: (any Error).self) { try store.adopt(home.file("missing.timeline.jsonl"), as: id) }
        #expect(!FileManager.default.fileExists(atPath: EventTimeline.url(for: id, home: home.url.path).path))
    }

    @MainActor @Test func aDeletedRecordingLosesItsTimelineOtherKindsAndChangesDoNot() async throws {
        let home = try TempDirectory("home")
        defer { home.remove() }
        let store = TimelineStore(home: home.url.path)
        let bus = CaptureEventBus()
        let subscription = store.observe(bus)
        let recording = CaptureID()
        let screenshot = CaptureID()
        let folder = EventTimeline.folder(home: home.url.path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for id in [recording, screenshot] {
            try Data("x\n".utf8).write(to: EventTimeline.url(for: id, home: home.url.path))
        }
        bus.publish(CaptureEvent(change: .saved, item: item(recording, .recording), origin: "quickAccess"))
        bus.publish(CaptureEvent(change: .deleted, item: item(screenshot, .screenshot), origin: "quickAccess"))
        #expect(FileManager.default.fileExists(atPath: EventTimeline.url(for: recording, home: home.url.path).path))
        #expect(FileManager.default.fileExists(atPath: EventTimeline.url(for: screenshot, home: home.url.path).path))
        bus.publish(CaptureEvent(change: .deleted, item: item(recording, .recording), origin: "quickAccess"))
        // Deleted off the main actor (claude-review #4 minor 2): wait for it, bounded.
        let deleted = await store.waitForDeletions()
        #expect(deleted)
        #expect(!FileManager.default.fileExists(atPath: EventTimeline.url(for: recording, home: home.url.path).path))
        // A capture without a timeline: nothing to do, no error.
        bus.publish(CaptureEvent(change: .deleted, item: item(CaptureID(), .recording), origin: "quickAccess"))
        subscription.cancel()
    }
}
