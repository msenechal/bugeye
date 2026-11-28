import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore

/// A model with test-controlled specs, handlers, decorations, save folder and ids.
@MainActor
final class ModelHarness {
    static let laptop = Rect2D(x: 0, y: 25, width: 1512, height: 920)  // fits 4
    static let edit = QuickAccessActionSpec(
        id: "editor.edit", title: "Edit", order: 0, placement: .primary, kinds: [.screenshot])
    static let copyText = QuickAccessActionSpec(id: "text.copy", title: "Copy Text", order: 100, kinds: [.screenshot])
    static let combine = QuickAccessActionSpec(
        id: "collections.combine", title: "Combine", order: 0, placement: .selection, kinds: [.screenshot])

    var specs: [QuickAccessActionSpec]
    var handlers: [String: QuickAccessActionHandler] = [:]
    var decorations: [CaptureID: [ThumbnailDecoration]] = [:]
    var saveTarget = QuickAccessSaveTarget(
        folder: URL(fileURLWithPath: "/Users/me/Pictures/Bugeye", isDirectory: true), displayPath: "~/Pictures/Bugeye/")
    var nextIDs: [CaptureID] = []
    private(set) var model: QuickAccessModel!

    init(extraSpecs: [QuickAccessActionSpec] = [], handled: [String] = []) {
        specs = [QuickAccessModule.revealSpec, QuickAccessModule.deleteSpec] + extraSpecs
        for id in [QuickAccessActionID.reveal, QuickAccessActionID.delete] + handled {
            handlers[id] = QuickAccessActionHandler(perform: { _ in })
        }
        model = QuickAccessModel(
            specs: specs, handler: { [unowned self] in self.handlers[$0] },
            decorations: { [unowned self] in self.decorations[$0] ?? [] },
            saveTarget: { [unowned self] in self.saveTarget },
            makeID: { [unowned self] in self.nextIDs.isEmpty ? CaptureID() : self.nextIDs.removeFirst() })
    }

    func item(_ kind: CaptureKind = .screenshot, saved: Bool = false, name: String? = nil) -> CaptureItem {
        let folder = saved ? "/Users/me/Pictures/Bugeye" : "/Users/me/Library/Caches/dev.msenechal.bugeye/Captures"
        let file = name ?? "\(kind.namePrefix) \(UUID().uuidString.prefix(8)).\(kind.fileExtension)"
        return CaptureItem(
            id: CaptureID(), fileURL: URL(fileURLWithPath: "\(folder)/\(file)"), isSaved: saved, kind: kind,
            createdAt: Date(timeIntervalSince1970: 1_795_784_592), pixelsPerPoint: 2)
    }

    @discardableResult
    func handle(_ event: QuickAccessEvent, at now: Double = 0) -> [QuickAccessEffect] {
        model.handle(event, at: now)
    }

    @discardableResult
    func show(
        _ item: CaptureItem, at now: Double = 0, anchor: Rect2D = ModelHarness.laptop,
        settings: QuickAccessSettings = QuickAccessSettings(), origin: String = "capture", preview: PixelBuffer? = nil
    ) -> [QuickAccessEffect] {
        handle(
            .bus(
                CaptureEvent(change: .created, item: item, preview: preview, origin: origin), anchor: anchor,
                settings: settings), at: now)
    }

    func publish(
        _ change: CaptureChange, _ item: CaptureItem, previous: URL? = nil, preview: PixelBuffer? = nil,
        origin: String = "editor", at now: Double = 0
    ) -> [QuickAccessEffect] {
        handle(
            .bus(
                CaptureEvent(change: change, item: item, previousURL: previous, preview: preview, origin: origin),
                anchor: nil, settings: nil), at: now)
    }

    var shown: [CaptureID] { model.entries.map(\.item.id) }

    func entry(_ id: CaptureID) -> QuickAccessModel.Entry? { model.entries.first { $0.item.id == id } }

    func timerRunning(_ id: CaptureID) -> Bool { entry(id)?.timer.isRunning ?? false }
}

extension [QuickAccessEffect] {
    var published: [CaptureEvent] {
        compactMap { if case .publish(let event) = $0 { event } else { nil } }
    }
    var notices: [String] {
        compactMap { if case .notify(let title, let body) = $0 { "\(title) | \(body)" } else { nil } }
    }
    var logs: [String] {
        compactMap { if case .log(let line) = $0 { line } else { nil } }
    }
    var fileActions: [QuickAccessFileAction] {
        compactMap { if case .runFileAction(_, let action) = $0 { action } else { nil } }
    }
    var performed: [QuickAccessActionContext] {
        compactMap { if case .perform(let context) = $0 { context } else { nil } }
    }
    var recorded: [PerformedQuickAccessAction] {
        compactMap { if case .recordActivity(let action) = $0 { action } else { nil } }
    }
    var renders: [CaptureID: ThumbnailState] {
        var states: [CaptureID: ThumbnailState] = [:]
        for case .render(let id, let state) in self { states[id] = state }
        return states
    }
    var layouts: [[CaptureID: Rect2D]] {
        compactMap { if case .layout(let frames, _) = $0 { frames } else { nil } }
    }
    func contains(_ effect: QuickAccessEffect) -> Bool { contains(where: { $0 == effect }) }
}
