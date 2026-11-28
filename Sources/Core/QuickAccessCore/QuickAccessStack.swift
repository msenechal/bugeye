/// The bounded thumbnail stack (`design/02` §2.12, spec §6.1 rule 2): items oldest first.
public struct QuickAccessStack<Item: Identifiable> {
    /// The most thumbnails ever shown.
    public static var capacity: Int { 5 }

    public private(set) var items: [Item] = []

    public init() {}

    /// How many thumbnails fit a visible height: `max(1, floor((h − 2·16 + 10) / (176 + 10)))`.
    public static func fitting(height: Double) -> Int {
        let slot = QuickAccessLayout.thumbnailHeight + QuickAccessLayout.gap
        let room = height - 2 * QuickAccessLayout.margin + QuickAccessLayout.gap
        return max(1, Int((room / slot).rounded(.down)))
    }

    /// `min(5, fitting(height:))`.
    public static func limit(height: Double) -> Int {
        min(capacity, fitting(height: height))
    }

    /// Appends `item`, then evicts from the oldest, skipping `sparing` (the hovered id) and never the new item,
    /// until the count fits `min(capacity, limit)` or only those two remain. Returns the evicted items, oldest first.
    @discardableResult
    public mutating func push(_ item: Item, limit: Int, sparing: Item.ID?) -> [Item] {
        items.append(item)
        let bound = max(1, min(Self.capacity, limit))
        var evicted: [Item] = []
        var index = 0
        while items.count > bound, index < items.count - 1 {
            if items[index].id == sparing {
                index += 1
            } else {
                evicted.append(items.remove(at: index))
            }
        }
        return evicted
    }

    @discardableResult
    public mutating func remove(_ id: Item.ID) -> Item? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }
}
