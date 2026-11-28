import BugeyeCore
import BugeyeFeatures
import Foundation

/// The single owner of the thumbnail stack (spec §6). Deterministic and on the main actor: the controller feeds it
/// events with a monotonic `now` (plan P2) and performs the effects it returns, in order. Panels and views hold no
/// state of their own.
@MainActor
public final class QuickAccessModel {
    public struct Entry: Hashable, Sendable, Identifiable {
        public var item: CaptureItem
        public var preview: PixelBuffer?
        public var timer: DismissTimer
        /// Seconds, from the settings at show time; nil never expires.
        public var duration: Double?
        public var isEditing: Bool

        public var id: CaptureID { item.id }
    }

    /// A Save As… whose panel is open or whose copy is running (Q17): the item follows `saved` and `moved` events.
    public struct PendingSaveAs: Hashable, Sendable {
        public var item: CaptureItem
        public var preview: PixelBuffer?
        /// The copy has started: a `deleted` of its source no longer cancels it (Q17, rule 11).
        public var isCopying = false
    }

    /// The Editor's module id (contracts §4.1.1's origins); its `created` copies get no thumbnail (Q19). Area cores
    /// can't import EditorCore (Wave 0 P14), so the value is restated here.
    public static let editorOrigin = "editor"

    public static let origin = QuickAccessModule.moduleID

    // MARK: State

    private var stack = QuickAccessStack<Entry>()
    public var entries: [Entry] { stack.items }
    public private(set) var hovered: CaptureID?
    public private(set) var selection = QuickAccessSelection()
    public private(set) var anchor: Rect2D = .zero
    public private(set) var position: QuickAccessPosition = .bottomLeft
    public private(set) var keyPanel: CaptureID?
    public private(set) var rememberedKeyWindow: WindowToken?
    public private(set) var ticking = false
    public private(set) var pendingSaveAs: [CaptureID: PendingSaveAs] = [:]
    public private(set) var bugeyeIsActive = false
    /// Ids with a Save, Save As… or Delete in progress (plan P6).
    public private(set) var busy: Set<CaptureID> = []
    /// The item of each Delete in progress, so its `deleted` is published even if the thumbnail went away (plan P7).
    private var deleting: [CaptureID: CaptureItem] = [:]
    /// The file each Copy in flight reads, so a Copy that failed because the file moved meanwhile (a Save, a `moved`)
    /// is retried once at the new place (claude-review on #10).
    private var copying: [CaptureID: URL] = [:]
    /// The item of each Save in flight, following `edited`, `moved` and `saved` events even after the thumbnail went
    /// away, so the published `saved` is never a stale copy (claude-review on #10).
    private var saving: [CaptureID: CaptureItem] = [:]
    /// Saves in flight whose capture was deleted meanwhile: their result publishes nothing, so no `saved` ever follows
    /// a `deleted` (claude-review on #10).
    private var savesOfDeleted: Set<CaptureID> = []
    private var fading: Set<CaptureID> = []
    private var loggedDecorations: Set<String> = []

    private let specs: [QuickAccessActionSpec]
    private let handler: @MainActor (String) -> QuickAccessActionHandler?
    private let decorations: @MainActor (CaptureID) -> [ThumbnailDecoration]
    private let saveTarget: @MainActor () -> QuickAccessSaveTarget
    private let makeID: @MainActor () -> CaptureID

    /// - Parameters:
    ///   - specs: the registry's Quick Access specs.
    ///   - handler: the router's handler lookup, asked at every render and action.
    ///   - decorations: `ThumbnailDecorations.decorations(for:)`.
    ///   - saveTarget: the save folder, read fresh at each Save.
    ///   - makeID: the id of a Save As… copy.
    public init(
        specs: [QuickAccessActionSpec], handler: @escaping @MainActor (String) -> QuickAccessActionHandler?,
        decorations: @escaping @MainActor (CaptureID) -> [ThumbnailDecoration],
        saveTarget: @escaping @MainActor () -> QuickAccessSaveTarget,
        makeID: @escaping @MainActor () -> CaptureID = { CaptureID() }
    ) {
        self.specs = specs
        self.handler = handler
        self.decorations = decorations
        self.saveTarget = saveTarget
        self.makeID = makeID
    }

