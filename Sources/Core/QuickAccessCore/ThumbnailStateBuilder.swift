import BugeyeCore
import BugeyeFeatures

/// Builds a `ThumbnailState` from the item, the registry's specs, their handlers and the decorations (spec §5.1,
/// §6.1 rule 10). A spec is shown only for its kinds and while it has a handler; each handler's state is asked here,
/// at render time.
@MainActor
public enum ThumbnailStateBuilder {
    public struct Output: Hashable, Sendable {
        public var state: ThumbnailState
        /// The case names of decorations that lost to an earlier one of the same case, in order (to be logged).
        public var ignoredDecorations: [String]
    }

    /// - Parameter selectionHostCount: the selection's size when this thumbnail is the selection host, else nil.
    public static func build(
        item: CaptureItem, preview: PixelBuffer?, isSelected: Bool, selectionHostCount: Int?,
        specs: [QuickAccessActionSpec], handler: (String) -> QuickAccessActionHandler?,
        decorations: [ThumbnailDecoration]
    ) -> Output {
        var drawn = Drawn()
        var ignored: [String] = []
        for decoration in decorations where !drawn.take(decoration) {
            ignored.append(Drawn.caseName(decoration))
        }
        let suggested = drawn.suggestedActionID

        let offered = specs.filter { $0.kinds.contains(item.kind) }
        var strip: [StripButton]
        if let host = selectionButton(offered: offered, item: item, count: selectionHostCount, handler: handler) {
            strip = [host]
        } else {
            let saveID = item.isSaved ? QuickAccessActionID.saveAs : QuickAccessActionID.save
            strip = [
                StripButton(
                    slot: .copy, actionID: QuickAccessActionID.copy, title: QuickAccessStrings.copy, isAccent: false,
                    hasRing: suggested == QuickAccessActionID.copy, isEnabled: true),
                StripButton(
                    slot: .save, actionID: saveID,
                    title: item.isSaved ? QuickAccessStrings.saveAs : QuickAccessStrings.save,
                    isAccent: false,
                    hasRing: suggested == QuickAccessActionID.save || suggested == QuickAccessActionID.saveAs,
                    isEnabled: true),
            ]
            if let primary = offered.first(where: { $0.placement == .primary }), let found = handler(primary.id) {
                strip.append(
                    StripButton(
                        slot: .primary, actionID: primary.id, title: primary.title, isAccent: true,
                        hasRing: suggested == primary.id, isEnabled: found.state(item) != .disabled))
            }
        }

        var menu: [MenuEntry] = []
        for spec in offered.filter({ $0.placement == .menu }).sorted(by: { $0.order < $1.order }) {
            guard let found = handler(spec.id) else { continue }
            let title = spec.id == suggested ? QuickAccessStrings.suggestedPrefix + spec.title : spec.title
            switch found.state(item) {
            case .hidden: continue
            case .enabled: menu.append(MenuEntry(actionID: spec.id, title: title, isEnabled: true))
            case .disabled: menu.append(MenuEntry(actionID: spec.id, title: title, isEnabled: false))
            case .submenu(let subitems):
                menu.append(MenuEntry(actionID: spec.id, title: title, isEnabled: true, subitems: subitems))
            }
        }
        let ringedOnStrip = strip.contains(where: \.hasRing)
        let suggestedInMenu = suggested.map { id in menu.contains { $0.actionID == id } } ?? false
        let moreHasRing = suggestedInMenu && !ringedOnStrip

        let state = ThumbnailState(
            id: item.id, kind: item.kind, preview: preview, isSelected: isSelected, strip: strip, menu: menu,
            moreHasRing: moreHasRing, sourceChip: drawn.sourceChip, mediaBadge: drawn.mediaBadge,
            warningBadge: drawn.warningBadge)
        return Output(state: state, ignoredDecorations: ignored)
    }

    /// The host's `<title> (N)` button: a `.selection` spec with a handler that doesn't hide it, two or more selected.
    private static func selectionButton(
        offered specs: [QuickAccessActionSpec], item: CaptureItem, count: Int?,
        handler: (String) -> QuickAccessActionHandler?
    ) -> StripButton? {
        guard let count, count >= 2, let spec = specs.first(where: { $0.placement == .selection }),
            let found = handler(spec.id)
        else { return nil }
        let state = found.state(item)
        guard state != .hidden else { return nil }
        return StripButton(
            slot: .selection, actionID: spec.id,
            title: QuickAccessStrings.selectionButtonTitle(spec.title, count: count),
            isAccent: true, hasRing: false, isEnabled: state != .disabled)
    }

    /// The first decoration of each case.
    private struct Drawn {
        var sourceChip: ThumbnailDecoration?
        var mediaBadge: ThumbnailDecoration?
        var warningBadge: ThumbnailDecoration?
        var suggestedActionID: String?

        /// False when one of the same case was already taken.
        mutating func take(_ decoration: ThumbnailDecoration) -> Bool {
            switch decoration {
            case .sourceChip:
                guard sourceChip == nil else { return false }
                sourceChip = decoration
            case .mediaBadge:
                guard mediaBadge == nil else { return false }
                mediaBadge = decoration
            case .warningBadge:
                guard warningBadge == nil else { return false }
                warningBadge = decoration
            case .suggestedAction(let id):
                guard suggestedActionID == nil else { return false }
                suggestedActionID = id
            }
            return true
        }

        static func caseName(_ decoration: ThumbnailDecoration) -> String {
            switch decoration {
            case .sourceChip: "sourceChip"
            case .mediaBadge: "mediaBadge"
            case .warningBadge: "warningBadge"
            case .suggestedAction: "suggestedAction"
            }
        }
    }
}
