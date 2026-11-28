import BugeyeCore
import BugeyeFeatures

/// One action the user took on a thumbnail, for the habits epic (spec §3; it promotes this type later, K3).
public struct PerformedQuickAccessAction: Hashable, Sendable {
    public var actionID: String
    public var captureID: CaptureID
    public var kind: CaptureKind
    public var trigger: QuickAccessTrigger

    public init(actionID: String, captureID: CaptureID, kind: CaptureKind, trigger: QuickAccessTrigger) {
        self.actionID = actionID
        self.captureID = captureID
        self.kind = kind
        self.trigger = trigger
    }
}

/// The feed of performed actions (plan P15). Observers live as long as the app.
@MainActor
public final class QuickAccessActivity {
    public static let recentLimit = 50

    public private(set) var recent: [PerformedQuickAccessAction] = []
    private var observers: [@MainActor (PerformedQuickAccessAction) -> Void] = []

    public init() {}

    public func record(_ action: PerformedQuickAccessAction) {
        recent.append(action)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
        for observer in observers { observer(action) }
    }

    public func observe(_ handler: @escaping @MainActor (PerformedQuickAccessAction) -> Void) {
        observers.append(handler)
    }
}
