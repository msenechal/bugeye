import BugeyeCore
import BugeyeFeatures
import Foundation

/// Delivers a finished take (§5.6), in order: the file into the save folder (or the temp folder when "Save to
/// folder" is off or the folder is unusable, with Capture's notice) under a new `CaptureID`; the file reference
/// on the clipboard if "Copy to clipboard" is on; the timeline moved to its store; the `▶` badge; `created` on
/// the bus. File work runs off the main actor.
@MainActor
public final class RecordingDelivery {
    public struct Ports {
        public var fileWriter: CaptureFileWriter
        public var bus: CaptureEventBus
        public var decorations: ThumbnailDecorations
        public var clipboard: any ClipboardWriter
        public var notifier: any Notifier
        public var timelines: TimelineStore
        public var settings: any SettingsStore
        public var home: String
        /// The General pane's folder, read at delivery.
        public var saveFolder: @MainActor () -> URL

        public init(
            fileWriter: CaptureFileWriter, bus: CaptureEventBus, decorations: ThumbnailDecorations,
            clipboard: any ClipboardWriter, notifier: any Notifier, timelines: TimelineStore,
            settings: any SettingsStore, home: String, saveFolder: @escaping @MainActor () -> URL
        ) {
            self.fileWriter = fileWriter
            self.bus = bus
            self.decorations = decorations
            self.clipboard = clipboard
            self.notifier = notifier
            self.timelines = timelines
            self.settings = settings
            self.home = home
            self.saveFolder = saveFolder
        }
    }

    public static let origin = "recording"

    private let ports: Ports
    private let timeZone: TimeZone

    public init(ports: Ports, timeZone: TimeZone = .current) {
        self.ports = ports
        self.timeZone = timeZone
    }

    /// The delivered item, or nil when even the temp folder refused the file (its notice is posted and the take
    /// stays where it is).
    public func deliver(
        movie: URL, date: Date, duration: Double, pixelsPerPoint: Double, timeline: URL?, preview: PixelBuffer?
    ) async -> CaptureItem? {
        let output = OutputSettings.load(from: ports.settings)
        let name = CaptureFileNamer.name(
            kind: .recording, date: date, fileExtension: movie.pathExtension, timeZone: timeZone)
        let id = CaptureID()
        let writer = ports.fileWriter
        let saveFolder = ports.saveFolder()
        let temp = CaptureFolders.temp(home: ports.home)

        let placed: (url: URL, saved: Bool, folderFailed: Bool)? = await Task.detached {
            if output.saveToFolder {
                if let url = try? Self.move(movie, into: saveFolder, named: name, id: id, writer: writer) {
                    return (url, true, false)
                }
                guard let url = try? Self.move(movie, into: temp, named: name, id: id, writer: writer) else {
                    return nil
                }
                return (url, false, true)
            }
            guard let url = try? Self.move(movie, into: temp, named: name, id: id, writer: writer) else { return nil }
            return (url, false, false)
        }.value

        guard let placed else {
            ports.notifier.post(
                notice: RecordingStrings.Notice.couldNotSave(path: movie.path, home: ports.home))
            return nil
        }
        if placed.folderFailed {
            ports.notifier.post(
                title: OutputStrings.folderUnavailableTitle,
                body: OutputStrings.folderUnavailableBody(
                    path: RecordingStrings.homeRelative(saveFolder.path, home: ports.home)))
        }
        if output.copyToClipboard { try? ports.clipboard.write(ClipboardPayload(fileURL: placed.url)) }
        if let timeline {
            let timelines = ports.timelines
            _ = await Task.detached { try? timelines.adopt(timeline, as: id) }.value
        }
        let item = CaptureItem(
            id: id, fileURL: placed.url, isSaved: placed.saved, kind: .recording, createdAt: date,
            pixelsPerPoint: pixelsPerPoint, duration: duration)
        ports.decorations.set(
            [.mediaBadge(text: "▶ " + MediaTime.text(seconds: duration))], for: id, from: Self.origin)
        ports.bus.publish(CaptureEvent(change: .created, item: item, preview: preview, origin: Self.origin))
        return item
    }

    /// Creates the folder if it's missing; a file in its place, an unwritable folder or no free name throws.
    nonisolated private static func move(
        _ movie: URL, into folder: URL, named name: String, id: CaptureID, writer: CaptureFileWriter
    ) throws -> URL {
        try SaveFolder.ensureExists(at: folder)
        return try writer.move(movie, into: folder, named: name, identity: .new(id))
    }
}

extension Notifier {
    func post(notice: RecordingNotice) {
        post(title: notice.title, body: notice.body)
    }
}
