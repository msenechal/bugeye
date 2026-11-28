import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore
import Testing

/// Rules 1–4: show, fit, layout, timers.
@MainActor
@Suite struct QuickAccessModelShowTests {
    @Test func rule1_aCreatedCaptureShowsAThumbnail() throws {
        let h = ModelHarness()
        let item = h.item()
        let preview = try PixelBuffer(width: 2, height: 2, fill: RGBA8(red: 1, green: 2, blue: 3))
        let effects = h.show(item, at: 10, preview: preview)
        #expect(h.shown == [item.id])
        let frame = Rect2D(x: 16, y: 41, width: 240, height: 176)
        #expect(effects.first == .showPanel(item.id, frame: frame))
        #expect(effects.renders[item.id]?.preview == preview)
        #expect(effects.contains(.fadeIn(item.id)))
        #expect(effects.layouts == [[item.id: frame]])
        #expect(effects.contains(.startTicker))
        #expect(effects.logs == ["show \(item.id) stack 1"])
        #expect(h.entry(item.id)?.timer == DismissTimer(duration: 5, startedAt: 10))
    }

    @Test func rule1_copiesFromQuickAccessAndTheEditorGetNoThumbnail() {
        let h = ModelHarness()
        #expect(h.show(h.item(), origin: "quickAccess").isEmpty)
        #expect(h.show(h.item(), origin: "editor").isEmpty)
        #expect(h.shown.isEmpty)
        h.show(h.item(.recording), origin: "recording")
        #expect(h.shown.count == 1)
    }

    @Test func rule1_aRepeatedCreatedIsIgnored() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        #expect(h.show(item, at: 3).isEmpty)
        #expect(h.shown == [item.id])
    }

    @Test func rule1_theTickerStartsOnce() {
        let h = ModelHarness()
        #expect(h.show(h.item()).contains(.startTicker))
        #expect(!h.show(h.item()).contains(.startTicker))
    }

    @Test func rule1_settingsAreReadFreshAtEachShow() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a, at: 0, settings: QuickAccessSettings(autoDismissSeconds: 0, position: .bottomLeft))
        let effects = h.show(b, at: 0, settings: QuickAccessSettings(autoDismissSeconds: 60, position: .bottomRight))
        #expect(h.entry(a.id)?.timer.remaining == nil)
        #expect(h.entry(b.id)?.timer.remaining == 60)
        // A position change applies to the whole stack at the next layout.
        #expect(effects.layouts.last?[a.id]?.minX == 1256)  // 1512 − 16 − 240
    }

    @Test func rule1_aNewThumbnailIsPausedWhileASelectionExists() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        h.handle(.imageClicked(a.id, shift: true))
        let b = h.item()
        h.show(b, at: 1)
        #expect(!h.timerRunning(b.id))
    }

    @Test func rule2_theStackHoldsAtMostFive() {
        let h = ModelHarness()
        let tall = Rect2D(x: 0, y: 0, width: 2560, height: 1400)
        let items = (0..<6).map { _ in h.item() }
        var last: [QuickAccessEffect] = []
        for item in items { last = h.show(item, anchor: tall) }
        #expect(h.shown == items.dropFirst().map(\.id))
        #expect(last.contains(.fadeOut(items[0].id)))
        #expect(last.logs.contains("dismiss \(items[0].id) evicted"))
    }

    @Test func rule2_stackLimitFollowsTheVisibleHeight() {
        let h = ModelHarness()
        let items = (0..<5).map { _ in h.item() }
        for item in items { h.show(item, anchor: Rect2D(x: 0, y: 0, width: 1440, height: 850)) }
        #expect(h.shown.count == 4)
        let tiny = h.item()
        h.show(tiny, anchor: Rect2D(x: 0, y: 0, width: 800, height: 300))
        #expect(h.shown == [tiny.id])
    }

    @Test func rule2_hoveredThumbnailIsNotEvictedByANewCapture() {
        let h = ModelHarness()
        let items = (0..<4).map { _ in h.item() }
        for item in items { h.show(item) }
        h.handle(.hoverBegan(items[0].id, bugeyeKeyWindow: nil))
        h.show(h.item())
        #expect(h.shown.first == items[0].id)
        #expect(!h.shown.contains(items[1].id))
    }

    @Test func rule3_newestIsAtTheBottomAndEveryEntryFollowsTheLatestAnchor() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a)
        let external = Rect2D(x: -1920, y: -1080, width: 1920, height: 1055)
        let effects = h.show(b, anchor: external)
        #expect(
            effects.layouts.last == [
                b.id: Rect2D(x: -1904, y: -1064, width: 240, height: 176),
                a.id: Rect2D(x: -1904, y: -1064 + 186, width: 240, height: 176),
            ])
    }

    @Test func rule3_aDismissalClosesTheGap() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a)
        h.show(b)
        let effects = h.handle(.closeTapped(b.id))
        #expect(effects.layouts.last == [a.id: Rect2D(x: 16, y: 41, width: 240, height: 176)])
    }

    @Test func rule4_aTimerExpiresAtItsDuration() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item, at: 100)
        #expect(h.handle(.tick, at: 104.5).isEmpty)
        let effects = h.handle(.tick, at: 105)
        #expect(effects.contains(.fadeOut(item.id)))
        #expect(effects.logs.contains("dismiss \(item.id) expired"))
        #expect(effects.contains(.stopTicker))
        #expect(h.shown.isEmpty)
    }

    @Test func rule4_neverDoesNotExpire() {
        let h = ModelHarness()
        h.show(h.item(), settings: QuickAccessSettings(autoDismissSeconds: 0))
        #expect(h.handle(.tick, at: 1_000_000).isEmpty)
        #expect(h.shown.count == 1)
    }

    @Test func rule4_hoverBanksTheTime() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item, at: 0)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil), at: 2)
        h.handle(.tick, at: 100)
        #expect(h.shown == [item.id])
        h.handle(.hoverEnded(item.id, bugeyeIsActive: false), at: 100)
        #expect(h.handle(.tick, at: 102.5).isEmpty)
        #expect(h.handle(.tick, at: 103).contains(.fadeOut(item.id)))
    }

    @Test func rule4_editingPausesUntilItEnds() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item, at: 0)
        h.publish(.editingStarted, item, at: 1)
        #expect(!h.timerRunning(item.id))
        h.handle(.tick, at: 50)
        #expect(h.shown == [item.id])
        // Hover begins and ends while editing: still paused.
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil), at: 51)
        h.handle(.hoverEnded(item.id, bugeyeIsActive: false), at: 52)
        #expect(!h.timerRunning(item.id))
        h.publish(.editingEnded, item, at: 60)
        #expect(h.timerRunning(item.id))
        #expect(h.handle(.tick, at: 64).contains(.fadeOut(item.id)))
    }

    @Test func rule4_theTickerStopsWhenTheStackEmpties() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.handle(.closeTapped(item.id))
        #expect(effects.contains(.stopTicker))
        #expect(h.show(h.item()).contains(.startTicker))
    }
}
