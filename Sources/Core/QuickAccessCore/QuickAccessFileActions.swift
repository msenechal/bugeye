import BugeyeCore
import Foundation

/// File work a thumbnail asks for. It runs off the main actor; its result returns to the model as a value.
public enum QuickAccessFileAction: Hashable, Sendable {
    /// Copy: a screenshot's PNG and URL, or another kind's URL.
    case readForCopy(CaptureItem)
    /// Save: into `folder` (`AppSettings.saveFolder`, read fresh); `displayPath` is how General shows it.
    case save(CaptureItem, folder: URL, displayPath: String)
    /// Save As…: a copy with a new identity (Q18).
    case saveAs(CaptureItem, to: URL, newID: CaptureID)
}

public enum QuickAccessFileResult: Hashable, Sendable {
    case copied(ClipboardPayload)
    /// The file is missing or unreadable; `name` is its file name.
    case copyFailed(name: String)
    /// The item as it is now (new URL, `isSaved`), and where the file was.
    case saved(CaptureItem, previousURL: URL)
    /// The folder couldn't be created or isn't writable; `path` as General shows it.
    case saveFolderUnavailable(path: String)
    /// Any other Save failure, as its error's text.
    case saveFailed(String)
    /// The copy as a new capture: new id, its URL, saved.
    case savedCopy(CaptureItem)
    /// Save As… onto the capture's own file: nothing was done (Q11).
    case saveAsUnchanged
    case saveAsFailed(String)
    case deleted
    case deleteFailed(String)
}

/// Copy's read, Save through `CaptureFileWriter.move` and Save As… through `CaptureFileWriter.copy` (spec §5.2,
/// Q6, Q18). A pure function of its inputs: the model decides, this only does the file work.
public struct QuickAccessFileActions: Sendable {
    private let writer: CaptureFileWriter

    public init(writer: CaptureFileWriter) {
        self.writer = writer
    }

    public func run(_ action: QuickAccessFileAction) -> QuickAccessFileResult {
        switch action {
        case .readForCopy(let item): readForCopy(item)
        case .save(let item, let folder, let displayPath): save(item, into: folder, displayPath: displayPath)
        case .saveAs(let item, let destination, let newID): saveAs(item, to: destination, newID: newID)
        }
    }

    /// Delete's file work: `remove` trashes a saved file or removes a temp one. A file that is already gone counts
    /// as deleted (Q11).
    public static func delete(_ url: URL, using remove: (URL) throws -> Void) -> QuickAccessFileResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .deleted }
        do {
            try remove(url)
            return .deleted
        } catch {
            return FileManager.default.fileExists(atPath: url.path)
                ? .deleteFailed(error.localizedDescription) : .deleted
        }
    }

    private func readForCopy(_ item: CaptureItem) -> QuickAccessFileResult {
        let url = item.fileURL
        let failed = QuickAccessFileResult.copyFailed(name: url.lastPathComponent)
        guard item.kind == .screenshot else {
            return FileManager.default.isReadableFile(atPath: url.path)
                ? .copied(ClipboardPayload(fileURL: url)) : failed
        }
        guard let png = try? Data(contentsOf: url) else { return failed }
        return .copied(ClipboardPayload(png: png, fileURL: url))
    }

    private func save(_ item: CaptureItem, into folder: URL, displayPath: String) -> QuickAccessFileResult {
        do {
            try SaveFolder.ensureExists(at: folder)
        } catch {
            return .saveFolderUnavailable(path: displayPath)
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return .saveFolderUnavailable(path: displayPath)
        }
        do {
            var saved = item
            saved.fileURL = try writer.move(item.fileURL, into: folder)
            saved.isSaved = true
            return .saved(saved, previousURL: item.fileURL)
        } catch {
            return .saveFailed(error.localizedDescription)
        }
    }

    private func saveAs(_ item: CaptureItem, to destination: URL, newID: CaptureID) -> QuickAccessFileResult {
        do {
            try writer.copy(item.fileURL, to: destination, identity: .new(newID))
        } catch is CaptureFileWriter.SameFile {
            return .saveAsUnchanged
        } catch {
            return .saveAsFailed(error.localizedDescription)
        }
        return .savedCopy(
            CaptureItem(
                id: newID, fileURL: destination, isSaved: true, kind: item.kind, createdAt: item.createdAt,
                pixelsPerPoint: item.pixelsPerPoint, duration: item.duration))
    }
}
