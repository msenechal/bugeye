import AppKit
import BugeyeCore
import BugeyeFeatures
import MacAdapters
import QuickAccessCore
import SwiftUI
import os

/// Feeds the model and performs its effects (spec §7): the bus subscription, the display under the pointer,
/// settings read fresh, the 0.5 s ticker, panels, file work off the main actor, Trash, Reveal, the save panel,
/// focus, logging. It owns no stack state: the model does.
@MainActor
final class QuickAccessController {
    struct Host {
        let panel: QuickAccessPanel
        var hosting: NSHostingView<ThumbnailView>?
    }

    static let fadeInDuration = 0.18
    static let fadeOutDuration = 0.15
    static let slideDuration = 0.18
    static let tickInterval = 0.5

    let model: QuickAccessModel
    private(set) var hosts: [CaptureID: Host] = [:]
    private let bus: CaptureEventBus
    private let router: ActionRouter
    private let clipboard: any ClipboardWriter
    private let notifier: any Notifier
    private let settingsStore: any SettingsStore
    private let fileActions: QuickAccessFileActions
    private let activity: QuickAccessActivity
    private let system: QuickAccessSystem
    private let animated: Bool
    private let clock: @MainActor () -> Double
    private let log = Logger(subsystem: CaptureFolders.bundleID, category: "quickAccess")
    private var subscription: CaptureSubscription?
    private var ticker: Timer?
    private var queue: [QuickAccessEvent] = []
    private var handling = false
    private var images: [CaptureID: (preview: PixelBuffer, image: CGImage)] = [:]
    private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - animated: false in tests: fades finish at once (plan P17).
    init(
        bus: CaptureEventBus, router: ActionRouter, specs: [QuickAccessActionSpec],
        decorations: ThumbnailDecorations, clipboard: any ClipboardWriter, notifier: any Notifier,
        settingsStore: any SettingsStore, fileWriter: CaptureFileWriter, activity: QuickAccessActivity,
        saveTarget: @escaping @MainActor () -> QuickAccessSaveTarget, system: QuickAccessSystem = QuickAccessSystem(),
        animated: Bool = true, clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.bus = bus
        self.router = router
        self.clipboard = clipboard
        self.notifier = notifier
        self.settingsStore = settingsStore
        fileActions = QuickAccessFileActions(writer: fileWriter)
        self.activity = activity
        self.system = system
        self.animated = animated
        self.clock = clock
        model = QuickAccessModel(
            specs: specs, handler: { [weak router] in router?.quickAccessHandler(for: $0) },
            decorations: { [weak decorations] in decorations?.decorations(for: $0) ?? [] }, saveTarget: saveTarget)
        subscription = bus.subscribe { [weak self] in self?.receive($0) }
        decorations.observe { [weak self] in self?.handle(.decorationsChanged($0)) }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.handle(.appActiveChanged(true)) }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.handle(.appActiveChanged(false)) }
            },
        ]
    }

    /// Stops the ticker and the activation observers (final review of #11, M2 and M3). The app keeps its
    /// controller for its life; tests let theirs go.
    isolated deinit {
        ticker?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Input

    /// Events from the views and effects. Queued while another is being handled, so effects run in the order the
    /// model returned them (plan P16).
    func handle(_ event: QuickAccessEvent) {
        queue.append(event)
        guard !handling else { return }
        handling = true
        defer { handling = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            for effect in model.handle(next, at: clock()) { perform(effect) }
        }
    }

    func hover(_ id: CaptureID, inside: Bool) {
        if inside {
            handle(.hoverBegan(id, bugeyeKeyWindow: system.bugeyeKeyWindow()))
        } else {
            handle(.hoverEnded(id, bugeyeIsActive: system.bugeyeIsActive()))
        }
    }

    /// The capture's current file, for the drag provider.
    func currentURL(_ id: CaptureID) -> URL? {
        model.item(id)?.fileURL
    }

    /// The built-in Reveal in Finder and Delete, when another module runs them through the router (plan P4).
    func runBuiltIn(_ context: QuickAccessActionContext) {
        for item in context.items {
            handle(.menuChosen(item.id, actionID: context.actionID, subitemID: context.subitemID))
        }
    }

    private func receive(_ event: CaptureEvent) {
        if event.change == .created {
            handle(
                .bus(
                    event, anchor: system.anchorUnderPointer(), settings: QuickAccessSettings.load(from: settingsStore))
            )
        } else {
            handle(.bus(event, anchor: nil, settings: nil))
        }
    }

    // MARK: Effects

    private func perform(_ effect: QuickAccessEffect) {
        switch effect {
        case .showPanel(let id, let frame):
            let panel = QuickAccessPanel(frame: Self.rect(frame))
            panel.onEscape = { [weak self] in self?.handle(.escape(id)) }
            // Invisible until `.fadeIn`, which follows the first render, so a panel is never seen empty (claude-review).
            panel.alphaValue = 0
            hosts[id] = Host(panel: panel, hosting: nil)
            panel.orderFrontRegardless()
        case .fadeIn(let id):
            guard let panel = hosts[id]?.panel else { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeInDuration
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
            }
        case .fadeOut(let id):
            guard let panel = hosts[id]?.panel else { return handle(.fadeOutFinished(id)) }
            panel.onEscape = nil
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeOutDuration
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated { self?.handle(.fadeOutFinished(id)) }
                }
            } else {
                panel.alphaValue = 0
                handle(.fadeOutFinished(id))
            }
        case .closePanel(let id):
            images[id] = nil
            guard let host = hosts.removeValue(forKey: id) else { return }
            host.panel.onEscape = nil
            host.panel.contentView = nil
            host.panel.close()
        case .layout(let frames, let slide):
            for (id, frame) in frames {
                guard let panel = hosts[id]?.panel else { continue }
                let rect = Self.rect(frame)
                guard panel.frame != rect else { continue }
                if animated && slide {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = Self.slideDuration
                        panel.animator().setFrame(rect, display: true)
                    }
                } else {
                    panel.setFrame(rect, display: true)
                }
            }
        case .render(let id, let state):
            guard var host = hosts[id] else { return }
            let view = ThumbnailView(
                state: state, image: image(id, state.preview), actions: ThumbnailActions(id: id, controller: self))
            if let hosting = host.hosting {
                hosting.rootView = view
            } else {
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(origin: .zero, size: host.panel.frame.size)
                host.panel.contentView = hosting
                host.hosting = hosting
                hosts[id] = host
            }
        case .makeKey(let id):
            hosts[id]?.panel.makeKey()
        case .restoreKey(let token):
            if !system.restoreKey(token) { system.activateFrontmostApp() }
        case .activateFrontmostApp:
            system.activateFrontmostApp()
        case .startTicker:
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.tick) }
            }
        case .stopTicker:
            ticker?.invalidate()
            ticker = nil
        case .copy(let payload):
            do {
                try clipboard.write(payload)
            } catch {
                // Plan P13: the Copy notice is the closest settled text.
                let name = payload.fileURL?.lastPathComponent ?? ""
                // The error's text, never its userInfo (which can hold paths): spec §7 (final review of #11, M4).
                log.error("failed copy \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                notifier.post(
                    title: QuickAccessStrings.copyFailedTitle, body: QuickAccessStrings.copyFailedBody(name: name))
            }
        case .runFileAction(let id, let action):
            let actions = fileActions
            Task.detached { [weak self] in
                let result = actions.run(action)
                await self?.handle(.fileActionFinished(id, result))
            }
        case .trash(let id, let url):
            delete(id, url, using: system.trash)
        case .remove(let id, let url):
            delete(id, url, using: system.remove)
        case .reveal(let url):
            system.reveal(url)
        case .showSavePanel(let id, let name, let directory):
            system.showSavePanel(name, directory) { [weak self] url in self?.handle(.saveAsChosen(id, url)) }
        case .perform(let context):
            if let handler = router.quickAccessHandler(for: context.actionID) {
                handler.perform(context)
            } else {
                log.error("no handler for \(context.actionID, privacy: .public)")
            }
        case .recordActivity(let action):
            activity.record(action)
        case .publish(let event):
            bus.publish(event)
        case .notify(let title, let body):
            notifier.post(title: title, body: body)
        case .log(let line):
            log.info("\(line, privacy: .public)")
        }
    }

    private func delete(_ id: CaptureID, _ url: URL, using remove: @escaping @Sendable (URL) throws -> Void) {
        Task.detached { [weak self] in
            let result = QuickAccessFileActions.delete(url, using: remove)
            await self?.handle(.fileActionFinished(id, result))
        }
    }

    /// The preview as a `CGImage`, converted once per preview.
    private func image(_ id: CaptureID, _ preview: PixelBuffer?) -> CGImage? {
        guard let preview else {
            images[id] = nil
            return nil
        }
        if let cached = images[id], cached.preview == preview { return cached.image }
        guard let image = PixelBufferImages.cgImage(preview) else { return nil }
        images[id] = (preview, image)
        return image
    }

    static func rect(_ frame: Rect2D) -> NSRect {
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }
}
