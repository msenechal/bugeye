import AppKit
import BugeyeCore
import BugeyeFeatures
import QuickAccessCore
import SwiftUI

/// What a thumbnail's view can ask for. It holds only the capture's id and a weak controller, never an entry or
/// the model (spec §6.1 rule 12, `design/02` §5.8).
@MainActor
struct ThumbnailActions {
    let id: CaptureID
    weak var controller: QuickAccessController?

    func close() { controller?.handle(.closeTapped(id)) }
    func strip(_ button: StripButton) {
        if button.slot == .selection {
            controller?.handle(.selectionActionTapped)
        } else {
            controller?.handle(.stripTapped(id, button.slot))
        }
    }
    func menu(_ actionID: String, subitemID: String? = nil) {
        controller?.handle(.menuChosen(id, actionID: actionID, subitemID: subitemID))
    }
    func decoration(_ actionID: String) { controller?.handle(.decorationTapped(id, actionID: actionID)) }
    func click(shift: Bool) { controller?.handle(.imageClicked(id, shift: shift)) }
    func doubleClick() { controller?.handle(.imageDoubleClicked(id)) }
    func hover(_ inside: Bool) { controller?.hover(id, inside: inside) }

    /// The file at the capture's current URL, asked at drag start (after Save it's the moved file).
    func dragProvider() -> NSItemProvider {
        guard let url = controller?.currentURL(id), let provider = NSItemProvider(contentsOf: url) else {
            return NSItemProvider()
        }
        return provider
    }
}

/// Draws a `ThumbnailState` and nothing else (spec §4, §6). 240 × 176 pt: image 136, strip 40.
struct ThumbnailView: View {
    let state: ThumbnailState
    let image: CGImage?
    let actions: ThumbnailActions

    private var accent: SwiftUI.Color { NightChrome.color(NightChrome.accentHex) }

    var body: some View {
        VStack(spacing: 0) {
            imageArea
                .frame(width: QuickAccessLayout.thumbnailWidth, height: QuickAccessLayout.imageHeight)
            strip
                .frame(width: QuickAccessLayout.thumbnailWidth, height: QuickAccessLayout.stripHeight)
        }
        .frame(width: QuickAccessLayout.thumbnailWidth, height: QuickAccessLayout.thumbnailHeight)
        .nightPanel()
        .overlay {
            if state.isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { actions.hover($0) }
    }

    // MARK: Image area

    private var imageArea: some View {
        ZStack {
            picture
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { actions.doubleClick() }
                .simultaneousGesture(
                    TapGesture().onEnded { actions.click(shift: NSEvent.modifierFlags.contains(.shift)) }
                )
                .onDrag { actions.dragProvider() }
            overlays
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: QuickAccessLayout.thumbnailWidth, height: QuickAccessLayout.imageHeight)
                .clipped()
        } else {
            // No preview: a generic icon for the kind (plan P18).
            Image(systemName: Self.symbol(for: state.kind))
                .font(.system(size: 36, weight: .light))
                .frame(width: QuickAccessLayout.thumbnailWidth, height: QuickAccessLayout.imageHeight)
        }
    }

    static func symbol(for kind: CaptureKind) -> String {
        switch kind {
        case .screenshot: "photo"
        case .recording, .gif: "film"
        case .collection: "square.stack"
        }
    }

    private var overlays: some View {
        ZStack {
            VStack {
                HStack(alignment: .top, spacing: 6) {
                    Button(action: actions.close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 20, height: 20)
                            .background(SwiftUI.Color.black.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(QuickAccessStrings.dismissLabel)
                    if case .sourceChip(let label, _, let actionID)? = state.sourceChip {
                        Button {
                            if let actionID { actions.decoration(actionID) }
                        } label: {
                            Text(label).font(.system(size: 11)).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(SwiftUI.Color.black.opacity(0.6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if state.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(accent)
                            .allowsHitTesting(false)  // clicks and drags reach the image (Q11; review of #11, I2)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    if case .warningBadge(let text, let tooltip, let actionID)? = state.warningBadge {
                        Button {
                            if let actionID { actions.decoration(actionID) }
                        } label: {
                            Text(text).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NightChrome.color(NightChrome.textOnAccentHex))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(SwiftUI.Color.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(tooltip ?? "")
                    }
                    HStack {
                        Spacer(minLength: 0)
                        if case .mediaBadge(let text)? = state.mediaBadge {
                            Text(text).font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(SwiftUI.Color.black.opacity(0.6), in: Capsule())
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: Strip

    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(state.strip, id: \.actionID) { button in
                Button(button.title) { actions.strip(button) }
                    .buttonStyle(NightButtonStyle(accent: button.isAccent))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    .disabled(!button.isEnabled)
                    .overlay { if button.hasRing { ring } }
            }
            if !state.menu.isEmpty, state.strip.first?.slot != .selection {
                moreMenu
            }
        }
        .padding(8)
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(accent, lineWidth: 1.5)
    }

    private var moreMenu: some View {
        Menu {
            ForEach(state.menu, id: \.actionID) { entry in
                if entry.subitems.isEmpty {
                    Button(entry.title) { actions.menu(entry.actionID) }
                        .disabled(!entry.isEnabled)
                } else {
                    Menu(entry.title) {
                        ForEach(entry.subitems, id: \.id) { subitem in
                            Button(subitem.title) { actions.menu(entry.actionID, subitemID: subitem.id) }
                        }
                    }
                    .disabled(!entry.isEnabled)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .background(
            SwiftUI.Color.white.opacity(NightChrome.controlFillOpacity),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay { if state.moreHasRing { ring } }
        .accessibilityLabel(QuickAccessStrings.moreLabel)
    }
}
