import AppKit
import BugeyeCore
import BugeyeFeatures
import EditorCore
import MacAdapters
import UniformTypeIdentifiers
import os

/// Alerts and the save panel, injectable for tests (§5.8, §5.9).
@MainActor
protocol EditorPrompts: AnyObject {
    func askToSave(name: String, window: NSWindow?) async -> SaveAnswer
    /// True for Save As….
    func goneAlert(name: String, window: NSWindow?) async -> Bool
    func saveAsURL(name: String, folder: URL, window: NSWindow?) async -> URL?
    func saveFailed(name: String, message: String, window: NSWindow?) async
}

/// The real prompts: sheets on the editor's window.
@MainActor
final class SheetPrompts: EditorPrompts {
    private func run(_ alert: NSAlert, on window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    func askToSave(name: String, window: NSWindow?) async -> SaveAnswer {
        let alert = NSAlert()
        alert.messageText = EditorStrings.unsavedTitle(name: name)
        alert.informativeText = EditorStrings.unsavedBody
        alert.addButton(withTitle: EditorStrings.saveButton)
        alert.addButton(withTitle: EditorStrings.dontSaveButton)
        alert.addButton(withTitle: EditorStrings.cancelButton)
        switch await run(alert, on: window) {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .dontSave
        default: return .cancel
        }
    }

    func goneAlert(name: String, window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = EditorStrings.goneTitle
        alert.informativeText = EditorStrings.goneBody(name: name)
        alert.addButton(withTitle: EditorStrings.saveAsButton)
        alert.addButton(withTitle: EditorStrings.cancelButton)
        return await run(alert, on: window) == .alertFirstButtonReturn
    }

    func saveAsURL(name: String, folder: URL, window: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name
        panel.directoryURL = folder
        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    func saveFailed(name: String, message: String, window: NSWindow?) async {
        let alert = NSAlert()
        alert.messageText = EditorStrings.saveFailedTitle(name: name)
        alert.informativeText = message
        alert.addButton(withTitle: EditorStrings.okButton)
        _ = await run(alert, on: window)
    }
}

/// The macOS side of the editor: implements `EditorHost` for `EditorSessions` (plan P8), owns the windows and the
/// decoded captures, and logs (§8.4).
@MainActor
final class EditorManager: EditorHost {
    static let logger = Logger(subsystem: CaptureFolders.bundleID, category: "editor")

    let sessions: EditorSessions
    let prompts: any EditorPrompts
    private(set) var windows: [CaptureID: EditorWindowController] = [:]
    private var captures: [CaptureID: CGImage] = [:]
    private var blurCaches: [CaptureID: BlurCache] = [:]

    init(environment: EditorEnvironment, prompts: any EditorPrompts = SheetPrompts()) {
        sessions = EditorSessions(environment: environment)
        self.prompts = prompts
        sessions.host = self
    }

    /// The environment for the live app: the context's ports, logging to `os.Logger`.
    static func environment(
        bus: CaptureEventBus, documentWindows: DocumentWindows, writer: CaptureFileWriter,
        clipboard: any ClipboardWriter, notifier: any Notifier, saveFolder: @escaping @MainActor () -> URL
    ) -> EditorEnvironment {
        EditorEnvironment(
            bus: bus, documentWindows: documentWindows, writer: writer, clipboard: clipboard, notifier: notifier,
            saveFolder: saveFolder, log: { logger.log("\($0, privacy: .public)") })
    }

    /// The router's opener for screenshots (E2).
    func open(_ item: CaptureItem) {
        Task { await sessions.open(item) }
    }

    func windowClosed(_ controller: EditorWindowController) {
        let id = controller.session.id
        guard windows[id] === controller else { return }
        windows[id] = nil
        captures[id] = nil
        blurCaches[id] = nil
        sessions.didClose(id)
    }

    // MARK: EditorHost

    func load(_ item: CaptureItem) async -> Result<Size2D, EditorLoadFailure> {
        let url = item.fileURL
        let decoded = await Task.detached(priority: .userInitiated) { EditorImages.decode(url) }.value
        switch decoded {
        case .failure(let failure):
            return .failure(failure)
        case .success(let image):
            captures[item.id] = image
            blurCaches[item.id] = BlurCache()
            return .success(Size2D(width: Double(image.width), height: Double(image.height)))
        }
    }

    func showWindow(for session: EditorSession) {
        guard let capture = captures[session.id], let cache = blurCaches[session.id] else {
            Self.logger.fault("show without a decoded image for \(session.name, privacy: .public)")
            return
        }
        let controller = EditorWindowController(session: session, capture: capture, blurCache: cache, manager: self)
        windows[session.id] = controller
        controller.show()
    }

    func bringForward(_ id: CaptureID) { windows[id]?.bringForward() }
    func retitle(_ session: EditorSession) { windows[session.id]?.retitle() }
    func commitPendingEdits(_ session: EditorSession) { windows[session.id]?.canvas.commitText() }
    func documentSaved(_ session: EditorSession) { windows[session.id]?.canvasDidChange() }

    func export(_ session: EditorSession, state: EditorState) async throws -> ExportedImage {
        guard let capture = captures[session.id], let cache = blurCaches[session.id] else {
            throw EditorImages.ExportFailed()
        }
        let metrics = EditorMetrics(ppp: session.item.pixelsPerPoint, measurer: CoreTextMeasurer())
        return try await Task.detached(priority: .userInitiated) {
            try EditorImages.export(state: state, capture: capture, metrics: metrics, blur: cache)
        }.value
    }

    func askToSave(_ session: EditorSession) async -> SaveAnswer {
        await prompts.askToSave(name: session.name, window: windows[session.id]?.window)
    }

    func showGoneAlert(_ session: EditorSession) async -> Bool {
        await prompts.goneAlert(name: session.name, window: windows[session.id]?.window)
    }

    func chooseSaveAsURL(_ session: EditorSession) async -> URL? {
        await prompts.saveAsURL(
            name: session.name, folder: session.item.fileURL.deletingLastPathComponent(),
            window: windows[session.id]?.window)
    }

    func showSaveFailed(_ session: EditorSession, name: String, message: String) async {
        await prompts.saveFailed(name: name, message: message, window: windows[session.id]?.window)
    }
}
