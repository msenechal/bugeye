import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore
import Testing

/// The final review of #10: every path that releases `busy`, the item a Save publishes, the Save As… preview, and
/// focus edges.
@MainActor
@Suite struct QuickAccessModelReviewTests {
    func saveAsOpens(_ h: ModelHarness, _ id: CaptureID) -> Bool {
        h.handle(.stripTapped(id, .save)).contains { if case .showSavePanel = $0 { true } else { false } }
    }

    func deleteRuns(_ h: ModelHarness, _ id: CaptureID) -> Bool {
        h.handle(.menuChosen(id, actionID: QuickAccessActionID.delete, subitemID: nil)).contains {
            if case .trash = $0 { true } else if case .remove = $0 { true } else { false }
        }
    }

    // MARK: I1: busy is released on every path

    @Test func cancellingTheSavePanelReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, nil))
        #expect(h.model.busy.isEmpty)
        #expect(saveAsOpens(h, item.id))
    }

    @Test func choosingTheSameFileReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, item.fileURL))
        #expect(h.model.busy.isEmpty)
        #expect(deleteRuns(h, item.id))
    }

    @Test func aFinishedCopyReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        let target = URL(fileURLWithPath: "/tmp/Copy.png")
        h.handle(.saveAsChosen(item.id, target))
        var copy = item
        copy.id = CaptureID()
        copy.fileURL = target
        h.handle(.fileActionFinished(item.id, .savedCopy(copy)))
        #expect(h.model.busy.isEmpty)
        #expect(saveAsOpens(h, item.id))
    }

    @Test func anUnchangedCopyReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png")))
        h.handle(.fileActionFinished(item.id, .saveAsUnchanged))
        #expect(h.model.busy.isEmpty)
        #expect(saveAsOpens(h, item.id))
    }

    @Test func aFailedCopyReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png")))
        h.handle(.fileActionFinished(item.id, .saveAsFailed("No space.")))
        #expect(h.model.busy.isEmpty)
        #expect(saveAsOpens(h, item.id))
    }

    @Test func aFinishedSaveReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        var saved = item
        saved.isSaved = true
        saved.fileURL = URL(fileURLWithPath: "/Users/me/Pictures/Bugeye/a.png")
        h.handle(.fileActionFinished(item.id, .saved(saved, previousURL: item.fileURL)))
        #expect(h.model.busy.isEmpty)
        #expect(saveAsOpens(h, item.id))
    }

    @Test func anUnavailableFolderReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.fileActionFinished(item.id, .saveFolderUnavailable(path: "~/x/")))
        #expect(h.model.busy.isEmpty)
        #expect(deleteRuns(h, item.id))
    }

    @Test func aFailedDeleteReleasesTheThumbnail() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil))
        h.handle(.fileActionFinished(item.id, .deleteFailed("Locked.")))
        #expect(h.model.busy.isEmpty)
        #expect(deleteRuns(h, item.id))
    }

    @Test func aFinishedDeleteReleasesTheID() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil))
        h.handle(.fileActionFinished(item.id, .deleted))
        #expect(h.model.busy.isEmpty)
    }

    /// M1: a `deleted` event cancelled the open Save As…; the panel's later answer releases the id.
    @Test func aSaveAsCancelledByDeletedReleasesTheID() {
        let h = ModelHarness()
        let item = h.item(saved: true)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.publish(.deleted, item, origin: "duplicates")
        h.handle(.saveAsChosen(item.id, URL(fileURLWithPath: "/tmp/Copy.png")))
        #expect(h.model.busy.isEmpty)
    }

    // MARK: M2: Save publishes the current item

    @Test func aSavePublishesTheItemAsEditedMeanwhile() {
        let h = ModelHarness()
        let item = h.item(.recording)
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        var edited = item
        edited.duration = 3
        h.publish(.edited, edited)
        var moved = item
        moved.isSaved = true
        moved.fileURL = URL(fileURLWithPath: "/Users/me/Pictures/Bugeye/r.mp4")
        let done = h.handle(.fileActionFinished(item.id, .saved(moved, previousURL: item.fileURL)))
        var expected = edited
        expected.isSaved = true
        expected.fileURL = moved.fileURL
        #expect(done.published.first?.item == expected)
        #expect(h.entry(item.id)?.item == expected)
    }

    // MARK: M3: Save As… carries the preview as it is when the copy is published

    @Test func saveAsPublishesThePreviewEditedWhileThePanelWasOpen() throws {
        let h = ModelHarness()
        let item = h.item(saved: true)
        let old = try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 1, green: 1, blue: 1))
        let new = try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 2, green: 2, blue: 2))
        h.show(item, preview: old)
        h.handle(.stripTapped(item.id, .save))
        h.publish(.edited, item, preview: new)
        let target = URL(fileURLWithPath: "/tmp/Copy.png")
        h.handle(.saveAsChosen(item.id, target))
        var copy = item
        copy.id = CaptureID()
        copy.fileURL = target
        #expect(h.handle(.fileActionFinished(item.id, .savedCopy(copy))).published.first?.preview == new)
    }

    // MARK: M5: focus edges

    @Test func leavingAThumbnailThatIsNotKeyReturnsNoFocus() {
        let h = ModelHarness()
        let a = h.item()
        let b = h.item()
        h.show(a)
        h.show(b)
        h.handle(.hoverBegan(a.id, bugeyeKeyWindow: nil))
        h.handle(.hoverBegan(b.id, bugeyeKeyWindow: nil))
        let effects = h.handle(.hoverEnded(a.id, bugeyeIsActive: false))
        #expect(!effects.contains(.activateFrontmostApp))
        #expect(!effects.contains { if case .restoreKey = $0 { true } else { false } })
        #expect(h.model.keyPanel == b.id)
    }

    @Test func deletingTheKeyThumbnailReturnsFocusOnce() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.hoverBegan(item.id, bugeyeKeyWindow: nil))
        h.handle(.menuChosen(item.id, actionID: QuickAccessActionID.delete, subitemID: nil))
        let done = h.handle(.fileActionFinished(item.id, .deleted))
        #expect(done.filter { $0 == .activateFrontmostApp }.count == 1)
        #expect(h.handle(.hoverEnded(item.id, bugeyeIsActive: false)).isEmpty)
    }

    // MARK: claude-review on #10: Copy during a Save

    @Test func aCopyThatFailedBecauseASaveMovedTheFileIsRetriedAtTheNewPlace() {
        let h = ModelHarness()
        let item = h.item()
        h.show(item)
        h.handle(.stripTapped(item.id, .save))
        h.handle(.stripTapped(item.id, .copy))
        var saved = item
        saved.isSaved = true
        saved.fileURL = URL(fileURLWithPath: "/Users/me/Pictures/Bugeye/\(item.fileURL.lastPathComponent)")
        h.handle(.fileActionFinished(item.id, .saved(saved, previousURL: item.fileURL)))
        let failed = h.handle(.fileActionFinished(item.id, .copyFailed(name: item.fileURL.lastPathComponent)))
        #expect(failed.notices.isEmpty)
        #expect(failed.fileActions == [.readForCopy(saved)])
        // A second failure at the current place is real.
        let again = h.handle(.fileActionFinished(item.id, .copyFailed(name: item.fileURL.lastPathComponent)))
        #expect(again.notices.count == 1)
    }
}
