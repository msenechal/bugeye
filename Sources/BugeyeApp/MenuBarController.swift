import AppKit
import BugeyeCore
import BugeyeFeatures

/// What `MenuBarController` changes on the status item; the real one wraps an `NSStatusItem`, tests record.
@MainActor
protocol StatusItemDisplay: AnyObject {
    /// The square glyph (or the `Bugeye` title without a bundle), labelled `Bugeye`.
    func showGlyph()
    /// Variable length, drawing the badge.
    func showBadge(_ badge: StatusItemOverride.Badge)
    func setAccessibilityLabel(_ label: String)
    func setMenu(_ menu: NSMenu)
}

/// The status item and its menu (contracts §4.5): the module menu with each item's current hotkey and enabled
/// state, or Recording's override while one is set.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onChoose: @MainActor (String) -> Void = { _ in }
    let moduleMenu: NSMenu
    private let display: any StatusItemDisplay
    private let settings: any SettingsStore
    private let router: ActionRouter
    private let hotkeyStatus: HotkeyStatus
    private let state: StatusItemState
    private let moduleItemIDs: Set<String>
    /// Menu item id → the hotkey whose binding it shows (K13).
    private let hotkeys: [String: HotkeySpec]

    init(
        registry: FeatureRegistry, settings: any SettingsStore, router: ActionRouter, hotkeyStatus: HotkeyStatus,
        statusItemState: StatusItemState, display: any StatusItemDisplay
    ) {
        self.display = display
        self.settings = settings
        self.router = router
        self.hotkeyStatus = hotkeyStatus
        state = statusItemState
        moduleItemIDs = Set(registry.menuItems.map(\.id))
        let specs = Dictionary(registry.hotkeys.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var hotkeys: [String: HotkeySpec] = [:]
        for item in registry.menuItems {
            if let id = item.hotkeyID, let spec = specs[id] { hotkeys[item.id] = spec }
        }
        self.hotkeys = hotkeys
        moduleMenu = NSMenu()
        super.init()
        MenuBuilder.fill(moduleMenu, StatusMenu.entries(for: registry), target: self, action: #selector(choose(_:)))
        moduleMenu.autoenablesItems = false
        moduleMenu.delegate = self
        apply()
        statusItemState.observe { [weak self] in self?.apply() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === moduleMenu else { return }
        updateModuleItems()
    }

    /// Each module item's key from its current binding (none while its hotkey isn't registered, K34) and its
    /// enabled state from the router (K13). The shell's own items stay enabled.
    func updateModuleItems() {
        for item in moduleMenu.items {
            guard let id = item.identifier?.rawValue, moduleItemIDs.contains(id) else { continue }
            item.isEnabled = router.isMenuItemEnabled(id)
            guard let spec = hotkeys[id] else { continue }
            let key = hotkeyStatus.isRegistered(spec.id) ? HotkeyBindings.current(spec, in: settings) : nil
            item.keyEquivalent = key?.key ?? ""
            item.keyEquivalentModifierMask = key.map { MenuBuilder.modifierFlags($0.modifiers) } ?? []
        }
    }

    private func apply() {
        if let override = state.override {
            display.showBadge(override.badge)
            display.setAccessibilityLabel(override.accessibilityLabel)
            display.setMenu(
                MenuBuilder.overrideMenu(override.menu, target: self, action: #selector(chooseOverride(_:))))
        } else {
            display.showGlyph()
            display.setAccessibilityLabel(ShellStrings.statusItemLabel)
            display.setMenu(moduleMenu)
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let id = sender.identifier?.rawValue else { return }
        onChoose(id)
    }

    @objc private func chooseOverride(_ sender: NSMenuItem) {
        guard let id = sender.identifier?.rawValue else { return }
        router.performMenuItem(id)
    }
}

/// The real status item.
@MainActor
final class SystemStatusItemDisplay: StatusItemDisplay {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func showGlyph() {
        statusItem.length = NSStatusItem.squareLength
        guard let button = statusItem.button else { return }
        button.attributedTitle = NSAttributedString(string: "")
        if let glyph = Bundle.main.image(forResource: "MenuBarIcon") {
            glyph.isTemplate = true
            button.image = glyph
            button.title = ""
        } else {
            button.image = nil
            button.title = ShellStrings.statusItemLabel  // `swift run` has no bundle, so no glyph.
        }
    }

    func showBadge(_ badge: StatusItemOverride.Badge) {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        if let symbol = StatusBadge.symbolName(badge) {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        } else {
            button.image = nil
            button.attributedTitle = StatusBadge.title(badge) ?? NSAttributedString(string: "")
        }
    }

    func setAccessibilityLabel(_ label: String) {
        statusItem.button?.setAccessibilityLabel(label)
    }

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }
}

/// How an override badge is drawn: red `● ` + elapsed in monospaced digits; `❙❙ ` + elapsed; the hourglass.
@MainActor
enum StatusBadge {
    static let recordingDot = "\u{25CF} "
    static let pausedBars = "\u{2759}\u{2759} "

    static func symbolName(_ badge: StatusItemOverride.Badge) -> String? {
        if case .finishing = badge { return "hourglass" }
        return nil
    }

    static func title(_ badge: StatusItemOverride.Badge) -> NSAttributedString? {
        let digits = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString()
        switch badge {
        case .recording(let elapsed):
            title.append(
                NSAttributedString(
                    string: recordingDot, attributes: [.foregroundColor: NSColor.systemRed, .font: digits]))
            title.append(NSAttributedString(string: elapsed, attributes: [.font: digits]))
        case .paused(let elapsed):
            title.append(NSAttributedString(string: pausedBars + elapsed, attributes: [.font: digits]))
        case .finishing:
            return nil
        }
        return title
    }
}

/// Turns menu entries into an `NSMenu`. Separate from the status item so tests can check it.
@MainActor
enum MenuBuilder {
    static func menu(_ entries: [StatusMenuEntry], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        fill(menu, entries, target: target, action: action)
        return menu
    }

    static func fill(_ menu: NSMenu, _ entries: [StatusMenuEntry], target: AnyObject, action: Selector) {
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .item(let id, let title, let key):
                menu.addItem(item(id: id, title: title, key: key, target: target, action: action))
            }
        }
    }

    /// Recording's override menu: each entry's own `isEnabled` decides (K35).
    static func overrideMenu(_ entries: [StatusItemOverride.Entry], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            guard let id = entry.id else {
                menu.addItem(.separator())
                continue
            }
            let item = item(id: id, title: entry.title, key: entry.shownKey, target: target, action: action)
            item.isEnabled = entry.isEnabled
            menu.addItem(item)
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

    private static func item(id: String, title: String, key: KeyCombo?, target: AnyObject, action: Selector)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key?.key ?? "")
        item.keyEquivalentModifierMask = key.map { modifierFlags($0.modifiers) } ?? []
        item.identifier = NSUserInterfaceItemIdentifier(id)
        item.target = target
        return item
    }
}