    /// The shown item, for the drag provider and the built-in handlers.
    public func item(_ id: CaptureID) -> CaptureItem? {
        entry(id)?.item
    }

    // MARK: Events

    public func handle(_ event: QuickAccessEvent, at now: Double) -> [QuickAccessEffect] {
        var out: [QuickAccessEffect] = []
        switch event {
        case .bus(let captureEvent, let anchor, let settings):
            follow(captureEvent, anchor: anchor, settings: settings, now: now, &out)
        case .tick:
            let expired = entries.filter { $0.timer.isExpired(at: now) }.map(\.id)
            for id in expired { dismiss(id, .expired, now: now, relayout: false, &out) }
            if !expired.isEmpty { relayout(&out) }
        case .hoverBegan(let id, let window):
            guard isShown(id) else { break }
            hovered = id
            if let window { rememberedKeyWindow = window }
            syncTimers(now)
            out.append(.makeKey(id))
            keyPanel = id
        case .hoverEnded(let id, let active):
            bugeyeIsActive = active
            guard isShown(id) else { break }
            if hovered == id { hovered = nil }
            syncTimers(now)
            if keyPanel == id { returnFocus(&out) }
        case .appActiveChanged(let active):
            bugeyeIsActive = active
        case .imageClicked(let id, let shift):
            guard let entry = entry(id) else { break }
            if shift {
                guard entry.item.kind == .screenshot else { break }
                selection.toggle(id)
                if selection.isEmpty { restartAfterSelection(now) } else { syncTimers(now) }
                renderAll(&out)
            } else if !selection.isEmpty {
                clearSelection(now, &out)
            }
        case .imageDoubleClicked(let id):
            guard let entry = entry(id), let primary = primarySpec(for: entry.item.kind),
                let found = handler(primary.id), found.state(entry.item) != .disabled
            else { break }
            runOther(primary.id, on: entry, trigger: .doubleClick, subitemID: nil, &out)
        case .escape(let id):
            guard isShown(id) else { break }
            if selection.isEmpty {
                dismiss(id, .escape, now: now, &out)
            } else {
                clearSelection(now, &out)
            }
        case .closeTapped(let id):
            guard isShown(id) else { break }
            dismiss(id, .close, now: now, &out)
        case .stripTapped(let id, let slot):
            guard let entry = entry(id) else { break }
            switch slot {
            case .copy: run(QuickAccessActionID.copy, on: entry, trigger: .strip, subitemID: nil, now: now, &out)
            case .save:
                let action = entry.item.isSaved ? QuickAccessActionID.saveAs : QuickAccessActionID.save
                run(action, on: entry, trigger: .strip, subitemID: nil, now: now, &out)
            case .primary:
                guard let primary = primarySpec(for: entry.item.kind) else { break }
                if let found = handler(primary.id), found.state(entry.item) == .disabled { break }
                run(primary.id, on: entry, trigger: .strip, subitemID: nil, now: now, &out)
            case .selection:
                runSelectionAction(now, &out)
            }
        case .menuChosen(let id, let actionID, let subitemID):
            guard let entry = entry(id) else { break }
            run(actionID, on: entry, trigger: .menu, subitemID: subitemID, now: now, &out)
        case .decorationTapped(let id, let actionID):
            guard let entry = entry(id) else { break }
            run(actionID, on: entry, trigger: .decoration, subitemID: nil, now: now, &out)
        case .selectionActionTapped:
            runSelectionAction(now, &out)
        case .decorationsChanged(let id):
            guard isShown(id) else { break }
            render(id, &out)
        case .fileActionFinished(let id, let result):
            finished(id, result, now: now, &out)
        case .saveAsChosen(let id, let url):
            saveAsChosen(id, url, &out)
        case .fadeOutFinished(let id):
            if fading.remove(id) != nil { out.append(.closePanel(id)) }
        }
        return out
    }

