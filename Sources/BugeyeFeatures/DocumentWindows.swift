public enum ActivationPolicy: Hashable, Sendable { case accessory, regular }

/// Counts open document windows (editors now, collection windows later).
@MainActor
public final class DocumentWindows {
    private let apply: @MainActor (ActivationPolicy) -> Void
    private let onUnderflow: @MainActor () -> Void
    public private(set) var openCount = 0
    public private(set) var underflows = 0

    /// `onUnderflow` runs on each `closed()` below 0, so the shell can log its fault (K37).
    public init(
        apply: @escaping @MainActor (ActivationPolicy) -> Void, onUnderflow: @escaping @MainActor () -> Void = {}
    ) {
        self.apply = apply
        self.onUnderflow = onUnderflow
    }

    /// 0 → 1 applies `.regular`.
    public func opened() {
        openCount += 1
        if openCount == 1 { apply(.regular) }
    }

    /// 1 → 0 applies `.accessory`. Below 0 the count stays 0 and `underflows` increments; the shell logs a fault (K37).
    public func closed() {
        guard openCount > 0 else {
            underflows += 1
            onUnderflow()
            return
        }
        openCount -= 1
        if openCount == 0 { apply(.accessory) }
    }
}
