import BugeyeCore
import BugeyeFeatures
import Foundation
import Testing

@MainActor @Suite struct ThumbnailDecorationsTests {
    let bus = CaptureEventBus()
    let id = CaptureID()
    let other = CaptureID()

    func deleted(_ id: CaptureID) -> CaptureEvent {
        CaptureEvent(
            change: .deleted,
            item: CaptureItem(
                id: id, fileURL: URL(fileURLWithPath: "/tmp/a.png"), isSaved: false, kind: .screenshot,
                createdAt: Date(), pixelsPerPoint: 2),
            origin: "quickAccess")
    }

    @Test func setReplacesAProvidersDecorations() {
        let decorations = ThumbnailDecorations(bus: bus)
        decorations.set([.mediaBadge(text: "▶ 00:01")], for: id, from: "recording")
        decorations.set([.mediaBadge(text: "▶ 00:42")], for: id, from: "recording")
        #expect(decorations.decorations(for: id) == [.mediaBadge(text: "▶ 00:42")])
        #expect(decorations.decorations(for: other) == [])
    }

    @Test func providersAppearInFirstSetOrder() {
        let decorations = ThumbnailDecorations(bus: bus)
        decorations.set([.suggestedAction(actionID: "editor.edit")], for: id, from: "habits")
        decorations.set([.mediaBadge(text: "GIF")], for: id, from: "recording")
        decorations.set([.suggestedAction(actionID: "quickAccess.save")], for: id, from: "habits")
        #expect(
            decorations.decorations(for: id) == [
                .suggestedAction(actionID: "quickAccess.save"), .mediaBadge(text: "GIF"),
            ])
    }

    @Test func anEmptySetRemovesTheProvider() {
        let decorations = ThumbnailDecorations(bus: bus)
        decorations.set([.mediaBadge(text: "GIF")], for: id, from: "recording")
        decorations.set(
            [.warningBadge(text: "Secrets", tooltip: nil, actionID: nil)], for: id, from: "sweep")
        decorations.set([], for: id, from: "recording")
        #expect(decorations.decorations(for: id) == [.warningBadge(text: "Secrets", tooltip: nil, actionID: nil)])
        decorations.set([.mediaBadge(text: "GIF")], for: id, from: "recording")
        #expect(decorations.decorations(for: id).last == .mediaBadge(text: "GIF"))
    }

    @Test func observersHearEverySet() {
        let decorations = ThumbnailDecorations(bus: bus)
        var heard: [CaptureID] = []
        decorations.observe { heard.append($0) }
        decorations.set([.mediaBadge(text: "GIF")], for: id, from: "recording")
        decorations.set([], for: other, from: "recording")
        #expect(heard == [id, other])
    }

    @Test func aDeletedCaptureLosesEveryProvidersDecorations() {
        let decorations = ThumbnailDecorations(bus: bus)
        var heard: [CaptureID] = []
        decorations.set([.mediaBadge(text: "GIF")], for: id, from: "recording")
        decorations.set([.sourceChip(label: "Arc", appBundleID: nil, actionID: nil)], for: id, from: "provenance")
        decorations.set([.mediaBadge(text: "GIF")], for: other, from: "recording")
        decorations.observe { heard.append($0) }
        bus.publish(deleted(id))
        #expect(decorations.decorations(for: id) == [])
        #expect(decorations.decorations(for: other) == [.mediaBadge(text: "GIF")])
        #expect(heard == [id])
    }

    @Test func handlersDefaultToEnabled() {
        let handler = QuickAccessActionHandler(perform: { _ in })
        let item = CaptureItem(
            id: id, fileURL: URL(fileURLWithPath: "/tmp/a.png"), isSaved: false, kind: .screenshot,
            createdAt: Date(), pixelsPerPoint: 2)
        #expect(handler.state(item) == .enabled)
        let context = QuickAccessActionContext(actionID: "a", items: [item], trigger: .strip)
        #expect(context.subitemID == nil)
    }
}
