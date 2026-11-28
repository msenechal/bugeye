import BugeyeCore

/// The ⇧-click selection (`design/02` §1.4, spec §6.1 rule 7). `ids` are in click order.
public struct QuickAccessSelection: Hashable, Sendable {
    public private(set) var ids: [CaptureID] = []

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    public func contains(_ id: CaptureID) -> Bool { ids.contains(id) }

    /// The most recently ⇧-clicked id still selected.
    public var host: CaptureID? { ids.last }

    public mutating func toggle(_ id: CaptureID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    public mutating func remove(_ id: CaptureID) {
        ids.removeAll { $0 == id }
    }

    public mutating func clear() {
        ids = []
    }

    /// The selected ids in stack order (oldest first), for a `.selection` action.
    public func ordered(byStack stack: [CaptureID]) -> [CaptureID] {
        stack.filter(contains)
    }
}
