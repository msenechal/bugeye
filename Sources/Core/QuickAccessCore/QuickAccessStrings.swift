/// Every user-visible Quick Access string, copied from the spec (§5). Tests check each character for character.
public enum QuickAccessStrings {
    // §5.1 strip and menu
    public static let copy = "Copy"
    public static let save = "Save"
    public static let saveAs = "Save As\u{2026}"
    public static let revealInFinder = "Reveal in Finder"
    public static let delete = "Delete"
    /// Before the suggested action's ⋯ menu title: U+2605 and a space.
    public static let suggestedPrefix = "\u{2605} "

    /// The selection host's one strip button: "Combine (3)".
    public static func selectionButtonTitle(_ title: String, count: Int) -> String {
        "\(title) (\(count))"
    }

    // §5.1 accessibility labels
    public static let dismissLabel = "Dismiss"
    public static let moreLabel = "More"

    // §5.3 notices
    public static let saveFailedTitle = "Couldn't save to folder"
    public static func folderUnavailableBody(path: String) -> String {
        "\(path) is unavailable. The capture stays in the temporary folder."
    }
    public static let saveAsFailedTitle = "Couldn't save a copy"
    public static let copyFailedTitle = "Couldn't copy"
    public static func copyFailedBody(name: String) -> String {
        "\(name) is missing or unreadable."
    }
    public static let deleteFailedTitle = "Delete failed"

    // §5.4 settings pane
    public static let paneTitle = "Quick Access"
    public static let autoDismissLabel = "Auto-dismiss"
    public static let never = "Never"
    public static func seconds(_ count: Int) -> String {
        "\(count) seconds"
    }
    public static let positionLabel = "Position"
    public static let bottomLeft = "Bottom left"
    public static let bottomRight = "Bottom right"
}
