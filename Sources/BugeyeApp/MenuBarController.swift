import AppKit
import BugeyeFeatures

/// The status item and its menu, built from `StatusMenu` entries.
@MainActor
final class MenuBarController: NSObject {
    var onChoose: @MainActor (String) -> Void = { _ in }
    private let statusItem: NSStatusItem

    init(entries: [StatusMenuEntry]) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            if let glyph = Bundle.main.image(forResource: "MenuBarIcon") {
                glyph.isTemplate = true
                button.image = glyph
            } else {
                button.title = "Bugeye"  // `swift run` has no bundle, so no glyph.
            }
            button.setAccessibilityLabel("Bugeye")
        }
        statusItem.menu = MenuBuilder.menu(entries, target: self, action: #selector(choose(_:)))
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let id = sender.identifier?.rawValue else { return }
        onChoose(id)
    }
}

/// Turns menu entries into an `NSMenu`. Separate from the status item so tests can check it.
@MainActor
enum MenuBuilder {
    static func menu(_ entries: [StatusMenuEntry], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .item(let id, let title, let key):
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key?.key ?? "")
                item.keyEquivalentModifierMask = key.map { modifierFlags($0.modifiers) } ?? []
                item.identifier = NSUserInterfaceItemIdentifier(id)
                item.target = target
                menu.addItem(item)
            }
        }
        return menu
    }

    static func modifierFlags(_ modifiers: Set<KeyModifier>) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }
}
