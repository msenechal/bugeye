import BugeyeCore
import BugeyeFeatures

/// The editor's registration (E2): the Quick Access Edit action and the status menu's Open Last Capture.
public struct EditorModule: FeatureModule {
    public static let id = "editor"
    public static let editActionID = "editor.edit"
    public static let openLastCaptureID = "editor.openLastCapture"

    public init() {}

    public var id: String { Self.id }

    public func quickAccessActions() -> [QuickAccessActionSpec] {
        [
            QuickAccessActionSpec(
                id: Self.editActionID, title: EditorStrings.editAction, order: 0, placement: .primary,
                kinds: [.screenshot])
        ]
    }

    public func menuItems() -> [MenuItemSpec] {
        [
            MenuItemSpec(
                id: Self.openLastCaptureID, title: EditorStrings.openLastCapture, slot: MenuSlot(.library, order: 0))
        ]
    }
}
