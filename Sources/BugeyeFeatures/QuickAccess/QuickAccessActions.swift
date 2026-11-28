import BugeyeCore

public enum QuickAccessTrigger: Hashable, Sendable { case strip, menu, doubleClick, decoration, selection }

public struct QuickAccessSubitem: Hashable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Asked at every render of a thumbnail.
public enum QuickAccessActionState: Hashable, Sendable {
    case enabled, disabled, hidden
    /// A submenu under the action's title.
    case submenu([QuickAccessSubitem])
}

public struct QuickAccessActionContext: Hashable, Sendable {
    public var actionID: String
    /// The thumbnail's item; for `.selection`, the selected items in stack order, oldest first.
    public var items: [CaptureItem]
    public var trigger: QuickAccessTrigger
    public var subitemID: String?

    public init(actionID: String, items: [CaptureItem], trigger: QuickAccessTrigger, subitemID: String? = nil) {
        self.actionID = actionID
        self.items = items
        self.trigger = trigger
        self.subitemID = subitemID
    }
}

/// What a module registers for one of its `QuickAccessActionSpec`s (`ActionRouter.onQuickAccessAction`).
public struct QuickAccessActionHandler: Sendable {
    public var state: @MainActor @Sendable (CaptureItem) -> QuickAccessActionState
    public var perform: @MainActor @Sendable (QuickAccessActionContext) -> Void

    public init(
        state: @escaping @MainActor @Sendable (CaptureItem) -> QuickAccessActionState = { _ in .enabled },
        perform: @escaping @MainActor @Sendable (QuickAccessActionContext) -> Void
    ) {
        self.state = state
        self.perform = perform
    }
}
