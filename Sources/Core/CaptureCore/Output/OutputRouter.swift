import BugeyeCore
import Foundation

/// One encoded capture to save and copy.
public struct OutputRequest: Sendable {
    public var png: Data
    public var id: CaptureID
    /// When the pixels were taken: names the file (C10).
    public var createdAt: Date
    public var pixelsPerPoint: Double
    public var settings: CaptureSettings
    public var saveFolder: URL
    /// The save folder as the General pane shows it (`~/…`), for the notice.
    public var displayedSaveFolder: String
    public var tempFolder: URL
    public var timeZone: TimeZone

    public init(
        png: Data, id: CaptureID, createdAt: Date, pixelsPerPoint: Double, settings: CaptureSettings, saveFolder: URL,
        displayedSaveFolder: String, tempFolder: URL, timeZone: TimeZone = .current
    ) {
        self.png = png
        self.id = id
        self.createdAt = createdAt
        self.pixelsPerPoint = pixelsPerPoint
        self.settings = settings
        self.saveFolder = saveFolder
        self.displayedSaveFolder = displayedSaveFolder
        self.tempFolder = tempFolder
        self.timeZone = timeZone
    }
}

public struct OutputResult: Sendable {
    /// Nil when even the temp write failed: nothing is announced.
    public var item: CaptureItem?
    public var notices: [Notice]
    /// `capture` category lines (Capture §8).
    public var logs: [String]
}

/// Save → copy (Capture §5.4). Writes through `CaptureFileWriter.create` only, so a file is never replaced. Slow:
/// call it off the main actor.
public struct OutputRouter: Sendable {
    let writer: CaptureFileWriter
    let clipboard: any ClipboardWriter

    public init(writer: CaptureFileWriter, clipboard: any ClipboardWriter) {
        self.writer = writer
        self.clipboard = clipboard
    }

    public func deliver(_ request: OutputRequest) -> OutputResult {
        let name = CaptureFileNamer.name(kind: .screenshot, date: request.createdAt, timeZone: request.timeZone)
        var notices: [Notice] = []
        var logs: [String] = []
        var saved: URL?
        if request.settings.saveToFolder {
            do {
                saved = try create(request, name: name, in: request.saveFolder, createFolder: false)
                logs.append("saved \(saved!.lastPathComponent)")
            } catch {
                notices.append(
                    Notice(
                        title: OutputStrings.folderUnavailableTitle,
                        body: OutputStrings.folderUnavailableBody(path: request.displayedSaveFolder)))
                logs.append("kept in temp \(name): \(Self.reason(error))")
            }
        }
        let url: URL
        if let saved {
            url = saved
        } else {
            do {
                url = try create(request, name: name, in: request.tempFolder, createFolder: true)
            } catch {
                logs.append("failed screenshot: \(Self.reason(error))")
                if request.settings.copyToClipboard {
                    copy(ClipboardPayload(png: request.png), logs: &logs)
                    notices.append(
                        Notice(title: CaptureStrings.captureFailedTitle, body: CaptureStrings.writeFailedCopied))
                } else {
                    notices.append(Notice(title: CaptureStrings.captureFailedTitle, body: CaptureStrings.writeFailed))
                }
                return OutputResult(item: nil, notices: notices, logs: logs)
            }
        }
        if request.settings.copyToClipboard {
            copy(ClipboardPayload(png: request.png, fileURL: url), logs: &logs)
        }
        let item = CaptureItem(
            id: request.id, fileURL: url, isSaved: saved != nil, kind: .screenshot, createdAt: request.createdAt,
            pixelsPerPoint: request.pixelsPerPoint)
        return OutputResult(item: item, notices: notices, logs: logs)
    }

    /// The save folder must already exist (the shell creates it at launch and when it's chosen): creating a missing
    /// one here could put it on the boot volume under an unplugged disk's mount point. The temp folder is created.
    private func create(_ request: OutputRequest, name: String, in folder: URL, createFolder: Bool) throws -> URL {
        var isDirectory: ObjCBool = false
        if createFolder {
            try SaveFolder.ensureExists(at: folder)
        } else if !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            || !isDirectory.boolValue
        {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: folder.path])
        }
        return try writer.create(request.png, named: name, in: folder, identity: request.id)
    }

    private func copy(_ payload: ClipboardPayload, logs: inout [String]) {
        do {
            try clipboard.write(payload)
        } catch {
            logs.append("failed copy: \(Self.reason(error))")
        }
    }

    static func reason(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