    // MARK: Rule 1 and rule 9: the bus

    private func follow(
        _ event: CaptureEvent, anchor: Rect2D?, settings: QuickAccessSettings?, now: Double,
        _ out: inout [QuickAccessEffect]
    ) {
        let id = event.item.id
        switch event.change {
        case .saved, .moved:
            if pendingSaveAs[id] != nil { pendingSaveAs[id]?.item = event.item }
            if saving[id] != nil { saving[id] = event.item }
        case .edited:
            if saving[id] != nil { saving[id] = event.item }
        case .deleted:
            cancelSaveAsUnlessCopying(id)
            deleting[id] = nil  // someone else published it; a Delete finishing later publishes nothing more
            if saving.removeValue(forKey: id) != nil { savesOfDeleted.insert(id) }
        default:
            break
        }

        if event.change == .created {
            guard event.origin != Self.origin, event.origin != Self.editorOrigin, !isShown(id) else { return }
            show(event, anchor: anchor ?? self.anchor, settings: settings ?? QuickAccessSettings(), now: now, &out)
            return
        }
        guard var entry = entry(id) else { return }
        switch event.change {
        case .saved, .moved:
            entry.item = event.item
            update(entry)
            render(id, &out)
        case .edited:
            entry.item = event.item
            if let preview = event.preview {
                entry.preview = preview
                pendingSaveAs[id]?.preview = preview  // the copy carries the thumbnail's preview (review of #10, M3)
            }
            update(entry)
            render(id, &out)
        case .deleted:
            dismiss(id, .deleted, now: now, &out)
        case .editingStarted:
            entry.isEditing = true
            update(entry)
            syncTimers(now)
            render(id, &out)
        case .editingEnded:
            entry.isEditing = false
            update(entry)
            syncTimers(now)
            render(id, &out)
        default:
            render(id, &out)
        }
    }

    private func show(
        _ event: CaptureEvent, anchor: Rect2D, settings: QuickAccessSettings, now: Double,
        _ out: inout [QuickAccessEffect]
    ) {
        let id = event.item.id
        var timer = DismissTimer(duration: settings.duration, startedAt: now)
        if !selection.isEmpty { timer.pause(at: now) }
        self.anchor = anchor
        position = settings.position
        let entry = Entry(
            item: event.item, preview: event.preview, timer: timer, duration: settings.duration, isEditing: false)
        let evicted = stack.push(entry, limit: QuickAccessStack<Entry>.limit(height: anchor.height), sparing: hovered)
        for gone in evicted { forget(gone.id, .evicted, now: now, &out) }
        let frames = frames()
        out.append(.showPanel(id, frame: frames[id] ?? .zero))
        render(id, &out)
        out.append(.fadeIn(id))
        out.append(.layout(frames, animated: true))
        out.append(.log("show \(id) stack \(entries.count)"))
        if !ticking {
            ticking = true
            out.append(.startTicker)
        }
    }

    // MARK: Rules 4, 5, 7, 8: timers, focus, selection, dismissal

    private func shouldRun(_ entry: Entry) -> Bool {
        hovered != entry.id && !entry.isEditing && selection.isEmpty
    }

    /// Pauses or resumes each timer to match rule 4's predicate.
    private func syncTimers(_ now: Double) {
        for var entry in entries {
            if shouldRun(entry) { entry.timer.resume(at: now) } else { entry.timer.pause(at: now) }
            update(entry)
        }
    }

