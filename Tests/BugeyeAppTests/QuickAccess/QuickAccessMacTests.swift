import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import QuickAccessCore
import SwiftUI
import Testing

@testable import BugeyeApp

/// Records the system calls Quick Access makes.
@MainActor
final class SystemLog {
    var calls: [String] = []
    var savePanelAnswer: URL?

    func system(anchor: Rect2D) -> QuickAccessSystem {
        var system = QuickAccessSystem()
        system.trash = { _ in }
        system.remove = { _ in }
        system.reveal = { [unowned self] in self.calls.append("reveal \($0.lastPathComponent)") }
        system.activateFrontmostApp = { [unowned self] in self.calls.append("activateFrontmostApp") }
        system.restoreKey = { [unowned self] in
            self.calls.append("restoreKey \($0.rawValue)")
            return true
        }
        system.bugeyeIsActive = { false }
        system.bugeyeKeyWindow = { nil }
        system.showSavePanel = { [unowned self] name, _, completion in
            self.calls.append("savePanel \(name)")
            completion(self.savePanelAnswer)
        }
        system.anchorUnderPointer = { anchor }
        return system
    }
}

@MainActor
struct QuickAccessFixture {
    static let anchor = Rect2D(x: 0, y: 25, width: 1512, height: 920)
    let bus = CaptureEventBus()
    let router = ActionRouter()
    let decorations: ThumbnailDecorations
    let settings = InMemorySettingsStore()
    let notifier = FakeNotifier()
    let clipboard = FakeClipboard()
    let log = SystemLog()
    let controller: QuickAccessController

    init(anchor: Rect2D = QuickAccessFixture.anchor) {
        decorations = ThumbnailDecorations(bus: bus)
        controller = QuickAccessController(
            bus: bus, router: router, specs: QuickAccessModule().quickAccessActions(), decorations: decorations,
            clipboard: clipboard, notifier: notifier, settingsStore: settings,
            fileWriter: CaptureFileWriter(metadata: FakeFileMetadataStore()), activity: QuickAccessActivity(),
            saveTarget: { QuickAccessSaveTarget(folder: URL(fileURLWithPath: "/tmp/none"), displayPath: "/tmp/none") },
            system: log.system(anchor: anchor), animated: false, clock: { 0 })
        router.onQuickAccessAction(QuickAccessActionID.reveal, QuickAccessActionHandler(perform: { _ in }))
        router.onQuickAccessAction(QuickAccessActionID.delete, QuickAccessActionHandler(perform: { _ in }))
    }

    func item(saved: Bool = false, name: String = "Screenshot.png") -> CaptureItem {
        CaptureItem(
            id: CaptureID(), fileURL: URL(fileURLWithPath: "/tmp/qa/\(UUID().uuidString)/\(name)"), isSaved: saved,
            kind: .screenshot, createdAt: Date(), pixelsPerPoint: 2)
    }

    func show(_ item: CaptureItem) {
        bus.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
    }
}

@MainActor @Suite struct QuickAccessPanelTests {
    @Test func thePanelHasSpecSection4sProperties() {
        let panel = QuickAccessPanel(frame: NSRect(x: 0, y: 0, width: 240, height: 176))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.level == .statusBar)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isOpaque)
        #expect(panel.hasShadow)
        #expect(!panel.isMovable)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
        #expect(panel.appearance?.name == .darkAqua)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test func escArrivesAsKeyDown53AndAsCancelOperation() throws {
        let panel = QuickAccessPanel(frame: NSRect(x: 0, y: 0, width: 240, height: 176))
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        let esc = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
                keyCode: 53))
        panel.keyDown(with: esc)
        #expect(escapes == 1)
        panel.cancelOperation(nil)
        #expect(escapes == 2)
        panel.close()
    }
}

