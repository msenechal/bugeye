import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@MainActor @Suite struct RecordingDeliveryTests {
    let date = Date(timeIntervalSince1970: 1_795_788_192)
    let utc = TimeZone(identifier: "UTC")!

    @MainActor struct Fixture {
        let home: TempDirectory
        let save: URL
        let settings: InMemorySettingsStore
        let metadata = FakeFileMetadataStore()
        let clipboard = FakeClipboard()
        let notifier = FakeNotifier()
        let bus = CaptureEventBus()
        let decorations: ThumbnailDecorations
        let recorder: CaptureEventRecorder
        let delivery: RecordingDelivery

        @MainActor init(settings: [String: SettingValue] = [:], saveFolderExists: Bool = true) throws {
            home = try TempDirectory("home")
            save = home.url.appendingPathComponent("Pictures/Bugeye", isDirectory: true)
            if saveFolderExists { try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true) }
            self.settings = InMemorySettingsStore(settings)
            decorations = ThumbnailDecorations(bus: bus)
            recorder = CaptureEventRecorder(bus)
            let save = save
            delivery = RecordingDelivery(
                ports: RecordingDelivery.Ports(
                    fileWriter: CaptureFileWriter(metadata: metadata), bus: bus, decorations: decorations,
                    clipboard: clipboard, notifier: notifier, timelines: TimelineStore(home: home.url.path),
                    settings: self.settings, home: home.url.path, saveFolder: { save }),
                timeZone: TimeZone(identifier: "UTC")!)
        }

        /// A take's movie and timeline in the in-progress folder.
        func take(_ ext: String = "mov", timeline: Bool = true) throws -> (URL, URL?) {
            let folder = CaptureFolders.recordingsInProgress(home: home.url.path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let id = UUID()
            let movie = folder.appendingPathComponent("Take-\(id.uuidString.lowercased()).\(ext)")
            try Data("movie".utf8).write(to: movie)
            guard timeline else { return (movie, nil) }
            let line = TimelineStore.takeURL(take: id, home: home.url.path)
            try Data("{}\n".utf8).write(to: line)
            return (movie, line)
        }
    }

    @Test func deliversIntoTheSaveFolderWithBadgeClipboardTimelineAndEvent() async throws {
        let f = try Fixture()
        defer { f.home.remove() }
        let (movie, timeline) = try f.take("mp4")
        let item = try #require(
            await f.delivery.deliver(
                movie: movie, date: date, duration: 42.7, pixelsPerPoint: 2, timeline: timeline, preview: nil))
        #expect(item.fileURL.deletingLastPathComponent().standardizedFileURL == f.save.standardizedFileURL)
        #expect(item.fileURL.lastPathComponent == "Recording 2026-11-27 at 14.03.12.mp4")
        #expect(item.isSaved)
        #expect(item.kind == .recording)
        #expect(item.duration == 42.7)
        #expect(item.createdAt == date)
        #expect(item.pixelsPerPoint == 2)
        #expect(!FileManager.default.fileExists(atPath: movie.path))
        #expect(f.clipboard.written == [ClipboardPayload(fileURL: item.fileURL)])
        #expect(f.decorations.decorations(for: item.id) == [.mediaBadge(text: "▶ 00:42")])
        #expect(f.recorder.changes == [.created])
        #expect(f.recorder.events.first?.origin == "recording")
        #expect(FileManager.default.fileExists(atPath: EventTimeline.url(for: item.id, home: f.home.url.path).path))
        #expect(f.notifier.posts.isEmpty)
    }

    @Test func aMovKeepsItsExtensionAndAClashGetsASuffix() async throws {
        let f = try Fixture()
        defer { f.home.remove() }
        try Data().write(to: f.save.appendingPathComponent("Recording 2026-11-27 at 14.03.12.mov"))
        let (movie, _) = try f.take("mov", timeline: false)
        let item = try #require(
            await f.delivery.deliver(
                movie: movie, date: date, duration: 1, pixelsPerPoint: 1, timeline: nil, preview: nil))
        #expect(item.fileURL.lastPathComponent == "Recording 2026-11-27 at 14.03.12 (2).mov")
    }

    @Test func saveOffGoesToTheTempFolderAndClipboardOffWritesNothing() async throws {
        let f = try Fixture(settings: [
            OutputSettings.Key.saveToFolder: .bool(false), OutputSettings.Key.copyToClipboard: .bool(false),
        ])
        defer { f.home.remove() }
        let (movie, _) = try f.take()
        let item = try #require(
            await f.delivery.deliver(
                movie: movie, date: date, duration: 1, pixelsPerPoint: 1, timeline: nil, preview: nil))
        #expect(!item.isSaved)
        #expect(
            item.fileURL.deletingLastPathComponent().standardizedFileURL
                == CaptureFolders.temp(home: f.home.url.path).standardizedFileURL)
        #expect(f.clipboard.written.isEmpty)
        #expect(f.notifier.posts.isEmpty)
    }

    @Test func anUnusableFolderFallsBackToTempWithCapturesNotice() async throws {
        let f = try Fixture()
        defer { f.home.remove() }
        try FileManager.default.removeItem(at: f.save)
        try Data("a file where the folder should be".utf8).write(to: f.save)
        let (movie, _) = try f.take()
        let item = try #require(
            await f.delivery.deliver(
                movie: movie, date: date, duration: 1, pixelsPerPoint: 1, timeline: nil, preview: nil))
        #expect(!item.isSaved)
        #expect(
            f.notifier.posts == [
                FakeNotifier.Post(
                    title: "Couldn't save to folder",
                    body: OutputStrings.folderUnavailableBody(path: "~/Pictures/Bugeye"))
            ])
    }

    @Test func whenEvenTheTempFolderRefusesTheTakeStaysAndSaysWhere() async throws {
        let f = try Fixture(settings: [OutputSettings.Key.saveToFolder: .bool(false)])
        defer { f.home.remove() }
        let temp = CaptureFolders.temp(home: f.home.url.path)
        try FileManager.default.createDirectory(
            at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: temp)
        let (movie, timeline) = try f.take()
        let item = await f.delivery.deliver(
            movie: movie, date: date, duration: 1, pixelsPerPoint: 1, timeline: timeline, preview: nil)
        #expect(item == nil)
        #expect(FileManager.default.fileExists(atPath: movie.path))
        let shown = "~/" + movie.path.dropFirst(f.home.url.path.count + 1)
        #expect(
            f.notifier.posts == [
                FakeNotifier.Post(title: "Couldn't save the recording", body: "It is still in \(shown).")
            ])
        #expect(f.recorder.events.isEmpty)
    }
}
