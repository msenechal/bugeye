import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore
import Testing

/// Rules 5–8: hover, Esc, selection, dismissal.
@MainActor
@Suite struct QuickAccessModelInteractionTests {
    @Test func rule5_hoverMakesTheThumbnailKeyAndPausesIt() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil), at: 1)
        #expect(effects.contains(.makeKey(item.id)))
        #expect(h.model.hovered == item.id)
        #expect(h.model.keyPanel == item.id)
        #expect(!h.timerRunning(item.id))
    }

    @Test func keyFocusReturnsWhenThePointerLeaves() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil))
        let effects = h.handle(.hoverEnded(item.id, bugeyeIsActive: false), at: 1)
        #expect(effects.contains(.activateFrontmostApp))
        #expect(h.model.keyPanel == nil)
        #expect(h.model.hovered == nil)
        #expect(h.timerRunning(item.id))
    }

    @Test func rule5_aRememberedBugeyeWindowGetsKeyBackWhileBugeyeIsActive() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: WindowToken(42)))
        let effects = h.handle(.hoverEnded(item.id, bugeyeIsActive: true))
        #expect(effects.contains(.restoreKey(WindowToken(42))))
        #expect(!effects.contains(.activateFrontmostApp))
    }

    @Test func rule5_aRememberedWindowIsNotRestoredOnceBugeyeIsInactive() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: WindowToken(42)))
        let effects = h.handle(.hoverEnded(item.id, bugeyeIsActive: false))
        #expect(effects.contains(.activateFrontmostApp))
    }

    @Test func rule6_escDismissesTheKeyThumbnailAndReturnsFocus() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil))
        let effects = h.handle(.escape(item.id))
        #expect(effects.contains(.fadeOut(item.id)))
        #expect(effects.contains(.activateFrontmostApp))
        #expect(effects.logs.contains("dismiss \(item.id) escape"))
        #expect(h.model.keyPanel == nil)
        // The pointer leaving the closed panel afterwards does nothing more.
        #expect(h.handle(.hoverEnded(item.id, bugeyeIsActive: false)).isEmpty)
    }

    @Test func escapeAsCancelOperationDismissesAndClosesTheGap() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a)
        h.show(b)
        let effects = h.handle(.escape(b.id))
        #expect(h.shown == [a.id])
        #expect(effects.layouts.last == [a.id: Rect2D(x: 16, y: 41, width: 240, height: 176)])
        #expect(!effects.contains(.closePanel(b.id)))
        #expect(h.handle(.fadeOutFinished(b.id)) == [.closePanel(b.id)])
        #expect(h.handle(.fadeOutFinished(b.id)).isEmpty)
    }

    @Test func rule6_escClearsASelectionFirst() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        h.handle(.imageClicked(a.id, shift: true))
        let effects = h.handle(.escape(a.id), at: 3)
        #expect(h.shown == [a.id])
        #expect(h.model.selection.isEmpty)
        #expect(effects.renders[a.id]?.isSelected == false)
    }

    @Test func rule7_shiftClickSelectsAndPausesEveryTimer() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a)
        h.show(b)
        let effects = h.handle(.imageClicked(a.id, shift: true), at: 1)
        #expect(h.model.selection.ids == [a.id])
        #expect(effects.renders[a.id]?.isSelected == true)
        #expect(!h.timerRunning(a.id))
        #expect(!h.timerRunning(b.id))
        h.handle(.tick, at: 100)
        #expect(h.shown == [a.id, b.id])
    }

    @Test func rule7_clearingRestartsEveryTimerButTheHoveredAndEditingOnes() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        let c = h.item()
        for item in [a, b, c] { h.show(item, at: 0) }
        h.handle(.imageClicked(a.id, shift: true), at: 4)
        h.publish(.editingStarted, b, at: 4)
        h.handle(.hoverBegan(c.id, bugeyeKeyWindow: nil), at: 4)
        h.handle(.imageClicked(c.id, shift: false), at: 20)
        #expect(h.model.selection.isEmpty)
        #expect(h.entry(a.id)?.timer == DismissTimer(duration: 5, startedAt: 20))
        #expect(!h.timerRunning(b.id))
        #expect(!h.timerRunning(c.id))
        // The hovered one kept its banked second, not a full restart.
        #expect(h.entry(c.id)?.timer.remaining == 1)
    }

    @Test func rule7_shiftClickingTheLastOneOffAlsoRestarts() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a, at: 0)
        h.handle(.imageClicked(a.id, shift: true), at: 4)
        h.handle(.imageClicked(a.id, shift: true), at: 30)
        #expect(h.entry(a.id)?.timer == DismissTimer(duration: 5, startedAt: 30))
    }

    @Test func rule7_shiftClickOnOtherKindsDoesNothing() {
        let h = ModelHarness()
        let recording = h.item(.recording)
        let gif = h.item(.gif)
        h.show(recording)
        h.show(gif)
        #expect(h.handle(.imageClicked(recording.id, shift: true)).isEmpty)
        #expect(h.handle(.imageClicked(gif.id, shift: true)).isEmpty)
        #expect(h.model.selection.isEmpty)
    }

    @Test func rule7_aPlainClickWithoutASelectionDoesNothing() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        #expect(h.handle(.imageClicked(a.id, shift: false)).isEmpty)
    }

    @Test func rule7_theHostShowsTheSelectionActionAndRunsItOldestFirst() {
        var performed: [QuickAccessActionContext] = []
        let h = ModelHarness(extraSpecs: [ModelHarness.combine], handled: [])
        h.handlers[ModelHarness.combine.id] = QuickAccessActionHandler(perform: { performed.append($0) })
        let a = h.item()
        let b = h.item()
        let c = h.item()
        for item in [a, b, c] { h.show(item) }
        h.handle(.imageClicked(c.id, shift: true))
        let effects = h.handle(.imageClicked(a.id, shift: true))
        #expect(effects.renders[a.id]?.strip.map(\.title) == ["Combine (2)"])
        #expect(effects.renders[c.id]?.strip.map(\.title) == ["Copy", "Save"])
        let run = h.handle(.selectionActionTapped, at: 9)
        #expect(
            run.performed == [
                QuickAccessActionContext(actionID: "collections.combine", items: [a, c], trigger: .selection)
            ])
        #expect(
            run.recorded == [
                PerformedQuickAccessAction(
                    actionID: "collections.combine", captureID: a.id, kind: .screenshot, trigger: .selection)
            ])
        #expect(h.model.selection.isEmpty)
        #expect(h.entry(b.id)?.timer == DismissTimer(duration: 5, startedAt: 9))
        #expect(performed.isEmpty)  // the controller performs; the model only asks
    }

    @Test func rule8_dismissingASelectedThumbnailRemovesItFromTheSelection() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a, at: 0)
        h.show(b, at: 0)
        h.handle(.imageClicked(a.id, shift: true), at: 1)
        h.handle(.closeTapped(a.id), at: 7)
        #expect(h.model.selection.isEmpty)
        #expect(h.entry(b.id)?.timer == DismissTimer(duration: 5, startedAt: 7))
    }

    @Test func rule8_closeDismissesWithoutTouchingTheFile() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        let effects = h.handle(.closeTapped(a.id))
        #expect(effects.logs == ["dismiss \(a.id) close"])
        #expect(effects.fileActions.isEmpty)
        #expect(effects.published.isEmpty)
        #expect(
            !effects.contains(where: { if case .trash = $0 { true } else if case .remove = $0 { true } else { false } })
        )
    }

    @Test func rule8_aDismissedIDProducesNoMoreEffects() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        h.handle(.closeTapped(a.id))
        #expect(h.handle(.closeTapped(a.id)).isEmpty)
        #expect(h.handle(.escape(a.id)).isEmpty)
        #expect(h.handle(.hoverBegan(a.id, bugeyeKeyWindow: nil)).isEmpty)
        #expect(h.handle(.stripTapped(a.id, .copy)).isEmpty)
        #expect(h.handle(.menuChosen(a.id, actionID: QuickAccessActionID.delete, subitemID: nil)).isEmpty)
        #expect(h.handle(.imageClicked(a.id, shift: true)).isEmpty)
        #expect(h.handle(.decorationsChanged(a.id)).isEmpty)
        #expect(h.publish(.edited, a).isEmpty)
    }

    @Test func rule8_dismissingTheKeyThumbnailWhileBugeyeIsActiveRestoresItsWindow() {
        let h = ModelHarness()
        let a = h.item()
        h.show(a)
        h.handle(.appActiveChanged(true))
        h.handle(.hoverBegan(a.id, bugeyeKeyWindow: WindowToken(7)))
        let effects = h.handle(.closeTapped(a.id))
        #expect(effects.contains(.restoreKey(WindowToken(7))))
        #expect(effects.filter { $0 == .restoreKey(WindowToken(7)) || $0 == .activateFrontmostApp }.count == 1)
    }
}
