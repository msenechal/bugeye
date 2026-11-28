import BugeyeCore

public enum ThumbnailDecoration: Hashable, Sendable {
    /// Top of the image, right of ✕: app icon + short label (provenance). Tapping runs `actionID`.
    case sourceChip(label: String, appBundleID: String?, actionID: String?)
    /// Bottom-right corner: "▶ 00:42" (Recording, K12), "GIF".
    case mediaBadge(text: String)
    /// Bottom edge, centred, amber capsule. Tapping runs `actionID`.
    case warningBadge(text: String, tooltip: String?, actionID: String?)
    /// The learned usual action: a ring on its strip button, else on ⋯ plus "★ " before its menu title.
    case suggestedAction(actionID: String)
}

/// What each provider shows on a capture's Quick Access thumbnail. Quick Access draws them.
@MainActor
public final class ThumbnailDecorations {
    private var byCapture: [CaptureID: [(provider: String, decorations: [ThumbnailDecoration])]] = [:]
    private var observers: [@MainActor (CaptureID) -> Void] = []
    private var subscription: CaptureSubscription?

    /// Subscribes to `bus`: a `deleted` event drops every provider's decorations for that capture (K36) and
    /// tells the observers (plan P7).
    public init(bus: CaptureEventBus) {
        subscription = bus.subscribe { [weak self] event in
            guard let self, event.change == .deleted, self.byCapture.removeValue(forKey: event.item.id) != nil
            else { return }
            self.notify(event.item.id)
        }
    }

    /// Replaces everything `provider` shows on `capture`; [] removes it.
    public func set(_ decorations: [ThumbnailDecoration], for capture: CaptureID, from provider: String) {
        var entries = byCapture[capture] ?? []
        if let index = entries.firstIndex(where: { $0.provider == provider }) {
            if decorations.isEmpty {
                entries.remove(at: index)
            } else {
                entries[index].decorations = decorations
            }
        } else if !decorations.isEmpty {
            entries.append((provider, decorations))
        }
        byCapture[capture] = entries.isEmpty ? nil : entries
        notify(capture)
    }

    /// All providers' decorations, providers in first-set order.
    public func decorations(for capture: CaptureID) -> [ThumbnailDecoration] {
        (byCapture[capture] ?? []).flatMap(\.decorations)
    }

    /// Called after every `set`, with the capture it changed. Observers live as long as the app.
    public func observe(_ handler: @escaping @MainActor (CaptureID) -> Void) {
        observers.append(handler)
    }

    private func notify(_ capture: CaptureID) {
        for observer in observers { observer(capture) }
    }
}
