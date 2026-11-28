import AppKit

/// The app's main menu. A menu-bar agent (`LSUIElement`) never shows it, but AppKit routes the standard
/// key equivalents through it: without it, ⌘V can't paste the API key into Settings and ⌘W can't close the
/// window. Items target the first responder (`target` nil), so they act on the key window's focused field.
enum MainMenu {
    @MainActor static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(item("Quit Bugeye", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(submenu(app, title: "Bugeye"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        main.addItem(submenu(edit, title: "Edit"))

        let window = NSMenu(title: "Window")
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        main.addItem(submenu(window, title: "Window"))

        return main
    }

    @MainActor private static func item(
        _ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }

    @MainActor private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
