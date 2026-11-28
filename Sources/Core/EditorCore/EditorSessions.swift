import BugeyeCore
import BugeyeFeatures
import Foundation

/// The rendered export: the PNG and the `edited` preview (≤ 480 px, sRGB).
public struct ExportedImage: Sendable {
    public var png: Data
    public var preview: PixelBuffer?
    public init(png: Data, preview: PixelBuffer?) {
        self.png = png
        self.preview = preview
    }
}

public enum SaveAnswer: Hashable, Sendable { case save, dontSave, cancel }

public enum SaveOutcome: Hashable, Sendable {
    case saved
    /// A clean document whose file exists: nothing to do (E13).
    case unchanged
    /// The user cancelled the gone alert or the save panel.
    case cancelled
    /// The write or the render failed; the alert was shown.
    case failed
}

/// Why a capture couldn't be opened, for the log.
public struct EditorLoadFailure: Error, Hashable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

/// What the macOS shell does for `EditorSessions` (plan P8): windows, rendering, prompts. Every rule lives in
/// `EditorSessions`; the host only shows and renders.
@MainActor
public protocol EditorHost: AnyObject {
    /// Decodes the capture off the main actor and keeps its image for the window; the image's pixel size.
    func load(_ item: CaptureItem) async -> Result<Size2D, EditorLoadFailure>
    func showWindow(for session: EditorSession)
    func bringForward(_ id: CaptureID)
    /// The session's file changed: the title and `representedURL` follow it.
    func retitle(_ session: EditorSession)
    /// Commits typed text, so the document holds every edit (§5.4).
    func commitPendingEdits(_ session: EditorSession)
    /// The document was marked saved: the window's edited dot follows it.
    func documentSaved(_ session: EditorSession)
    /// Renders `state` and encodes PNG and preview, off the main actor.
    func export(_ session: EditorSession, state: EditorState) async throws -> ExportedImage
    /// `Save changes to “<name>”?`
    func askToSave(_ session: EditorSession) async -> SaveAnswer
    /// `The original file is gone`; true for Save As….
    func showGoneAlert(_ session: EditorSession) async -> Bool
    /// The save panel, PNG only, starting at the file's name and folder; nil when cancelled.
    func chooseSaveAsURL(_ session: EditorSession) async -> URL?
    /// `Couldn't save “<name>”` / `message`, button OK.
    func showSaveFailed(_ session: EditorSession, name: String, message: String) async
}

/// The ports and shell objects the sessions use.
public struct EditorEnvironment {
    public var bus: CaptureEventBus
    public var documentWindows: DocumentWindows
    public var writer: CaptureFileWriter
    public var clipboard: any ClipboardWriter
    public var notifier: any Notifier
    /// `AppSettings.saveFolder`, read fresh each time (E4).
    public var saveFolder: @MainActor () -> URL
    public var fileExists: @Sendable (URL) -> Bool
    public var log: @MainActor (String) -> Void
    /// The drag handle's folder (E22).
    public var dragFolder: URL

    public init(
        bus: CaptureEventBus, documentWindows: DocumentWindows, writer: CaptureFileWriter,
        clipboard: any ClipboardWriter, notifier: any Notifier, saveFolder: @escaping @MainActor () -> URL,
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        log: @escaping @MainActor (String) -> Void = { _ in },
        dragFolder: URL = DragFolder.url(temporaryDirectory: FileManager.default.temporaryDirectory)
    ) {
        self.bus = bus
        self.documentWindows = documentWindows
        self.writer = writer
        self.clipboard = clipboard
        self.notifier = notifier
        self.saveFolder = saveFolder
        self.fileExists = fileExists
        self.log = log
        self.dragFolder = dragFolder
    }
}

