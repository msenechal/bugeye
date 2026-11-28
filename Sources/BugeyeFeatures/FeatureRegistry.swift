/// Why a set of modules can't be registered together.
public enum FeatureConflict: Hashable, Sendable {
    case duplicateModule(String)
    case duplicateMenuItem(String)
    case menuSlotTaken(MenuSlot, ids: [String])
    case duplicateHotkey(String)
    case hotkeyTaken(KeyCombo, ids: [String])
    case settingKeyTaken(String, ids: [String])
    case duplicateSettingsSection(String)
    case duplicateQuickAccessAction(String)
}

public struct FeatureRegistryError: Error, Hashable, Sendable {
    public let conflicts: [FeatureConflict]
    public init(conflicts: [FeatureConflict]) { self.conflicts = conflicts }
}

/// The registered modules, checked so that no two claim the same id, menu slot, hotkey or setting.
public struct FeatureRegistry: Sendable {
    public let modules: [any FeatureModule]

    public init(_ modules: [any FeatureModule]) throws(FeatureRegistryError) {
        let conflicts = Self.conflicts(in: modules)
        guard conflicts.isEmpty else { throw FeatureRegistryError(conflicts: conflicts) }
        self.modules = modules
    }

    public var moduleIDs: [String] { modules.map(\.id) }

    /// Every menu item, sorted by group then order.
    public var menuItems: [MenuItemSpec] {
        modules.flatMap { $0.menuItems() }.sorted { ($0.slot.group, $0.slot.order) < ($1.slot.group, $1.slot.order) }
    }

    public var settingsSections: [SettingsSectionSpec] {
        modules.compactMap { $0.settingsSection() }.sorted { $0.order < $1.order }
    }

    public var hotkeys: [HotkeySpec] { modules.flatMap { $0.hotkeys() } }

    public var quickAccessActions: [QuickAccessActionSpec] {
        modules.flatMap { $0.quickAccessActions() }.sorted { $0.order < $1.order }
    }

    /// Every conflict, in a stable order (the order modules and their specs were given).
    public static func conflicts(in modules: [any FeatureModule]) -> [FeatureConflict] {
        var conflicts: [FeatureConflict] = []
        conflicts += duplicates(modules.map(\.id)).map { .duplicateModule($0) }

        let menu = modules.flatMap { $0.menuItems() }
        conflicts += duplicates(menu.map(\.id)).map { .duplicateMenuItem($0) }
        conflicts += clashes(menu, by: \.slot).map { .menuSlotTaken($0.key, ids: $0.ids) }

        let hotkeys = modules.flatMap { $0.hotkeys() }
        conflicts += duplicates(hotkeys.map(\.id)).map { .duplicateHotkey($0) }
        conflicts += clashes(hotkeys, by: \.defaultKey).map { .hotkeyTaken($0.key, ids: $0.ids) }
        conflicts += clashes(hotkeys, by: \.settingKey).map { .settingKeyTaken($0.key, ids: $0.ids) }

        let sections = modules.compactMap { $0.settingsSection() }
        conflicts += duplicates(sections.map(\.id)).map { .duplicateSettingsSection($0) }

        let actions = modules.flatMap { $0.quickAccessActions() }
        conflicts += duplicates(actions.map(\.id)).map { .duplicateQuickAccessAction($0) }
        return conflicts
    }

    private static func duplicates(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var reported: [String] = []
        for value in values where !seen.insert(value).inserted && !reported.contains(value) {
            reported.append(value)
        }
        return reported
    }

    private struct Clash<Key> {
        let key: Key
        let ids: [String]
    }

    /// Keys claimed by more than one distinct id, in first-seen order.
    private static func clashes<Item: IdentifiedSpec, Key: Hashable>(_ items: [Item], by key: (Item) -> Key)
        -> [Clash<Key>]
    {
        var order: [Key] = []
        var ids: [Key: [String]] = [:]
        for item in items {
            let k = key(item)
            if ids[k] == nil { order.append(k) }
            ids[k, default: []].append(item.id)
        }
        return order.compactMap { k in
            let claimed = ids[k]!
            return Set(claimed).count > 1 ? Clash(key: k, ids: claimed) : nil
        }
    }
}

protocol IdentifiedSpec {
    var id: String { get }
}

extension MenuItemSpec: IdentifiedSpec {}
extension HotkeySpec: IdentifiedSpec {}
