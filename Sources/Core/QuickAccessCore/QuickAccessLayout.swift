import BugeyeCore

/// Thumbnail sizes and the stack's frames (spec §4, §6.1 rule 3). Cocoa points: origin bottom-left, y up.
public enum QuickAccessLayout {
    public static let thumbnailWidth = 240.0
    public static let thumbnailHeight = 176.0
    public static let imageHeight = 136.0
    public static let stripHeight = 40.0
    /// From the visible frame's edges.
    public static let margin = 16.0
    /// Between thumbnails.
    public static let gap = 10.0

    /// Every id's frame in `anchor` (the visible frame of one display); `ids` oldest first, the newest at the bottom.
    public static func frames(for ids: [CaptureID], anchor: Rect2D, position: QuickAccessPosition) -> [CaptureID:
        Rect2D]
    {
        let x =
            switch position {
            case .bottomLeft: anchor.minX + margin
            case .bottomRight: anchor.maxX - margin - thumbnailWidth
            }
        var frames: [CaptureID: Rect2D] = [:]
        for (index, id) in ids.reversed().enumerated() {
            let y = anchor.minY + margin + Double(index) * (thumbnailHeight + gap)
            frames[id] = Rect2D(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
        }
        return frames
    }
}