/// One editor: its capture as last known, its document once loaded.
@MainActor
public final class EditorSession {
    public let id: CaptureID
    /// The capture as last known: from the bus's `saved` and `moved` events, or a gone-file Save As.
    public internal(set) var item: CaptureItem
    /// Nil while the image loads.
    public internal(set) var document: EditorDocument?
    public internal(set) var imageSize = Size2D.zero
    /// A `deleted` event arrived, or a save found the file missing (§5.8).
    public internal(set) var isGone = false
    /// Set when the window closed: a save still running then shows nothing more (final review B, I2).
    public internal(set) var isClosed = false
    /// Increments when a save is requested (S6, plan P9).
    var saveGeneration = 0
    var saveTask: Task<SaveOutcome, Never>?
    /// The unsaved-changes prompt in flight: a close and a quit share it (final review C, I3).
    var askTask: Task<Bool, Never>?

    init(item: CaptureItem) {
        id = item.id
        self.item = item
    }

    /// The file name with its extension.
    public var name: String { item.fileURL.lastPathComponent }
    public var isOpen: Bool { document != nil && !isClosed }
}

/// The open editors and every rule about them (§6.4, S1–S7): one editor per capture, the bus events, saves,
/// Save As, copy, the unsaved prompts and quit.
@MainActor
public final class EditorSessions {
    public let environment: EditorEnvironment
    public weak var host: (any EditorHost)?
    private var sessions: [CaptureID: EditorSession] = [:]
    /// Opening order, for quit (S7).
    private var order: [CaptureID] = []
    private var subscription: CaptureSubscription?

    public init(environment: EditorEnvironment) {
        self.environment = environment
        subscription = environment.bus.subscribe { [weak self] event in self?.handle(event) }
    }

    public func session(_ id: CaptureID) -> EditorSession? { sessions[id] }
    /// Open sessions in opening order.
    public var openSessions: [EditorSession] { order.compactMap { sessions[$0] }.filter(\.isOpen) }

    // MARK: Opening and closing

    /// S1, S2: one editor per capture; decode, then show, `opened()`, `editingStarted`, in that order.
    public func open(_ item: CaptureItem) async {
        if let existing = sessions[item.id] {
            if existing.isOpen { host?.bringForward(item.id) }  // still loading: it will show itself
            return
        }
        let session = EditorSession(item: item)
        sessions[item.id] = session
        order.append(item.id)
        guard let host else { return forget(session) }
        switch await host.load(item) {
        case .failure(let failure):
            forget(session)
            environment.notifier.post(
                title: EditorStrings.openFailedTitle, body: EditorStrings.openFailedBody(name: session.name))
            environment.log(EditorLog.openFailed(session.name, reason: failure.reason))
        case .success(let size):
            guard sessions[item.id] === session else { return }
            session.imageSize = size
            session.document = EditorDocument()
            host.showWindow(for: session)
            environment.documentWindows.opened()
            publish(.editingStarted, session)
            environment.log(EditorLog.open(session.name))
        }
    }

    /// S3: the window closed. Publishes `editingEnded` and `closed()` exactly once.
    public func didClose(_ id: CaptureID) {
        guard let session = sessions[id], session.isOpen else { return }
        session.isClosed = true
        forget(session)
        publish(.editingEnded, session)
        environment.documentWindows.closed()
        environment.log(EditorLog.close(session.name))
    }

    private func forget(_ session: EditorSession) {
        sessions[session.id] = nil
        order.removeAll { $0 == session.id }
    }

    /// S4: follow `saved` and `moved`; `deleted` marks the file gone.
    private func handle(_ event: CaptureEvent) {
        guard let session = sessions[event.item.id] else { return }
        switch event.change {
        case .saved, .moved:
            guard session.item.fileURL != event.item.fileURL || session.isGone else { return }
            session.item = event.item
            session.isGone = false
            if session.isOpen { host?.retitle(session) }
        case .deleted:
            session.isGone = true
        default:
            break
        }
    }

    // MARK: Save