@MainActor @Suite struct QuickAccessControllerTests {
    @Test func aCreatedCaptureShowsOnePanelAtItsFrame() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        f.show(item)
        let host = try #require(f.controller.hosts[item.id])
        #expect(host.panel.frame == NSRect(x: 16, y: 41, width: 240, height: 176))
        #expect(host.hosting?.rootView.state.id == item.id)
        #expect(host.panel.isVisible)
        f.controller.handle(.closeTapped(item.id))
    }

    @Test func renderReplacesTheRootView() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        f.show(item)
        let hosting = try #require(f.controller.hosts[item.id]?.hosting)
        #expect(hosting.rootView.state.strip.map(\.title) == ["Copy", "Save"])
        var saved = item
        saved.isSaved = true
        saved.fileURL = URL(fileURLWithPath: "/tmp/qa/saved/Screenshot.png")
        f.bus.publish(CaptureEvent(change: .saved, item: saved, previousURL: item.fileURL, origin: "quickAccess"))
        #expect(f.controller.hosts[item.id]?.hosting === hosting)
        #expect(hosting.rootView.state.strip.map(\.title) == ["Copy", "Save As\u{2026}"])
        f.decorations.set([.mediaBadge(text: "GIF")], for: item.id, from: "test")
        #expect(hosting.rootView.state.mediaBadge == .mediaBadge(text: "GIF"))
        f.controller.handle(.closeTapped(item.id))
    }

    @Test func theDragProviderGivesTheFileAfterSave() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        f.show(item)
        let actions = try #require(f.controller.hosts[item.id]?.hosting?.rootView.actions)
        #expect(f.controller.currentURL(item.id) == item.fileURL)
        var saved = item
        saved.isSaved = true
        saved.fileURL = URL(fileURLWithPath: "/tmp/qa/saved/Screenshot.png")
        f.bus.publish(CaptureEvent(change: .saved, item: saved, previousURL: item.fileURL, origin: "quickAccess"))
        #expect(f.controller.currentURL(item.id) == saved.fileURL)
        #expect(actions.controller?.currentURL(actions.id) == saved.fileURL)
        f.controller.handle(.closeTapped(item.id))
    }

    @Test func escThroughBothPathsDismissesAndClosesTheGap() throws {
        let f = QuickAccessFixture()
        let a = f.item()
        let b = f.item()
        let c = f.item()
        f.show(a)
        f.show(b)
        f.show(c)
        let panelC = try #require(f.controller.hosts[c.id]?.panel)
        let esc = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panelC.windowNumber,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
                keyCode: 53))
        panelC.keyDown(with: esc)
        #expect(f.controller.hosts[c.id] == nil)
        #expect(!panelC.isVisible)
        #expect(f.controller.hosts[b.id]?.panel.frame.minY == 41)
        let panelB = try #require(f.controller.hosts[b.id]?.panel)
        panelB.cancelOperation(nil)
        #expect(f.controller.hosts[b.id] == nil)
        #expect(f.controller.hosts[a.id]?.panel.frame.minY == 41)
        f.controller.handle(.closeTapped(a.id))
    }

    @Test func hoverMakesKeyAndLeavingReturnsFocus() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        f.show(item)
        f.controller.hover(item.id, inside: true)
        f.controller.hover(item.id, inside: false)
        #expect(f.log.calls == ["activateFrontmostApp"])
        f.controller.handle(.closeTapped(item.id))
    }

    @Test func revealAndSaveAsGoThroughTheSystem() throws {
        let f = QuickAccessFixture()
        var item = f.item(saved: true, name: "Shot.png")
        item.isSaved = true
        f.show(item)
        f.controller.handle(.menuChosen(item.id, actionID: QuickAccessActionID.reveal, subitemID: nil))
        f.log.savePanelAnswer = nil
        f.controller.handle(.stripTapped(item.id, .save))
        #expect(f.log.calls == ["reveal Shot.png", "savePanel Shot.png"])
        f.controller.handle(.closeTapped(item.id))
    }

    @Test func aDebugCommandAnswersTheStack() throws {
        #if DEBUG
            let f = QuickAccessFixture()
            let a = f.item(name: "A.png")
            let b = f.item(name: "B.png")
            f.show(a)
            f.show(b)
            let commands = DebugCommands()
            DebugQuickAccessCommands.register(f.controller, in: commands)
            let answer = try #require(commands.handler(for: "quickAccess.stack")?(""))
            let first = try #require(answer.range(of: "\"file\":\"A.png\""))
            let second = try #require(answer.range(of: "\"file\":\"B.png\""))
            #expect(first.lowerBound < second.lowerBound)  // oldest first, newest last
            #expect(answer.hasPrefix("[") && answer.hasSuffix("]"))
            #expect(commands.duplicates.isEmpty)
            f.controller.handle(.closeTapped(a.id))
            f.controller.handle(.closeTapped(b.id))
        #endif
    }
}

