import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@Suite struct KeystrokeLabelTests {
    private func label(
        _ code: UInt16, _ characters: String, _ modifiers: Set<TimelineModifier>, all: Bool = false
    ) -> String? {
        KeystrokeFormatter.label(keyCode: code, characters: characters, modifiers: modifiers, showAllKeys: all)
    }

    @Test func shortcutsOnlyByDefault() {
        #expect(label(20, "3", [.shift, .cmd]) == "⇧ ⌘ 3")
        #expect(label(6, "z", [.cmd]) == "⌘ Z")
        #expect(label(8, "c", [.ctrl]) == "⌃ C")
        #expect(label(0, "a", [.ctrl, .opt, .shift, .cmd]) == "⌃ ⌥ ⇧ ⌘ A")
        #expect(label(49, " ", [.cmd]) == "⌘ Space")
        #expect(label(36, "\r", [.cmd]) == "⌘ ↩")
        // Typing, ⌥ and ⇧ included, is hidden.
        #expect(label(0, "a", []) == nil)
        #expect(label(0, "a", [.shift]) == nil)
        #expect(label(33, "[", [.opt]) == nil)
        #expect(label(36, "\r", []) == nil)
    }

    @Test func everythingWithShowAllKeys() {
        #expect(label(0, "a", [], all: true) == "A")
        #expect(label(0, "a", [.shift], all: true) == "⇧ A")
        #expect(label(36, "\r", [], all: true) == "↩")
        let named: [(UInt16, String)] = [
            (36, "↩"), (76, "⌤"), (48, "⇥"), (49, "Space"), (51, "⌫"), (117, "⌦"), (53, "⎋"), (123, "←"),
            (124, "→"), (125, "↓"), (126, "↑"), (115, "↖"), (119, "↘"), (116, "⇞"), (121, "⇟"), (122, "F1"),
            (111, "F12"),
        ]
        for (code, symbol) in named { #expect(label(code, "", [], all: true) == symbol) }
    }

    @Test func layouts() {
        // AZERTY ⌘A, the number row, German Ü, Russian ⌘C.
        #expect(label(12, "a", [.cmd]) == "⌘ A")
        #expect(label(20, "\"", [.shift, .cmd]) == "⇧ ⌘ 3")
        #expect(label(33, "ü", [.cmd]) == "⌘ Ü")
        #expect(label(8, "с", [.cmd]) == "⌘ C")
    }
}

@Suite struct KeystrokeBadgeTests {
    @Test func theSameLabelWithin1_5SecondsCounts() {
        var badge = KeystrokeBadge()
        badge.press("⌘ Z", at: 0)
        badge.press("⌘ Z", at: 1.0)
        badge.press("⌘ Z", at: 2.4)
        #expect(badge.text(at: 2.5) == "⌘ Z ×3")
        badge.press("⌘ Z", at: 4.0)
        #expect(badge.text(at: 4.0) == "⌘ Z")
        badge.press("⌘ S", at: 4.1)
        #expect(badge.text(at: 4.1) == "⌘ S")
    }

    @Test func visibleFor1_5SecondsTheLast0_3Fading() {
        var badge = KeystrokeBadge()
        #expect(badge.opacity(at: 0) == 0)
        badge.press("⌘ S", at: 10)
        #expect(badge.opacity(at: 10) == 1)
        #expect(badge.opacity(at: 11.2) == 1)
        #expect(abs(badge.opacity(at: 11.35) - 0.5) < 1e-9)
        #expect(badge.opacity(at: 11.5) == 0)
        #expect(badge.text(at: 11.5) == nil)
        #expect(badge.isVisible(at: 11.49))
        #expect(!badge.isVisible(at: 11.5))
    }

    @Test func theBadgeDrawsAsInTheGolden() throws {
        var badge = KeystrokeBadge()
        badge.press("⇧ ⌘ 3", at: 0)
        let list = try #require(
            badge.displayList(at: 1.35, area: Size2D(width: 800, height: 600), measurer: FakeTextMeasurer()))
        #expect(list.isBalanced)
        try Golden.check(list, "keystroke-badge")
        #expect(badge.displayList(at: 2, area: Size2D(width: 800, height: 600), measurer: FakeTextMeasurer()) == nil)
    }
}

@Suite struct ClickRingsTests {
    @Test func leftIsYellowRightIsPinkOtherNone() {
        var rings = ClickRings()
        rings.click(.left, at: Point2D(x: 10, y: 10), time: 0)
        rings.click(.right, at: Point2D(x: 50, y: 50), time: 0)
        rings.click(.other, at: Point2D(x: 90, y: 90), time: 0)
        #expect(rings.count(at: 0.1) == 2)
        #expect(rings.isAnimating(at: 0.49))
        #expect(!rings.isAnimating(at: 0.5))
        #expect(rings.count(at: 0.5) == 0)
    }

    @Test func ringsGrowFrom14To28PointsEasingOut() {
        #expect(ClickRings.diameter(progress: 0) == 14)
        #expect(ClickRings.diameter(progress: 1) == 28)
        #expect(ClickRings.diameter(progress: 0.5) == 24.5)
    }

    @Test func ringsDrawAsInTheGolden() throws {
        var rings = ClickRings()
        rings.click(.left, at: Point2D(x: 100, y: 80), time: 0)
        rings.click(.right, at: Point2D(x: 300, y: 200), time: 0.25)
        let list = rings.displayList(at: 0.25, area: Size2D(width: 400, height: 300))
        #expect(list.isBalanced)
        try Golden.check(list, "click-rings")
    }
}

/// Golden display lists in `Fixtures/`. Set `BUGEYE_UPDATE_GOLDENS` to a path to write the current JSON there.
enum Golden {
    static func check(_ list: DisplayList, _ name: String) throws {
        let json = try list.goldenJSON()
        if let folder = ProcessInfo.processInfo.environment["BUGEYE_UPDATE_GOLDENS"] {
            try json.write(toFile: folder + "/" + name + ".json", atomically: false, encoding: .utf8)
        }
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        #expect(json == (try String(contentsOf: url, encoding: .utf8)))
    }
}
