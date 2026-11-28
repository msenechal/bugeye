import BugeyeCore
import Foundation

/// Where timelines live (V5): beside the take while recording, then under the capture's identity in
/// Application Support, deleted when the capture is.
public struct TimelineStore: Sendable {
    public let home: String

    public init(home: String) {
        self.home = home
    }

    /// <home>/Library/Caches/dev.msenechal.bugeye/Recordings/Take-<uuid>.timeline.jsonl, beside the take's .mov.
    public static func takeURL(take: UUID, home: String) -> URL {
        CaptureFolders.recordingsInProgress(home: home)
            .appendingPathComponent("Take-" + take.uuidString.lowercased() + EventTimeline.fileSuffix)
    }

    /// Moves a take's timeline to `Timelines/<id>.timeline.jsonl` and returns the new URL. The id is new, so
    /// nothing is replaced; a clash throws.
    public func adopt(_ take: URL, as id: CaptureID) throws -> URL {
        let destination = EventTimeline.url(for: id, home: home)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: take, to: destination)
        return destination
    }

    /// Deletes a capture's timeline; no error when it has none.
    public func delete(_ id: CaptureID) {
        try? FileManager.default.removeItem(at: EventTimeline.url(for: id, home: home))
    }

    /// Deletes a recording's timeline when a `deleted` event for it reaches the bus.
    @MainActor
    public func observe(_ bus: CaptureEventBus) -> CaptureSubscription {
        bus.subscribe { event in
            guard event.change == .deleted, event.item.kind == .recording else { return }
            delete(event.item.id)
        }
    }
}
