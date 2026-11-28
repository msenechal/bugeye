import BugeyeCore
import BugeyeFeatures

/// Quick Access as a feature module (spec §7): its Settings pane and its two ⋯ menu items. Copy, Save and Save As…
/// are strip slots, not specs. Its handlers are registered by `QuickAccessWiring`.
public struct QuickAccessModule: FeatureModule {
    public static let moduleID = "quickAccess"
    public static let revealSpec = QuickAccessActionSpec(
        id: QuickAccessActionID.reveal, title: QuickAccessStrings.revealInFinder, order: 800, placement: .menu)
    public static let deleteSpec = QuickAccessActionSpec(
        id: QuickAccessActionID.delete, title: QuickAccessStrings.delete, order: 1000, placement: .menu)
    public static let settingsSectionSpec = SettingsSectionSpec(
        id: moduleID, title: QuickAccessStrings.paneTitle, order: 20)

    public init() {}

    public var id: String { Self.moduleID }

    public func settingsSection() -> SettingsSectionSpec? { Self.settingsSectionSpec }

    public func quickAccessActions() -> [QuickAccessActionSpec] { [Self.revealSpec, Self.deleteSpec] }
}
