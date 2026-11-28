import BugeyeCore
import BugeyeFeatures

/// Which strip button a tap came from.
public enum StripSlot: String, Hashable, Sendable {
    case copy, save, primary
    /// The selection host's one button, `<title> (N)`.
    case selection
}

public struct StripButton: Hashable, Sendable {
    public var slot: StripSlot
    /// `quickAccess.copy`, `quickAccess.save` / `quickAccess.saveAs`, the primary's or the `.selection` spec's id.
    public var actionID: String
    public var title: String
    public var isAccent: Bool
    public var hasRing: Bool
    public var isEnabled: Bool

    public init(slot: StripSlot, actionID: String, title: String, isAccent: Bool, hasRing: Bool, isEnabled: Bool) {
        self.slot = slot
        self.actionID = actionID
        self.title = title
        self.isAccent = isAccent
        self.hasRing = hasRing
        self.isEnabled = isEnabled
    }
}

/// One ⋯ menu item.
public struct MenuEntry: Hashable, Sendable {
    public var actionID: String
    /// With `★ ` before it when it is the suggested action.
    public var title: String
    public var isEnabled: Bool
    /// Non-empty: a submenu under the title.
    public var subitems: [QuickAccessSubitem]

    public init(actionID: String, title: String, isEnabled: Bool, subitems: [QuickAccessSubitem] = []) {
        self.actionID = actionID
        self.title = title
        self.isEnabled = isEnabled
        self.subitems = subitems
    }
}

/// The whole render of one thumbnail (spec §6). The view draws it and nothing else.
public struct ThumbnailState: Hashable, Sendable {
    public var id: CaptureID
    public var kind: CaptureKind
    /// Nil: the view draws a generic icon for the kind (plan P18).
    public var preview: PixelBuffer?
    public var isSelected: Bool
    public var strip: [StripButton]
    public var menu: [MenuEntry]
    public var moreHasRing: Bool
    public var sourceChip: ThumbnailDecoration?
    public var mediaBadge: ThumbnailDecoration?
    public var warningBadge: ThumbnailDecoration?

    public init(
        id: CaptureID, kind: CaptureKind, preview: PixelBuffer?, isSelected: Bool, strip: [StripButton],
        menu: [MenuEntry], moreHasRing: Bool, sourceChip: ThumbnailDecoration? = nil,
        mediaBadge: ThumbnailDecoration? = nil, warningBadge: ThumbnailDecoration? = nil
    ) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.isSelected = isSelected
        self.strip = strip
        self.menu = menu
        self.moreHasRing = moreHasRing
        self.sourceChip = sourceChip
        self.mediaBadge = mediaBadge
        self.warningBadge = warningBadge
    }
}