    /// ⌘S (§5.8, E13, E19): serialised, rendered off the main actor, written in place with `requireExisting`.
    public func save(_ id: CaptureID) async -> SaveOutcome {
        guard let session = sessions[id], session.isOpen else { return .failed }
        host?.commitPendingEdits(session)
        session.saveGeneration += 1
        let generation = session.saveGeneration
        let previous = session.saveTask
        let task = Task { @MainActor [weak self] () -> SaveOutcome in
            _ = await previous?.value
            guard let self else { return .failed }
            return await self.performSave(session, generation: generation)
        }
        session.saveTask = task
        return await task.value
    }

    private func performSave(_ session: EditorSession, generation: Int) async -> SaveOutcome {
        guard let document = session.document, let host else { return .failed }
        let snapshot = document.state
        var url = session.item.fileURL
        // Gone: no file at the URL, or a `deleted` event for a capture the bus has forgotten. A file put back at its
        // path (Put Back from the Trash) saves again (final review B, Minor 3).
        let exists = environment.fileExists(url)
        let gone = !exists || (session.isGone && environment.bus.item(session.id) == nil)
        if !gone { session.isGone = false }
        if !document.isDirty && !gone { return .unchanged }
        guard !gone else { return await goneFlow(session) }

        let exported: ExportedImage
        do {
            exported = try await host.export(session, state: snapshot)
        } catch {
            return await failed(session, name: session.name, error: error)
        }
        let start = ContinuousClock.now
        var redone = false
        while true {
            do {
                try await write(exported.png, to: url, attributesFrom: nil, identity: .keep, requireExisting: true)
                break
            } catch is CaptureFileWriter.TargetMissing {
                // E19: Quick Access may have saved it meanwhile; redo once at the bus's URL, else the gone alert.
                if !redone, let moved = environment.bus.item(session.id), moved.fileURL != url {
                    redone = true
                    url = moved.fileURL
                    session.item = moved
                    if session.isOpen { host.retitle(session) }
                    continue
                }
                session.isGone = true
                return await goneFlow(session)
            } catch {
                return await failed(session, name: session.name, error: error)
            }
        }
        let elapsed = start.duration(to: .now)
        environment.log(EditorLog.saved(session.name, milliseconds: Int((elapsed / .milliseconds(1)).rounded())))
        // Every successful write publishes `edited`, even after the window closed or when a newer save is queued:
        // the file changed, and the newer save may write nothing (final review B, I2; claude-review on #14).
        // Only the latest requested save marks the document saved (S6).
        if generation == session.saveGeneration && !session.isClosed {
            document.markSaved(snapshot)
            host.documentSaved(session)
        }
        publish(.edited, session, preview: exported.preview)
        return .saved
    }

    /// The gone alert, then Save As (§5.8, E4, E20).
    private func goneFlow(_ session: EditorSession) async -> SaveOutcome {
        guard let host else { return .failed }
        session.isGone = true
        guard !session.isClosed, await host.showGoneAlert(session), !session.isClosed,
            let chosen = await host.chooseSaveAsURL(session), !session.isClosed, let document = session.document
        else { return .cancelled }
        let snapshot = document.state
        let exported: ExportedImage
        do {
            exported = try await host.export(session, state: snapshot)
            try await write(
                exported.png, to: chosen, attributesFrom: session.item.fileURL, identity: .new(session.id),
                requireExisting: false)
        } catch {
            return await failed(session, name: chosen.lastPathComponent, error: error)
        }
        let old = session.item
        let moved = CaptureItem(
            id: old.id, fileURL: chosen, isSaved: isInSaveFolder(chosen), kind: old.kind, createdAt: old.createdAt,
            pixelsPerPoint: old.pixelsPerPoint, duration: old.duration)
        session.item = moved
        session.isGone = false
        document.markSaved(snapshot)
        if session.isOpen {
            host.retitle(session)
            host.documentSaved(session)
        }
        if environment.bus.item(session.id) != nil {
            environment.bus.publish(
                CaptureEvent(change: .moved, item: moved, previousURL: old.fileURL, origin: EditorModule.id))
            publish(.edited, session, preview: exported.preview)
        } else {
            environment.bus.publish(
                CaptureEvent(change: .created, item: moved, preview: exported.preview, origin: EditorModule.id))
        }
        return .saved
    }

