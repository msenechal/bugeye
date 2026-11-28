import AppKit
import BugeyeFeatures

/// Builds `NSApp.mainMenu` from `MainMenu.entries` (contracts §4.2.5, §4.5) and applies `DocumentWindows`'
/// activation policy. Items target the first responder (`target` nil), so they act on the key window: the editor
/// answers Save, Zoom and the rest; the Settings window's fields answer ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W.
@MainActor
enum MainMenuInstaller {
    static func menu(for registry: FeatureRegistry) -> NSMenu {
        let main = NSMenu()
        let entries = MainMenu.entries(for: registry)
        for group in MainMenuGroup.allCases {
            let title = MainMenu.title(of: group)
            let submenu = NSMenu(title: title)
            for entry in entries[group] ?? [] {
                switch entry {
                case .separator:
                    submenu.addItem(.separator())
                case .item(let spec):
                    let item = NSMenuItem(
                        title: spec.title, action: NSSelectorFromString(spec.action), keyEquivalent: spec.key?.key ?? ""
                    )
                    item.keyEquivalentModifierMask = spec.key.map { MenuBuilder.modifierFlags($0.modifiers) } ?? []
                    item.identifier = NSUserInterfaceItemIdentifier(spec.id)
                    item.target = nil
                    submenu.addItem(item)
                }
            }
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = submenu
            main.addItem(holder)
        }
        return main
    }

    /// `.regular`: installs `menu`, sets the policy, activates Bugeye. `.accessory`: sets the policy back and keeps
    /// the menu, which an accessory app never shows but which keeps ⌘V working in Settings (plan P10).
    static func applier(
        menu: NSMenu, setPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void,
        setMainMenu: @escaping @MainActor (NSMenu) -> Void, activate: @escaping @MainActor () -> Void
    ) -> @MainActor (ActivationPolicy) -> Void {
        { policy in
            switch policy {
            case .regular:
                setMainMenu(menu)
                setPolicy(.regular)
                activate()
            case .accessory:
                setPolicy(.accessory)
            }
        }
    }
}
