import AppKit
import BugeyeFeatures
import Testing

@testable import BugeyeApp

/// The main menu built from `MainMenu.entries` (contracts §4.2.5). Built from `[GeneralModule()]`, never the live
/// module list (K20). Wave 0's shortcuts still reach the focused field in Settings.
@MainActor @Suite struct MainMenuTests {
    func menu() throws -> NSMenu {
        MainMenuInstaller.menu(for: try FeatureRegistry([GeneralModule()]))
    }

    func items() throws -> [NSMenuItem] {
        try menu().items.flatMap { $0.submenu?.items ?? [] }
    }

    func item(for action: String) throws -> NSMenuItem? {
        try items().first { $0.action == NSSelectorFromString(action) }
    }

    @Test func menusAreBugeyeFileEditView() throws {
        #expect(try menu().items.map(\.title) == ["Bugeye", "File", "Edit", "View"])
    }

    @Test(arguments: [
        ("paste:", "v"), ("copy:", "c"), ("cut:", "x"), ("selectAll:", "a"), ("undo:", "z"),
        ("performClose:", "w"), ("terminate:", "q"), ("saveDocument:", "s"), ("zoomIn:", "="), ("zoomOut:", "-"),
        ("zoomToActualSize:", "1"), ("zoomToFit:", "0"),
    ])
    func commandShortcutsReachTheFirstResponder(action: String, key: String) throws {
        let found = try #require(try item(for: action), "no menu item for \(action)")
        #expect(found.keyEquivalent == key)
        #expect(found.keyEquivalentModifierMask == .command)
        #expect(found.target == nil)
    }

    @Test func shiftedShortcuts() throws {
        let redo = try #require(try item(for: "redo:"))
        #expect(redo.keyEquivalent == "z" && redo.keyEquivalentModifierMask == [.command, .shift])
        let saveAs = try #require(try item(for: "saveDocumentAs:"))
        #expect(saveAs.keyEquivalent == "s" && saveAs.keyEquivalentModifierMask == [.command, .shift])
        let delete = try #require(try item(for: "delete:"))
        #expect(delete.keyEquivalent == "")
    }

    @Test func separatorsSitWhereTheTableSays() throws {
        let file = try #require(try menu().items[1].submenu)
        #expect(file.items.map { $0.isSeparatorItem ? "—" : $0.title } == ["Save", "Save As\u{2026}", "—", "Close"])
    }
}
