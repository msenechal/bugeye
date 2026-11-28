import AppKit
import Testing

@testable import BugeyeApp

@MainActor @Suite struct MainMenuTests {
    /// Every item of every submenu, flattened.
    func items() -> [NSMenuItem] {
        MainMenu.make().items.flatMap { $0.submenu?.items ?? [] }
    }

    func item(for action: String) -> NSMenuItem? {
        items().first { $0.action == Selector((action)) }
    }

    @Test(arguments: [
        ("paste:", "v"), ("copy:", "c"), ("cut:", "x"), ("selectAll:", "a"), ("undo:", "z"),
        ("performClose:", "w"), ("terminate:", "q"),
    ])
    func standardShortcutsReachTheFocusedField(action: String, key: String) throws {
        let found = try #require(item(for: action), "no menu item for \(action)")
        #expect(found.keyEquivalent == key)
        #expect(found.keyEquivalentModifierMask == .command)
        #expect(found.target == nil)
    }

    @Test func redoIsShiftCommandZ() throws {
        let redo = try #require(item(for: "redo:"))
        #expect(redo.keyEquivalent == "z")
        #expect(redo.keyEquivalentModifierMask == [.command, .shift])
    }
}