    /// ⇧⌘S: a copy with a new ID; the editor keeps the original and stays dirty; no event (§5.8).
    public func saveAs(_ id: CaptureID) async -> SaveOutcome {
        guard let session = sessions[id], let document = session.document, let host else { return .failed }
        host.commitPendingEdits(session)
        guard let chosen = await host.chooseSaveAsURL(session), !session.isClosed else { return .cancelled }
        // Onto its own file, Save As is a Save: it must keep the capture's ID (final review B, I1).
        if Self.samePath(chosen, session.item.fileURL) { return await save(id) }
        do {
            let exported = try await host.export(session, state: document.state)
            guard !session.isClosed else { return .cancelled }
            try await write(
                exported.png, to: chosen, attributesFrom: session.item.fileURL, identity: .new(CaptureID()),
                requireExisting: false)
        } catch {
            return await failed(session, name: chosen.lastPathComponent, error: error)
        }
        return .saved
    }

    private func failed(_ session: EditorSession, name: String, error: any Error) async -> SaveOutcome {
        environment.log(EditorLog.saveFailed(name, error: String(describing: error)))
        if !session.isClosed {
            await host?.showSaveFailed(session, name: name, message: error.localizedDescription)
        }
        return .failed
    }

    private func write(
        _ png: Data, to url: URL, attributesFrom source: URL?, identity: CaptureIdentity, requireExisting: Bool
    ) async throws {
        let writer = environment.writer
        try await Task.detached {
            try writer.write(png, to: url, attributesFrom: source, identity: identity, requireExisting: requireExisting)
        }.value
    }

    static func normalized(_ u: URL) -> String {
        var path = u.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool { normalized(a) == normalized(b) }

    private func isInSaveFolder(_ url: URL) -> Bool {
        Self.samePath(url.deletingLastPathComponent(), environment.saveFolder())
    }

    // MARK: Copy and drag

    /// ⌘C: the export as PNG on the clipboard; a notice only on failure (§5.8).
    public func copy(_ id: CaptureID) async {
        guard let session = sessions[id], let document = session.document, let host else { return }
        host.commitPendingEdits(session)
        do {
            let exported = try await host.export(session, state: document.state)
            try environment.clipboard.write(ClipboardPayload(png: exported.png))
        } catch {
            environment.notifier.post(title: EditorStrings.copyFailedTitle, body: EditorStrings.copyFailedBody)
        }
    }

    /// The drag handle's file (§5.8, E4, E22): stale files removed, then the export written as a copy with a new
    /// ID into the drag folder under the capture's name. Throws when it can't be written (the drag doesn't start).
    public func writeDragFile(_ id: CaptureID) async throws -> URL {
        guard let session = sessions[id], let document = session.document, let host else {
            throw EditorSessionError.noEditor
        }
        host.commitPendingEdits(session)
        let folder = environment.dragFolder
        let source = session.item.fileURL
        do {
            let exported = try await host.export(session, state: document.state)
            let writer = environment.writer
            return try await Task.detached {
                try DragFolder.prepare(folder, now: Date())
                // Its own subfolder per drag: the file keeps the capture's name, and a later drag never replaces a
                // file another app may still be reading (claude-review on #14).
                let subfolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
                let url = subfolder.appendingPathComponent(source.lastPathComponent)
                try writer.write(exported.png, to: url, attributesFrom: source, identity: .new(CaptureID()))
                return url
            }.value
        } catch {
            environment.log(EditorLog.dragFailed(error: String(describing: error)))
            throw error
        }
    }

    // MARK: Closing and quitting

    /// The close button and ⌘W (§5.9): a dirty editor asks; Save that fails or is cancelled keeps it open.
    public func shouldClose(_ id: CaptureID) async -> Bool {
        guard let session = sessions[id], let document = session.document, let host else { return true }
        host.commitPendingEdits(session)
        _ = await session.saveTask?.value  // a save in flight decides first (final review B, I3)
        guard sessions[id] === session, document.isDirty else { return true }
        return await ask(session)
    }

    /// Quit (S7): every dirty editor in opening order, brought forward and asked; the first Cancel stops.
    public func shouldTerminate() async -> Bool {
        for session in openSessions {
            // An editor closed while an earlier one was asking isn't asked (final review B, I4).
            guard sessions[session.id] === session, session.isOpen, let document = session.document, let host else {
                continue
            }
            host.commitPendingEdits(session)
            _ = await session.saveTask?.value  // a save in flight decides first (I3)
            guard sessions[session.id] === session, document.isDirty else { continue }
            host.bringForward(session.id)
            guard await ask(session) else { return false }
        }
        return true
    }

    /// One prompt per editor at a time: a second close, or a quit, waits for the one already up.
    private func ask(_ session: EditorSession) async -> Bool {
        if let running = session.askTask { return await running.value }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return true }
            return await self.askOnce(session)
        }
        session.askTask = task
        let answer = await task.value
        session.askTask = nil
        return answer
    }

    private func askOnce(_ session: EditorSession) async -> Bool {
        guard let host else { return true }
        switch await host.askToSave(session) {
        case .dontSave: return true
        case .cancel: return false
        case .save:
            let outcome = await save(session.id)
            return outcome == .saved || outcome == .unchanged
        }
    }

    // MARK: Events

    /// E3: the item from the bus, else the last known one (E20).
    private func publish(_ change: CaptureChange, _ session: EditorSession, preview: PixelBuffer? = nil) {
        let item = environment.bus.item(session.id) ?? session.item
        environment.bus.publish(CaptureEvent(change: change, item: item, preview: preview, origin: EditorModule.id))
    }
}