    /// The selection emptied: every timer restarts with its full duration, except the hovered and editing ones.
    private func restartAfterSelection(_ now: Double) {
        for var entry in entries {
            if shouldRun(entry) {
                entry.timer.restart(duration: entry.duration, at: now)
            } else {
                entry.timer.pause(at: now)
            }
            update(entry)
        }
    }

    private func clearSelection(_ now: Double, _ out: inout [QuickAccessEffect]) {
        selection.clear()
        restartAfterSelection(now)
        renderAll(&out)
    }

    private func returnFocus(_ out: inout [QuickAccessEffect]) {
        if bugeyeIsActive, let window = rememberedKeyWindow {
            out.append(.restoreKey(window))
        } else {
            out.append(.activateFrontmostApp)
        }
        keyPanel = nil
        rememberedKeyWindow = nil
    }

    private func dismiss(
        _ id: CaptureID, _ reason: DismissReason, now: Double, relayout shouldRelayout: Bool = true,
        _ out: inout [QuickAccessEffect]
    ) {
        guard stack.remove(id) != nil else { return }
        forget(id, reason, now: now, &out)
        if shouldRelayout { relayout(&out) }
    }

    /// Rule 8 for an entry already out of the stack.
    private func forget(_ id: CaptureID, _ reason: DismissReason, now: Double, _ out: inout [QuickAccessEffect]) {
        if hovered == id { hovered = nil }
        if selection.contains(id) {
            selection.remove(id)
            if selection.isEmpty { restartAfterSelection(now) }
            renderAll(&out)
        }
        if keyPanel == id { returnFocus(&out) }
        if reason == .deleted { cancelSaveAsUnlessCopying(id) }
        out.append(.log("dismiss \(id) \(reason.rawValue)"))
        out.append(.fadeOut(id))
        fading.insert(id)
    }

    private func relayout(_ out: inout [QuickAccessEffect]) {
        if !entries.isEmpty { out.append(.layout(frames(), animated: true)) }
        if entries.isEmpty, ticking {
            ticking = false
            out.append(.stopTicker)
        }
    }

    private func frames() -> [CaptureID: Rect2D] {
        QuickAccessLayout.frames(for: entries.map(\.id), anchor: anchor, position: position)
    }

    // MARK: Rule 11: actions

    /// The one dispatcher (spec §5.2): records the action, then acts on the entry's current item.
    private func run(
        _ actionID: String, on entry: Entry, trigger: QuickAccessTrigger, subitemID: String?, now: Double,
        _ out: inout [QuickAccessEffect]
    ) {
        let item = entry.item
        switch actionID {
        case QuickAccessActionID.copy:
            record(actionID, item, trigger, &out)
            copying[item.id] = item.fileURL
            out.append(.runFileAction(item.id, .readForCopy(item)))
        case QuickAccessActionID.save where !item.isSaved:
            guard !busy.contains(item.id) else { return }
            record(actionID, item, trigger, &out)
            busy.insert(item.id)
            saving[item.id] = item
            let target = saveTarget()
            out.append(.runFileAction(item.id, .save(item, folder: target.folder, displayPath: target.displayPath)))
        case QuickAccessActionID.save, QuickAccessActionID.saveAs:
            guard !busy.contains(item.id) else { return }
            record(QuickAccessActionID.saveAs, item, trigger, &out)
            busy.insert(item.id)
            pendingSaveAs[item.id] = PendingSaveAs(item: item, preview: entry.preview)
            out.append(
                .showSavePanel(
                    item.id, name: item.fileURL.lastPathComponent, directory: item.fileURL.deletingLastPathComponent()))
        case QuickAccessActionID.reveal:
            record(actionID, item, trigger, &out)
            out.append(.reveal(item.fileURL))
        case QuickAccessActionID.delete:
            guard !busy.contains(item.id) else { return }
            record(actionID, item, trigger, &out)
            busy.insert(item.id)
            deleting[item.id] = item
            out.append(item.isSaved ? .trash(item.id, item.fileURL) : .remove(item.id, item.fileURL))
        default:
            runOther(actionID, on: entry, trigger: trigger, subitemID: subitemID, &out)
        }
    }

