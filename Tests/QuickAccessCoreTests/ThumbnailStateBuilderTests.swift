import BugeyeCore
import BugeyeFeatures
import Foundation
import QuickAccessCore
import Testing

@MainActor
@Suite struct ThumbnailStateBuilderTests {
    static let edit = QuickAccessActionSpec(
        id: "editor.edit", title: "Edit", order: 0, placement: .primary, kinds: [.screenshot])
    static let trim = QuickAccessActionSpec(
        id: "recording.trim", title: "Trim", order: 0, placement: .primary, kinds: [.recording])
    static let copyText = QuickAccessActionSpec(id: "text.copy", title: "Copy Text", order: 100, kinds: [.screenshot])
    static let exportGIF = QuickAccessActionSpec(
        id: "recording.gif", title: "Export GIF\u{2026}", order: 850, kinds: [.recording])
    static let combine = QuickAccessActionSpec(
        id: "collections.combine", title: "Combine", order: 0, placement: .selection, kinds: [.screenshot])
    static let reveal = QuickAccessModule.revealSpec
    static let delete = QuickAccessModule.deleteSpec

    var states: [String: QuickAccessActionState] = [:]
    var handled: Set<String> = [reveal.id, delete.id]

    func item(_ kind: CaptureKind = .screenshot, saved: Bool = false) -> CaptureItem {
        CaptureItem(
            id: CaptureID(), fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"), isSaved: saved, kind: kind,
            createdAt: Date(timeIntervalSince1970: 0), pixelsPerPoint: 2)
    }

    func build(
        _ item: CaptureItem, specs: [QuickAccessActionSpec] = [reveal, delete], decorations: [ThumbnailDecoration] = [],
        isSelected: Bool = false, selectionHostCount: Int? = nil
    ) -> ThumbnailStateBuilder.Output {
        let states = self.states
        let handled = self.handled
        return ThumbnailStateBuilder.build(
            item: item, preview: nil, isSelected: isSelected, selectionHostCount: selectionHostCount, specs: specs,
            handler: { id in
                guard handled.contains(id) else { return nil }
                let state = states[id] ?? .enabled
                return QuickAccessActionHandler(state: { _ in state }, perform: { _ in })
            }, decorations: decorations)
    }

    @Test func withoutAPrimaryTheStripIsCopyAndSaveOnly() {
        let state = build(item()).state
        #expect(state.strip.map(\.title) == ["Copy", "Save"])
        #expect(state.strip.map(\.slot) == [.copy, .save])
        #expect(state.strip.map(\.actionID) == [QuickAccessActionID.copy, QuickAccessActionID.save])
        #expect(state.strip.allSatisfy { !$0.isAccent && $0.isEnabled && !$0.hasRing })
    }

    @Test mutating func aRegisteredPrimaryIsThirdAndAccent() {
        handled.insert(Self.edit.id)
        let state = build(item(), specs: [Self.edit, Self.reveal, Self.delete]).state
        #expect(state.strip.map(\.title) == ["Copy", "Save", "Edit"])
        #expect(state.strip[2].slot == .primary)
        #expect(state.strip[2].actionID == "editor.edit")
        #expect(state.strip[2].isAccent)
    }

    @Test mutating func aPrimaryForAnotherKindIsNotShown() {
        handled.formUnion([Self.edit.id, Self.trim.id])
        let recording = build(item(.recording), specs: [Self.edit, Self.trim]).state
        #expect(recording.strip.map(\.title) == ["Copy", "Save", "Trim"])
        let gif = build(item(.gif), specs: [Self.edit, Self.trim]).state
        #expect(gif.strip.map(\.title) == ["Copy", "Save"])
    }

    @Test func aSpecWithoutAHandlerIsNotShown() {
        let state = build(item(), specs: [Self.edit, Self.copyText, Self.reveal, Self.delete]).state
        #expect(state.strip.count == 2)
        #expect(state.menu.map(\.title) == ["Reveal in Finder", "Delete"])
    }

    @Test func saveBecomesSaveAsOnceSaved() {
        let state = build(item(saved: true)).state
        #expect(state.strip[1].title == "Save As\u{2026}")
        #expect(state.strip[1].actionID == QuickAccessActionID.saveAs)
    }

    @Test mutating func menuIsSortedByOrderWithRevealAndDeleteLast() {
        handled.formUnion([Self.copyText.id, Self.exportGIF.id])
        let screenshot = build(item(), specs: [Self.delete, Self.reveal, Self.exportGIF, Self.copyText]).state
        #expect(screenshot.menu.map(\.title) == ["Copy Text", "Reveal in Finder", "Delete"])
        let recording = build(item(.recording), specs: [Self.delete, Self.reveal, Self.exportGIF, Self.copyText]).state
        #expect(recording.menu.map(\.title) == ["Reveal in Finder", "Export GIF\u{2026}", "Delete"])
        #expect(recording.menu.map(\.actionID) == [Self.reveal.id, Self.exportGIF.id, Self.delete.id])
    }