public enum EditorSessionError: Error, Hashable, Sendable {
    /// No open editor for the capture.
    case noEditor
}

/// The drag handle's folder, `<temporary directory>/Bugeye-Drag/`, cleaned only by the editor (E22).
public enum DragFolder {
    public static let maxAge: TimeInterval = 24 * 60 * 60

    public static func url(temporaryDirectory: URL) -> URL {
        temporaryDirectory.appendingPathComponent("Bugeye-Drag", isDirectory: true)
    }

    /// Creates the folder and deletes what's in it (files, or a drag's subfolder) older than 24 h, by modification
    /// date.
    public static func prepare(_ folder: URL, now: Date, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in try fileManager.contentsOfDirectory(atPath: folder.path) {
            let url = folder.appendingPathComponent(name)
            guard let modified = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                now.timeIntervalSince(modified) > maxAge
            else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}

/// Open Last Capture (E12, S8): the newest `created` capture of any kind, enabled when it still exists on the bus,
/// the router has an opener for its kind, and its file exists, all checked each time the menu opens.
@MainActor
public final class LastCapture {
    private let bus: CaptureEventBus
    private let router: ActionRouter
    private let fileExists: @Sendable (URL) -> Bool
    public private(set) var latestID: CaptureID?
    private var subscription: CaptureSubscription?

    public init(
        bus: CaptureEventBus, router: ActionRouter,
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.bus = bus
        self.router = router
        self.fileExists = fileExists
        subscription = bus.subscribe { [weak self] event in
            if event.change == .created { self?.latestID = event.item.id }
        }
    }

    public var item: CaptureItem? { latestID.flatMap { bus.item($0) } }

    public var isEnabled: Bool {
        guard let item else { return false }
        return router.canOpen(item.kind) && fileExists(item.fileURL)
    }

    /// Opens it through the router; false when disabled.
    @discardableResult public func open() -> Bool {
        guard isEnabled, let item else { return false }
        return router.open(item)
    }
}
