import QuickAccessCore
import Testing

@Suite struct QuickAccessStringsTests {
    @Test func stripAndMenuTitlesMatchSpecSection5_1() {
        #expect(QuickAccessStrings.copy == "Copy")
        #expect(QuickAccessStrings.save == "Save")
        #expect(QuickAccessStrings.saveAs == "Save As\u{2026}")
        #expect(QuickAccessStrings.revealInFinder == "Reveal in Finder")
        #expect(QuickAccessStrings.delete == "Delete")
        #expect(QuickAccessStrings.suggestedPrefix == "\u{2605} ")
        #expect(QuickAccessStrings.selectionButtonTitle("Combine", count: 3) == "Combine (3)")
    }

    @Test func accessibilityLabelsMatchSpecSection5_1() {
        #expect(QuickAccessStrings.dismissLabel == "Dismiss")
        #expect(QuickAccessStrings.moreLabel == "More")
    }

    @Test func noticesMatchSpecSection5_3() {
        #expect(QuickAccessStrings.saveFailedTitle == "Couldn't save to folder")
        #expect(
            QuickAccessStrings.folderUnavailableBody(path: "~/Pictures/Bugeye/")
                == "~/Pictures/Bugeye/ is unavailable. The capture stays in the temporary folder.")
        #expect(QuickAccessStrings.saveAsFailedTitle == "Couldn't save a copy")
        #expect(QuickAccessStrings.copyFailedTitle == "Couldn't copy")
        #expect(
            QuickAccessStrings.copyFailedBody(name: "Screenshot 2026-11-27 at 14.03.12.png")
                == "Screenshot 2026-11-27 at 14.03.12.png is missing or unreadable.")
        #expect(QuickAccessStrings.deleteFailedTitle == "Delete failed")
    }

    @Test func settingsPaneMatchesSpecSection5_4() {
        #expect(QuickAccessStrings.paneTitle == "Quick Access")
        #expect(QuickAccessStrings.autoDismissLabel == "Auto-dismiss")
        #expect(QuickAccessStrings.never == "Never")
        #expect(QuickAccessStrings.seconds(5) == "5 seconds")
        #expect(QuickAccessStrings.seconds(60) == "60 seconds")
        #expect(QuickAccessStrings.positionLabel == "Position")
        #expect(QuickAccessStrings.bottomLeft == "Bottom left")
        #expect(QuickAccessStrings.bottomRight == "Bottom right")
    }

    @Test func actionIDsMatchSpecSection3() {
        #expect(QuickAccessActionID.copy == "quickAccess.copy")
        #expect(QuickAccessActionID.save == "quickAccess.save")
        #expect(QuickAccessActionID.saveAs == "quickAccess.saveAs")
        #expect(QuickAccessActionID.reveal == "quickAccess.reveal")
        #expect(QuickAccessActionID.delete == "quickAccess.delete")
    }
}
