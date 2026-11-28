import AppKit
import BugeyeCore

/// The general pasteboard (contracts §4.4): clears it and writes **one** item holding whichever of `public.png`,
/// `public.file-url` and `public.utf8-plain-text` the payload sets (Capture C3, Editor §5.8, Recording V12).
public struct PasteboardClipboardWriter: ClipboardWriter {
    public struct WriteFailed: Error, Equatable {
        public init() {}
    }

    /// The pasteboard's name; tests pass a private one.
    private let name: String

    public init(pasteboardName: String = NSPasteboard.Name.general.rawValue) {
        name = pasteboardName
    }

    public func write(_ payload: ClipboardPayload) throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = payload.png { item.setData(png, forType: .png) }
        if let url = payload.fileURL { item.setString(url.absoluteString, forType: .fileURL) }
        if let text = payload.text { item.setString(text, forType: .string) }
        guard pasteboard.writeObjects([item]) else { throw WriteFailed() }
    }
}
