import BugeyeCore

/// The one action router (K6): status-menu items, override-menu entries, hotkeys, Quick Access actions and
/// "open this capture". A duplicate registration keeps the first and is recorded; launch fails on any.
@MainActor
public final class ActionRouter {
    private struct MenuAction {
        let isEnabled: @MainActor () -> Bool
        let perform: @MainActor () -> Void
    }

    private var menuItems: [String: MenuAction] = [:]
    private var hotkeys: [String: @MainActor () -> Void] = [:]
    private var quickAccess: [String: QuickAccessActionHandler] = [:]
    private var openers: [CaptureKind: @MainActor (CaptureItem) -> Void] = [:]

    /// Registrations refused because the id (or kind) was already taken, as "menu:<id>", "hotkey:<id>",
    /// "quickAccess:<id>", "open:<kind>". The first registration stays. Launch fails unless this is empty.
    public private(set) var duplicates: [String] = []

    public init() {}

    /// For a `MenuItemSpec` id or a `StatusItemOverride.Entry` id. `isEnabled` is asked each time the menu opens, for
    /// `MenuItemSpec` items only: an override entry's own `Entry.isEnabled` alone decides (K35).
    public func onMenuItem(
        _ id: String, isEnabled: @escaping @MainActor () -> Bool = { true }, perform: @escaping @MainActor () -> Void
    ) {
        guard menuItems[id] == nil else { return duplicates.append("menu:\(id)") }
        menuItems[id] = MenuAction(isEnabled: isEnabled, perform: perform)
    }

    /// For a `HotkeySpec` id; Capture's registrar calls `performHotkey` when the key is pressed.
    public func onHotkey(_ id: String, perform: @escaping @MainActor () -> Void) {
        guard hotkeys[id] == nil else { return duplicates.append("hotkey:\(id)") }
        hotkeys[id] = perform
    }

    /// For a `QuickAccessActionSpec` id. Quick Access shows a spec only while it has a handler.
    public func onQuickAccessAction(_ id: String, _ handler: QuickAccessActionHandler) {
        guard quickAccess[id] == nil else { return duplicates.append("quickAccess:\(id)") }
        quickAccess[id] = handler
    }

    /// Opens a capture of this kind (Open Last Capture now; Find Capture and Spotlight later). One per kind.
    public func onOpen(_ kind: CaptureKind, perform: @escaping @MainActor (CaptureItem) -> Void) {
        guard openers[kind] == nil else { return duplicates.append("open:\(kind.rawValue)") }
        openers[kind] = perform
    }

    /// False when nothing is registered under the id. Never asks `isEnabled`.
    @discardableResult public func performMenuItem(_ id: String) -> Bool {
        guard let action = menuItems[id] else { return false }
        action.perform()
        return true
    }

    /// False when unregistered.
    public func isMenuItemEnabled(_ id: String) -> Bool {
        menuItems[id]?.isEnabled() ?? false
    }

    /// False when nothing is registered under the id.
    @discardableResult public func performHotkey(_ id: String) -> Bool {
        guard let perform = hotkeys[id] else { return false }
        perform()
        return true
    }

    public func quickAccessHandler(for id: String) -> QuickAccessActionHandler? {
        quickAccess[id]
    }

    public func canOpen(_ kind: CaptureKind) -> Bool {
        openers[kind] != nil
    }

    /// False when no opener is registered for the item's kind.
    @discardableResult public func open(_ item: CaptureItem) -> Bool {
        guard let opener = openers[item.kind] else { return false }
        opener(item)
        return true
    }
}