    /// Another module's action: its handler performs it, through the controller.
    private func runOther(
        _ actionID: String, on entry: Entry, trigger: QuickAccessTrigger, subitemID: String?,
        _ out: inout [QuickAccessEffect]
    ) {
        guard handler(actionID) != nil else {
            out.append(.log("no handler for \(actionID)"))
            return
        }
        record(actionID, entry.item, trigger, &out)
        out.append(
            .perform(
                QuickAccessActionContext(
                    actionID: actionID, items: [entry.item], trigger: trigger, subitemID: subitemID)))
    }

    private func runSelectionAction(_ now: Double, _ out: inout [QuickAccessEffect]) {
        guard selection.count >= 2, let host = selection.host.flatMap(entry),
            let spec = specs.first(where: { $0.placement == .selection })
        else { return }
        guard let found = handler(spec.id) else {
            out.append(.log("no handler for \(spec.id)"))
            return
        }
        guard found.state(host.item) == .enabled || isSubmenu(found.state(host.item)) else { return }
        record(spec.id, host.item, .selection, &out)
        let items = selection.ordered(byStack: entries.map(\.id)).compactMap { self.entry($0)?.item }
        out.append(.perform(QuickAccessActionContext(actionID: spec.id, items: items, trigger: .selection)))
        clearSelection(now, &out)
    }

    private func isSubmenu(_ state: QuickAccessActionState) -> Bool {
        if case .submenu = state { return true }
        return false
    }

    private func record(
        _ actionID: String, _ item: CaptureItem, _ trigger: QuickAccessTrigger, _ out: inout [QuickAccessEffect]
    ) {
        out.append(
            .recordActivity(
                PerformedQuickAccessAction(actionID: actionID, captureID: item.id, kind: item.kind, trigger: trigger)))
    }

    private func saveAsChosen(_ id: CaptureID, _ url: URL?, _ out: inout [QuickAccessEffect]) {
        guard let pending = pendingSaveAs[id] else {
            busy.remove(id)  // a `deleted` event cancelled it (final review of #10, M1)
            return
        }
        guard let url, url.standardizedFileURL.path != pending.item.fileURL.standardizedFileURL.path else {
            pendingSaveAs[id] = nil
            busy.remove(id)
            return
        }
        pendingSaveAs[id]?.isCopying = true
        out.append(.runFileAction(id, .saveAs(pending.item, to: url, newID: makeID())))
    }