/// No closure a panel or its view holds keeps the panel alive (spec §6.1 rule 12, `design/02` §5.8).
@MainActor @Suite struct QuickAccessLeakTests {
    @Test func evictedQuickAccessPanelIsDeallocated() throws {
        let f = QuickAccessFixture(anchor: Rect2D(x: 0, y: 0, width: 800, height: 300))
        let first = f.item()
        weak var panel: QuickAccessPanel?
        weak var hosting: NSHostingView<ThumbnailView>?
        autoreleasepool {
            f.show(first)
            panel = f.controller.hosts[first.id]?.panel
            hosting = f.controller.hosts[first.id]?.hosting
            f.show(f.item())  // a one-slot screen: the first is evicted
        }
        #expect(f.controller.hosts[first.id] == nil)
        #expect(panel == nil)
        #expect(hosting == nil)
    }

    @Test func dismissedQuickAccessPanelIsDeallocated() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        weak var panel: QuickAccessPanel?
        weak var hosting: NSHostingView<ThumbnailView>?
        autoreleasepool {
            f.show(item)
            panel = f.controller.hosts[item.id]?.panel
            hosting = f.controller.hosts[item.id]?.hosting
            f.controller.handle(.closeTapped(item.id))
        }
        #expect(panel == nil)
        #expect(hosting == nil)
    }

    @Test func escDismissedQuickAccessPanelIsDeallocated() throws {
        let f = QuickAccessFixture()
        let item = f.item()
        weak var panel: QuickAccessPanel?
        weak var hosting: NSHostingView<ThumbnailView>?
        autoreleasepool {
            f.show(item)
            panel = f.controller.hosts[item.id]?.panel
            hosting = f.controller.hosts[item.id]?.hosting
            panel?.cancelOperation(nil)
        }
        #expect(panel == nil)
        #expect(hosting == nil)
    }
}

/// Rule 12 with panels still shown: nothing a panel, its view, the ticker or an observer holds keeps the controller
/// alive (final review of #11, I1). A strong capture anywhere would make a cycle through the shown panels.
@MainActor @Suite struct QuickAccessControllerLifetimeTests {
    @Test func theControllerIsFreedWhilePanelsAreShown() throws {
        weak var controller: QuickAccessController?
        var panels: [QuickAccessPanel] = []
        autoreleasepool {
            let f = QuickAccessFixture()
            let a = f.item()
            let b = f.item()
            f.show(a)
            f.show(b)
            f.controller.hover(a.id, inside: true)  // makeKey, and the ticker is running
            controller = f.controller
            panels = f.controller.hosts.values.map(\.panel)
        }
        #expect(controller == nil)
        #expect(panels.count == 2)
        for panel in panels { panel.close() }
    }
}

@MainActor @Suite struct QuickAccessPaneTests {
    @Test func thePaneReadsAndWritesTheKeys() {
        let store = InMemorySettingsStore([QuickAccessSettings.Key.autoDismissSeconds: .int(30)])
        let model = QuickAccessPaneModel(store: store)
        #expect(model.autoDismissSeconds == 30)
        #expect(model.position == .bottomLeft)
        model.autoDismissSeconds = 0
        model.position = .bottomRight
        #expect(store.value(forKey: "quickAccess.autoDismissSeconds") == .int(0))
        #expect(store.value(forKey: "quickAccess.position") == .string("bottomRight"))
    }

    @Test func thePaneBuilds() {
        let host = NSHostingView(
            rootView: QuickAccessSettingsPane(model: QuickAccessPaneModel(store: InMemorySettingsStore())))
        #expect(host.fittingSize.width > 0)
    }
}