    @Test mutating func handlerStatesHideGreyAndNest() {
        handled.formUnion([Self.copyText.id, "a.menu", "b.menu"])
        let a = QuickAccessActionSpec(id: "a.menu", title: "Open Source", order: 400)
        let b = QuickAccessActionSpec(id: "b.menu", title: "Find Similar", order: 500)
        states[Self.copyText.id] = .hidden
        states[a.id] = .submenu([
            QuickAccessSubitem(id: "s1", title: "Safari"), QuickAccessSubitem(id: "s2", title: "Xcode"),
        ])
        states[b.id] = .disabled
        let state = build(item(), specs: [Self.copyText, a, b, Self.reveal, Self.delete]).state
        #expect(state.menu.map(\.title) == ["Open Source", "Find Similar", "Reveal in Finder", "Delete"])
        #expect(state.menu[0].subitems.map(\.title) == ["Safari", "Xcode"])
        #expect(state.menu[0].isEnabled)
        #expect(!state.menu[1].isEnabled)
        #expect(state.menu[2].subitems.isEmpty)
    }

    @Test mutating func thePrimaryIsNeverHiddenButDisabledGreysIt() {
        handled.insert(Self.edit.id)
        states[Self.edit.id] = .hidden
        #expect(build(item(), specs: [Self.edit]).state.strip.map(\.title) == ["Copy", "Save", "Edit"])
        states[Self.edit.id] = .disabled
        let strip = build(item(), specs: [Self.edit]).state.strip
        #expect(strip[2].isEnabled == false)
    }

    @Test mutating func theSuggestedActionRingsItsStripButton() {
        handled.insert(Self.edit.id)
        let specs = [Self.edit, Self.reveal, Self.delete]
        func rings(_ id: String, saved: Bool = false) -> [Bool] {
            build(item(saved: saved), specs: specs, decorations: [.suggestedAction(actionID: id)]).state.strip.map(
                \.hasRing)
        }
        #expect(rings(QuickAccessActionID.copy) == [true, false, false])
        #expect(rings(QuickAccessActionID.save) == [false, true, false])
        #expect(rings(QuickAccessActionID.saveAs, saved: true) == [false, true, false])
        #expect(rings(QuickAccessActionID.saveAs, saved: false) == [false, true, false])
        #expect(rings("editor.edit") == [false, false, true])
        let state = build(item(), specs: specs, decorations: [.suggestedAction(actionID: "editor.edit")]).state
        #expect(!state.moreHasRing)
        #expect(state.menu.allSatisfy { !$0.title.hasPrefix("\u{2605}") })
    }

    @Test func aSuggestedMenuActionRingsMoreAndGetsAStar() {
        let state = build(item(), decorations: [.suggestedAction(actionID: QuickAccessActionID.reveal)]).state
        #expect(state.moreHasRing)
        #expect(state.menu.map(\.title) == ["\u{2605} Reveal in Finder", "Delete"])
        #expect(state.strip.allSatisfy { !$0.hasRing })
    }

    @Test func aSuggestedActionThatIsNotDrawnRingsNothing() {
        let state = build(item(), decorations: [.suggestedAction(actionID: "text.copy")]).state
        #expect(!state.moreHasRing)
        #expect(state.strip.allSatisfy { !$0.hasRing })
        #expect(state.menu.map(\.title) == ["Reveal in Finder", "Delete"])
    }

    @Test mutating func theSelectionHostShowsOneAccentButton() {
        handled.insert(Self.combine.id)
        let specs = [Self.combine, Self.reveal, Self.delete]
        let host = build(item(), specs: specs, isSelected: true, selectionHostCount: 3).state
        #expect(host.isSelected)
        #expect(host.strip.map(\.title) == ["Combine (3)"])
        #expect(host.strip[0].slot == .selection)
        #expect(host.strip[0].actionID == "collections.combine")
        #expect(host.strip[0].isAccent)
        let alone = build(item(), specs: specs, isSelected: true, selectionHostCount: 1).state
        #expect(alone.strip.map(\.title) == ["Copy", "Save"])
        let other = build(item(), specs: specs, isSelected: true, selectionHostCount: nil).state
        #expect(other.strip.map(\.title) == ["Copy", "Save"])
    }

    @Test func withoutASelectionHandlerTheHostKeepsItsStrip() {
        let host = build(item(), specs: [Self.combine], isSelected: true, selectionHostCount: 3).state
        #expect(host.strip.map(\.title) == ["Copy", "Save"])
    }

    @Test func theFirstDecorationOfEachCaseWinsAndTheRestAreReported() {
        let output = build(
            item(.recording),
            decorations: [
                .mediaBadge(text: "\u{25B6} 00:42"),
                .sourceChip(label: "Safari", appBundleID: "com.apple.Safari", actionID: nil),
                .mediaBadge(text: "GIF"),
                .warningBadge(text: "\u{26A0} 2 possible", tooltip: nil, actionID: nil),
                .sourceChip(label: "Xcode", appBundleID: nil, actionID: nil),
            ])
        #expect(output.state.mediaBadge == .mediaBadge(text: "\u{25B6} 00:42"))
        #expect(output.state.sourceChip == .sourceChip(label: "Safari", appBundleID: "com.apple.Safari", actionID: nil))
        #expect(output.state.warningBadge == .warningBadge(text: "\u{26A0} 2 possible", tooltip: nil, actionID: nil))
        #expect(output.ignoredDecorations == ["mediaBadge", "sourceChip"])
    }

    @Test func theStateCarriesTheItemsIdentity() {
        let screenshot = item()
        let state = build(screenshot).state
        #expect(state.id == screenshot.id)
        #expect(state.kind == .screenshot)
        #expect(state.preview == nil)
        #expect(!state.isSelected)
    }
}