    private func finished(
        _ id: CaptureID, _ result: QuickAccessFileResult, now: Double, _ out: inout [QuickAccessEffect]
    ) {
        switch result {
        case .copied(let payload):
            copying[id] = nil
            if isShown(id) { out.append(.copy(payload)) }
        case .copyFailed(let name):
            let requested = copying.removeValue(forKey: id)
            guard let current = entry(id)?.item else { return }
            if let requested, requested != current.fileURL {
                out.append(.runFileAction(id, .readForCopy(current)))  // retried once: `copying` is now empty
                return
            }
            fail("copy", id, QuickAccessStrings.copyFailedTitle, QuickAccessStrings.copyFailedBody(name: name), &out)
        case .saved(let moved, let previousURL):
            busy.remove(id)
            if savesOfDeleted.remove(id) != nil {
                out.append(.log("saved \(moved.fileURL.lastPathComponent) after its capture was deleted"))
                return
            }
            // Only the file's place comes from the result; everything else is the item as it is now (contracts
            // §4.1.1: never publish a stale copy; final review of #10, M2).
            var item = saving.removeValue(forKey: id) ?? moved
            item.fileURL = moved.fileURL
            item.isSaved = moved.isSaved
            if var entry = entry(id) {
                entry.item.fileURL = moved.fileURL
                entry.item.isSaved = moved.isSaved
                item = entry.item
                update(entry)
                render(id, &out)
            }
            out.append(.log("saved \(item.fileURL.lastPathComponent)"))
            out.append(
                .publish(CaptureEvent(change: .saved, item: item, previousURL: previousURL, origin: Self.origin)))
        case .saveFolderUnavailable(let path):
            busy.remove(id)
            saving[id] = nil
            savesOfDeleted.remove(id)
            fail(
                "save", id, QuickAccessStrings.saveFailedTitle, QuickAccessStrings.folderUnavailableBody(path: path),
                logged: "the save folder is unavailable", &out)
        case .saveFailed(let text):
            busy.remove(id)
            saving[id] = nil
            savesOfDeleted.remove(id)
            fail("save", id, QuickAccessStrings.saveFailedTitle, text, &out)
        case .savedCopy(let copy):
            busy.remove(id)
            let preview = pendingSaveAs.removeValue(forKey: id)?.preview
            out.append(.log("saved \(copy.fileURL.lastPathComponent)"))
            out.append(.publish(CaptureEvent(change: .created, item: copy, preview: preview, origin: Self.origin)))
        case .saveAsUnchanged:
            busy.remove(id)
            pendingSaveAs[id] = nil
        case .saveAsFailed(let text):
            busy.remove(id)
            pendingSaveAs[id] = nil
            fail("saveAs", id, QuickAccessStrings.saveAsFailedTitle, text, &out)
        case .deleted:
            busy.remove(id)
            pendingSaveAs[id] = nil
            let item = entry(id)?.item ?? deleting[id]
            deleting[id] = nil
            dismiss(id, .deleted, now: now, &out)
            if let item { out.append(.publish(CaptureEvent(change: .deleted, item: item, origin: Self.origin))) }
        case .deleteFailed(let text):
            busy.remove(id)
            deleting[id] = nil
            fail("delete", id, QuickAccessStrings.deleteFailedTitle, text, &out)
        }
    }

    /// A `deleted` cancels a Save As… whose panel is open, not one whose copy is running (claude-review on #10).
    private func cancelSaveAsUnlessCopying(_ id: CaptureID) {
        if pendingSaveAs[id]?.isCopying != true { pendingSaveAs[id] = nil }
    }

    /// `logged` replaces `body` in the log when the body names a folder: spec §7 logs file names only.
    private func fail(
        _ action: String, _ id: CaptureID, _ title: String, _ body: String, logged: String? = nil,
        _ out: inout [QuickAccessEffect]
    ) {
        out.append(.log("failed \(action) \(id): \(logged ?? body)"))
        out.append(.notify(title: title, body: body))
    }

    // MARK: Rendering

    private func primarySpec(for kind: CaptureKind) -> QuickAccessActionSpec? {
        specs.first { $0.placement == .primary && $0.kinds.contains(kind) }
    }

    private func renderAll(_ out: inout [QuickAccessEffect]) {
        for entry in entries { render(entry.id, &out) }
    }

    private func render(_ id: CaptureID, _ out: inout [QuickAccessEffect]) {
        guard let entry = entry(id) else { return }
        let output = ThumbnailStateBuilder.build(
            item: entry.item, preview: entry.preview, isSelected: selection.contains(id),
            selectionHostCount: selection.host == id ? selection.count : nil, specs: specs, handler: handler,
            decorations: decorations(id))
        for name in output.ignoredDecorations where loggedDecorations.insert("\(id) \(name)").inserted {
            out.append(.log("decoration ignored \(name)"))
        }
        out.append(.render(id, output.state))
    }

    // MARK: Helpers

    private func isShown(_ id: CaptureID) -> Bool {
        entries.contains { $0.id == id }
    }

    private func entry(_ id: CaptureID) -> Entry? {
        entries.first { $0.id == id }
    }

    private func update(_ entry: Entry) {
        stack.replace(entry)
    }
}
