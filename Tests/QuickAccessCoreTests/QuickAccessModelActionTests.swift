import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore
import Testing

/// Rules 9–11: following the bus, strip and menu, actions.
@MainActor
@Suite struct QuickAccessModelActionTests {
    func moved(_ item: CaptureItem, to path: String, saved: Bool? = nil) -> CaptureItem {
        var next = item
        next.fileURL = URL(fileURLWithPath: path)
        if let saved { next.isSaved = saved }
        return next
    }

    // MARK: Rule 9

    @Test func rule9_savedAndMovedReplaceTheItem() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let saved = moved(item, to: "/Users/me/Pictures/Bugeye/a.png", saved: true)
        let effects = h.publish(.saved, saved, previous: item.fileURL, origin: "quickAccess")
        #expect(h.entry(item.id)?.item == saved)
        #expect(effects.renders[item.id]?.strip[1].title == "Save As\u{2026}")
        let elsewhere = moved(saved, to: "/Users/me/Desktop/a.png")
        h.publish(.moved, elsewhere, previous: saved.fileURL)
        #expect(h.entry(item.id)?.item == elsewhere)
    }

    @Test func lateEventFollowsTheMovedFile() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let elsewhere = moved(item, to: "/Users/me/Desktop/a.png")
        h.publish(.moved, elsewhere, previous: item.fileURL)
        #expect(h.handle(.stripTapped(item.id, .copy)).fileActions == [.readForCopy(elsewhere)])
        #expect(h.model.item(item.id)?.fileURL == elsewhere.fileURL)
        let reveal = h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.reveal, subitemID: nil))
        #expect(reveal.contains(.reveal(elsewhere.fileURL)))
    }

    @Test func rule9_editedReplacesThePreviewWhenGiven() throws {
        let h = ModelHarness()
        let item = h.item()
        let first = try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 1, green: 1, blue: 1))
        let second = try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 9, green: 9, blue: 9))
        h.show(item, preview: first)
        #expect(h.publish(.edited, item, preview: second).renders[item.id]?.preview == second)
        #expect(h.publish(.edited, item).renders[item.id]?.preview == second)
    }

    @Test func rule9_deletedDismisses() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.publish(.deleted, item, origin: "duplicates")
        #expect(h.shown.isEmpty)
        #expect(effects.logs.contains("dismiss \(item.id) deleted"))
    }

    @Test func rule9_anUnknownChangeReRenders() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.publish(CaptureChange(rawValue: "provenanceArrived"), item)
        #expect(effects.renders[item.id] != nil)
    }

    @Test func rule9_eventsForIDsNotShownAreIgnored() {
        let h = ModelHarness()
        let item = h.item()
        #expect(h.publish(.edited, item).isEmpty)
        #expect(h.publish(.saved, item).isEmpty)
        #expect(h.publish(.deleted, item).isEmpty)
    }

    @Test func decorationsChangedReRendersWithTheNewDecorations() {
        let h = ModelHarness()
        let item = h.item(.recording)
        h.show(item)
        h.decorations[item.id] = [.mediaBadge(text: "\u{25B6} 00:42"), .mediaBadge(text: "x")]
        let effects = h.handle(.decorationsChanged(item.id))
        #expect(effects.renders[item.id]?.mediaBadge == .mediaBadge(text: "\u{25B6} 00:42"))
        #expect(effects.logs == ["decoration ignored mediaBadge"])
        #expect(h.handle(.decorationsChanged(item.id)).logs.isEmpty)
    }

    // MARK: Copy

    @Test func copyReadsOffTheMainActorThenWritesTheClipboard() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let tap = h.handle(.stripTapped(item.id, .copy))
        #expect(
            tap.recorded == [
                PerformedQuickAccessAction(
                    actionID: QuickAccessActionID.copy, captureID: item.id, kind: .screenshot, trigger: .strip)
            ])
        #expect(tap.contains(.runFileAction(item.id, .readForCopy(item))))
        let payload = ClipboardPayload(png: Data([1]), fileURL: item.fileURL)
        #expect(h.handle(.fileActionFinished(item.id, .copied(payload))) == [.copy(payload)])
    }

    @Test func aFailedCopyNotifiesAndLeavesTheTimer() {
        let h = ModelHarness()
        let item = h.item(name: "Screenshot 1.png")
        h.show(item, at: 0)
        let before = h.entry(item.id)?.timer
        let effects = h.handle(.fileActionFinished(item.id, .copyFailed(name: "Screenshot 1.png")), at: 2)
        #expect(effects.notices == ["Couldn't copy | Screenshot 1.png is missing or unreadable."])
        #expect(effects.logs == ["failed copy \(item.id): Screenshot 1.png is missing or unreadable."])
        #expect(h.entry(item.id)?.timer == before)
    }

    @Test func aCopyResultForAGoneThumbnailIsDropped() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .copy))
        h.handle(.closeTapped(item.id))
        #expect(h.handle(.fileActionFinished(item.id, .copied(ClipboardPayload(fileURL: item.fileURL)))).isEmpty)
    }

    // MARK: Save

    @Test func saveMovesIntoTheFreshSaveFolderAndPublishesSaved() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.saveTarget = QuickAccessSaveTarget(folder: URL(fileURLWithPath: "/Volumes/X"), displayPath: "/Volumes/X/")
        let tap = h.handle(.stripTapped(item.id, .save))
        #expect(tap.recorded.map(\.actionID) == [QuickAccessActionID.save])
        #expect(
            tap.fileActions == [.save(item, folder: URL(fileURLWithPath: "/Volumes/X"), displayPath: "/Volumes/X/")])
        let saved = moved(item, to: "/Volumes/X/a.png", saved: true)
        let done = h.handle(.fileActionFinished(item.id, .saved(saved, previousURL: item.fileURL)))
        #expect(
            done.published == [
                CaptureEvent(change: .saved, item: saved, previousURL: item.fileURL, origin: "quickAccess")
            ])
        #expect(done.logs == ["saved a.png"])
        #expect(done.renders[item.id]?.strip[1].title == "Save As\u{2026}")
        #expect(h.entry(item.id)?.item == saved)
    }

    @Test func aSecondSaveTapWhileOneRunsIsIgnored() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        #expect(h.handle(.stripTapped(item.id, .save)).isEmpty)
        #expect(h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil)).isEmpty)
        #expect(!h.handle(.stripTapped(item.id, .copy)).fileActions.isEmpty)
        h.handle(.fileActionFinished(item.id, .saveFailed("x")))
        #expect(!h.handle(.stripTapped(item.id, .save)).fileActions.isEmpty)
    }

    @Test func aFinishedSaveStillPublishesAfterTheThumbnailWentAway() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.closeTapped(item.id))
        let saved = moved(item, to: "/Users/me/Pictures/Bugeye/a.png", saved: true)
        let done = h.handle(.fileActionFinished(item.id, .saved(saved, previousURL: item.fileURL)))
        #expect(done.published.map(\.change) == [.saved])
        #expect(done.renders.isEmpty)
    }

    @Test func saveFailuresNotifyWithTheSettledText() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        let unavailable = h.handle(.fileActionFinished(item.id, .saveFolderUnavailable(path: "~/Pictures/Bugeye/")))
        #expect(
            unavailable.notices == [
                "Couldn't save to folder | ~/Pictures/Bugeye/ is unavailable. The capture stays in the temporary folder."
            ])
        // Spec §7: file paths other than names are never logged (final review of #11, M5).
        #expect(unavailable.logs == ["failed save \(item.id): the save folder is unavailable"])
        h.handle(.stripTapped(item.id, .save))
        let other = h.handle(
            .fileActionFinished(item.id, .saveFailed("Too many files are already named like \u{201C}a.png\u{201D}.")))
        #expect(
            other.notices == ["Couldn't save to folder | Too many files are already named like \u{201C}a.png\u{201D}."])
        #expect(other.logs == ["failed save \(item.id): Too many files are already named like \u{201C}a.png\u{201D}."])
        #expect(h.shown == [item.id])
    }

    // MARK: Save As…

    func savedItem(_ h: ModelHarness) -> CaptureItem {
        h.item(saved: true, name: "Shot.png")
    }

    @Test func saveAsOpensThePanelAtTheFile() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        let tap = h.handle(.stripTapped(item.id, .save))
        #expect(tap.recorded.map(\.actionID) == [QuickAccessActionID.saveAs])
        #expect(
            tap.contains(.showSavePanel(item.id, name: "Shot.png", directory: item.fileURL.deletingLastPathComponent()))
        )
        #expect(h.handle(.saveAsChosen(item.id, nil)).isEmpty)
        #expect(h.model.pendingSaveAs.isEmpty)
    }

    @Test func saveAsCopiesAndPublishesCreatedWithThePreview() throws {
        let h = ModelHarness()
        let item = savedItem(h)
        let preview = try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 5, green: 5, blue: 5))
        h.show(item, preview: preview)
        let newID = CaptureID()
        h.nextIDs = [newID]
        h.handle(.stripTapped(item.id, .save))
        let target = URL(fileURLWithPath: "/Users/me/Desktop/Copy.png")
        #expect(h.handle(.saveAsChosen(item.id, target)).fileActions == [.saveAs(item, to: target, newID: newID)])
        var copy = item
        copy.id = newID
        copy.fileURL = target
        let done = h.handle(.fileActionFinished(item.id, .savedCopy(copy)))
        #expect(done.published == [CaptureEvent(change: .created, item: copy, preview: preview, origin: "quickAccess")])
        #expect(h.model.pendingSaveAs.isEmpty)
        // Its own created comes back over the bus: no thumbnail.
        #expect(h.show(copy, origin: "quickAccess").isEmpty)
    }

    @Test func saveAsOntoTheCapturesOwnFileDoesNothing() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        let same = URL(fileURLWithPath: item.fileURL.path + "/../" + item.fileURL.lastPathComponent)
        #expect(h.handle(.saveAsChosen(item.id, same)).isEmpty)
        h.handle(.stripTapped(item.id, .save))  // a fresh Save As…: the first answer cleared the pending copy
        #expect(h.handle(.saveAsChosen(item.id, item.fileURL)).isEmpty)
    }

    @Test(arguments: ["close", "escape", "expired", "evicted"])
    func saveAsIsStillMadeAfterTheThumbnailWentAway(_ how: String) {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item, anchor: Rect2D(x: 0, y: 0, width: 800, height: 300))
        h.handle(.stripTapped(item.id, .save))
        switch how {
        case "close": h.handle(.closeTapped(item.id))
        case "escape": h.handle(.escape(item.id))
        case "expired": h.handle(.tick, at: 60)
        default: h.show(h.item(), anchor: Rect2D(x: 0, y: 0, width: 800, height: 300))
        }
        #expect(h.shown.firstIndex(of: item.id) == nil)
        let target = URL(fileURLWithPath: "/tmp/Copy.png")
        #expect(h.handle(.saveAsChosen(item.id, target)).fileActions.count == 1)
    }

    @Test func saveAsUsesTheItemAsSavedOrMovedWhileThePanelWasOpen() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.closeTapped(item.id))
        let elsewhere = moved(item, to: "/Users/me/Desktop/Shot.png")
        h.publish(.moved, elsewhere, previous: item.fileURL)
        let target = URL(fileURLWithPath: "/tmp/Copy.png")
        guard case .saveAs(let source, _, _)? = h.handle(.saveAsChosen(item.id, target)).fileActions.first else {
            Issue.record("no copy")
            return
        }
        #expect(source.fileURL == elsewhere.fileURL)
    }

    @Test func aDeletedEventCancelsAnOpenSaveAs() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.publish(.deleted, item, origin: "duplicates")
        #expect(h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png"))).isEmpty)
    }

    @Test func aDeletedEventAfterDismissalAlsoCancelsIt() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.closeTapped(item.id))
        h.publish(.deleted, item, origin: "duplicates")
        #expect(h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png"))).isEmpty)
    }

    @Test func saveAsResultsNotifyOrDoNothing() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png")))
        let failed = h.handle(.fileActionFinished(item.id, .saveAsFailed("No space.")))
        #expect(failed.notices == ["Couldn't save a copy | No space."])
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png")))
        #expect(h.handle(.fileActionFinished(item.id, .saveAsUnchanged)).isEmpty)
        #expect(h.model.pendingSaveAs.isEmpty)
    }

    @Test func aSecondSaveAsTapWhileThePanelIsOpenIsIgnored() {
        let h = ModelHarness()
        let item = savedItem(h)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        #expect(h.handle(.stripTapped(item.id, .save)).isEmpty)
    }

    // MARK: Reveal and Delete

    @Test func revealShowsTheFile() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.reveal, subitemID: nil))
        #expect(effects.recorded.map(\.trigger) == [.menu])
        #expect(effects.contains(.reveal(item.fileURL)))
        #expect(effects.performed.isEmpty)
    }

    @Test func deleteTrashesASavedFileAndRemovesATempOne() {
        let h = ModelHarness()
        let saved = h.item(saved: true)
        let temp = h.item()
        h.show(saved)
        h.show(temp)
        #expect(
            h.handle(.menuChosen(saved.id, actionID: QuickAccessActionID.delete, subitemID: nil)).contains(
                .trash(saved.id, saved.fileURL)))
        #expect(
            h.handle(.menuChosen(temp.id, actionID: QuickAccessActionID.delete, subitemID: nil)).contains(
                .remove(temp.id, temp.fileURL)))
        #expect(h.shown.count == 2)  // nothing dismissed before the result
        let done = h.handle(.fileActionFinished(saved.id, .deleted))
        #expect(done.published == [CaptureEvent(change: .deleted, item: saved, origin: "quickAccess")])
        #expect(done.logs.contains("dismiss \(saved.id) deleted"))
        #expect(h.shown == [temp.id])
    }

    @Test func aFailedDeleteNotifiesAndKeepsTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil))
        let failed = h.handle(.fileActionFinished(item.id, .deleteFailed("Locked.")))
        #expect(failed.notices == ["Delete failed | Locked."])
        #expect(failed.published.isEmpty)
        #expect(h.shown == [item.id])
    }

    @Test func aFinishedDeletePublishesEvenAfterTheThumbnailExpired() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item, at: 0)
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil), at: 4)
        h.handle(.tick, at: 10)
        #expect(h.handle(.fileActionFinished(item.id, .deleted)).published.map(\.change) == [.deleted])
    }

    @Test func aDeleteFinishingAfterAnotherModulesDeletedPublishesNothingMore() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil))
        h.publish(.deleted, item, origin: "duplicates")
        #expect(h.handle(.fileActionFinished(item.id, .deleted)).published.isEmpty)
    }

    // MARK: Other modules' actions

    @Test func thePrimaryRunsFromTheStripAndADoubleClick() {
        let h = ModelHarness(extraSpecs: [ModelHarness.edit], handled: [ModelHarness.edit.id])
        let item = h.item()
        h.show(item)
        let strip = h.handle(.stripTapped(item.id, .primary))
        #expect(strip.recorded.map(\.trigger) == [.strip])
        #expect(strip.performed == [QuickAccessActionContext(actionID: "editor.edit", items: [item], trigger: .strip)])
        let double = h.handle(.imageDoubleClicked(item.id))
        #expect(
            double.performed == [
                QuickAccessActionContext(actionID: "editor.edit", items: [item], trigger: .doubleClick)
            ])
        #expect(double.recorded.map(\.trigger) == [.doubleClick])
    }

    @Test func aDoubleClickWithoutAnEnabledPrimaryDoesNothing() {
        let h = ModelHarness(extraSpecs: [ModelHarness.edit])
        let item = h.item()
        h.show(item)
        #expect(h.handle(.imageDoubleClicked(item.id)).isEmpty)
        h.handlers[ModelHarness.edit.id] = QuickAccessActionHandler(state: { _ in .disabled }, perform: { _ in })
        #expect(h.handle(.imageDoubleClicked(item.id)).isEmpty)
        let recording = h.item(.recording)
        h.handlers[ModelHarness.edit.id] = QuickAccessActionHandler(perform: { _ in })
        h.show(recording)
        #expect(h.handle(.imageDoubleClicked(recording.id)).isEmpty)
    }

    @Test func menuAndDecorationActionsRunTheirHandlerWithTheSubitem() {
        let h = ModelHarness(extraSpecs: [ModelHarness.copyText], handled: [ModelHarness.copyText.id])
        let item = h.item()
        h.show(item)
        let menu = h.handle(.menuChosen(item.id, actionID: "text.copy", subitemID: "s1"))
        #expect(
            menu.performed == [
                QuickAccessActionContext(actionID: "text.copy", items: [item], trigger: .menu, subitemID: "s1")
            ])
        #expect(
            menu.recorded == [
                PerformedQuickAccessAction(actionID: "text.copy", captureID: item.id, kind: .screenshot, trigger: .menu)
            ])
        let decoration = h.handle(.decorationTapped(item.id, actionID: "text.copy"))
        #expect(decoration.performed.map(\.trigger) == [.decoration])
    }

    @Test func anActionWithoutAHandlerIsLogged() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        let effects = h.handle(.decorationTapped(item.id, actionID: "provenance.openSource"))
        #expect(effects.logs == ["no handler for provenance.openSource"])
        #expect(effects.performed.isEmpty)
        #expect(effects.recorded.isEmpty)
    }

    @Test func activityIsRecordedBeforeTheActionRuns() {
        let h = ModelHarness(extraSpecs: [ModelHarness.edit], handled: [ModelHarness.edit.id])
        let item = h.item()
        h.show(item)
        let effects = h.handle(.stripTapped(item.id, .primary))
        let record = effects.firstIndex { if case .recordActivity = $0 { true } else { false } }
        let perform = effects.firstIndex { if case .perform = $0 { true } else { false } }
        #expect(record != nil && perform != nil && record! < perform!)
    }

    // MARK: Snapshot

    @Test func theDebugSnapshotListsTheStackOldestFirst() throws {
        let h = ModelHarness()
        let a = h.item(name: "A.png")
        let b = h.item(.recording, saved: true, name: "B.mp4")
        h.show(a)
        h.show(b)
        h.handle(.hoverBegan(b.id, bugeyeKeyWindow: nil))
        h.handle(.imageClicked(a.id, shift: true))
        let json = h.model.stackSnapshotJSON()
        let rows = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows[0]["id"] as? String == a.id.description)
        #expect(rows[0]["file"] as? String == "A.png")
        #expect(rows[0]["kind"] as? String == "screenshot")
        #expect(rows[0]["saved"] as? Bool == false)
        #expect(rows[0]["selected"] as? Bool == true)
        #expect(rows[1]["hovered"] as? Bool == true)
        #expect(rows[1]["saved"] as? Bool == true)
        #expect(rows[1]["editing"] as? Bool == false)
        #expect(!json.contains("\n"))
    }
}
