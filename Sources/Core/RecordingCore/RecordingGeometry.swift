import BugeyeCore
import Foundation

public struct PixelSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Output sizes, codec limits and bitrates (`design/04` §2.6–2.7).
public enum RecordingGeometry {
    /// The encoder's limit, long side × short side: H.264 4096 × 2304, HEVC 8192 × 4320.
    public static func limit(_ codec: VideoCodec) -> (long: Double, short: Double) {
        switch codec {
        case .h264: (4096, 2304)
        case .hevc: (8192, 4320)
        }
    }

    /// Points × scale, shrunk into the codec's limit keeping the aspect, rounded down to even numbers, at least
    /// 2 × 2.
    public static func outputSize(points: Size2D, scale: Double, codec: VideoCodec) -> PixelSize {
        let width = max(points.width * scale, 0)
        let height = max(points.height * scale, 0)
        let (longLimit, shortLimit) = limit(codec)
        let long = max(width, height)
        let short = min(width, height)
        var factor = 1.0
        if long > 0 { factor = min(factor, longLimit / long) }
        if short > 0 { factor = min(factor, shortLimit / short) }
        func even(_ value: Double) -> Int {
            let whole = Int((value + 1e-6).rounded(.down))
            return max(whole - whole % 2, 2)
        }
        return PixelSize(width: even(width * factor), height: even(height * factor))
    }

    /// Bits per second: width × height × fps × 0.06 (Standard) or 0.12 (High), clamped to 2–100 Mbit/s.
    public static func bitrate(_ size: PixelSize, fps: Int, quality: RecordingQuality) -> Int {
        let factor = quality == .high ? 0.12 : 0.06
        let bits = Double(size.width) * Double(size.height) * Double(fps) * factor
        return Int(min(max(bits, 2_000_000), 100_000_000).rounded())
    }

    /// A display-local area grown to whole points, at least 2 × 2, inside the display.
    public static func clampedSourceRect(_ area: Rect2D, display: Size2D) -> Rect2D {
        let r = area.standardized
        var x = r.minX.rounded(.down)
        var y = r.minY.rounded(.down)
        var width = max(r.maxX.rounded(.up) - x, 2)
        var height = max(r.maxY.rounded(.up) - y, 2)
        width = min(width, display.width)
        height = min(height, display.height)
        x = min(max(x, 0), display.width - width)
        y = min(max(y, 0), display.height - height)
        return Rect2D(x: x, y: y, width: width, height: height)
    }
}

/// Where the options bar goes (§5.1): under the selection, 12 pt away; above it when it doesn't fit; inside the
/// bottom edge for a whole display or when neither fits. Centred on the selection, kept on the screen.
/// Top-left, y-down, screen points.
public enum OptionsBarPlacement {
    public static let gap = 12.0

    public static func origin(bar: Size2D, selection: Rect2D, screen: Rect2D, wholeDisplay: Bool) -> Point2D {
        let x = min(max(selection.minX + selection.width / 2 - bar.width / 2, screen.minX), screen.maxX - bar.width)
        let under = selection.maxY + gap
        let above = selection.minY - gap - bar.height
        let y: Double
        if !wholeDisplay, under + bar.height <= screen.maxY {
            y = under
        } else if !wholeDisplay, above >= screen.minY {
            y = above
        } else {
            y = min(selection.maxY, screen.maxY) - gap - bar.height
        }
        return Point2D(x: x, y: y)
    }
}

/// A window's frame and owner as the window server lists it (Quartz global, top-left).
public struct WindowSnapshot: Hashable, Sendable {
    public var id: WindowID
    public var processID: Int32
    public var layer: Int
    public var frame: Rect2D

    public init(id: WindowID, processID: Int32, layer: Int, frame: Rect2D) {
        self.id = id
        self.processID = processID
        self.layer = layer
        self.frame = frame
    }
}

/// Window recording follows the window at its starting size (§5.5).
public enum WindowFollow {
    /// The display-local source rect: the window's origin, the starting size, rounded to whole points and
    /// clamped into the display. `windowBounds` and `displayBounds` in the same global points.
    public static func followedRect(windowBounds: Rect2D, size: Size2D, displayBounds: Rect2D) -> Rect2D {
        let width = min(size.width, displayBounds.width)
        let height = min(size.height, displayBounds.height)
        let x = min(max((windowBounds.minX - displayBounds.minX).rounded(), 0), displayBounds.width - width)
        let y = min(max((windowBounds.minY - displayBounds.minY).rounded(), 0), displayBounds.height - height)
        return Rect2D(x: x, y: y, width: width, height: height)
    }
}

/// A window recording's child windows (V10): the same process, layer above 0 (menus, pop-ups, sheets), frame
/// meeting the followed rect.
public enum ChildWindowFilter {
    public static func children(of window: WindowID, in windows: [WindowSnapshot], followed: Rect2D) -> [WindowID] {
        guard let owner = windows.first(where: { $0.id == window }) else { return [] }
        return windows.filter {
            $0.id != window && $0.processID == owner.processID && $0.layer > 0
                && $0.frame.intersection(followed) != nil
        }.map(\.id)
    }
}

/// V10 / V23: if a filter update is followed by more than 2 consecutive dropped frames, the recording drops
/// back to the window alone for the rest of the take.
public struct ChildWindowFallback: Hashable, Sendable {
    public static let maxDroppedFrames = 2

    public private(set) var useWindowAlone = false
    private var watching = false
    private var dropped = 0

    public init() {}

    public mutating func filterUpdated() {
        watching = true
        dropped = 0
    }

    public mutating func frameDropped() {
        guard watching else { return }
        dropped += 1
        if dropped > Self.maxDroppedFrames { useWindowAlone = true }
    }

    public mutating func frameDelivered() {
        watching = false
        dropped = 0
    }
}

public enum BubbleCorner: Hashable, Sendable, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

/// The webcam bubble's place (§5.4): a corner of the area, 24 pt in; centred on an axis where the area is too
/// small. Top-left, y-down points.
public enum BubbleLayout {
    public static let inset = 24.0

    public static func frame(corner: BubbleCorner, size: BubbleSize, area: Rect2D) -> Rect2D {
        let d = size.diameter
        func place(min: Double, length: Double, atStart: Bool) -> Double {
            guard length >= d + 2 * inset else { return min + length / 2 - d / 2 }
            return atStart ? min + inset : min + length - inset - d
        }
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        return Rect2D(
            x: place(min: area.minX, length: area.width, atStart: left),
            y: place(min: area.minY, length: area.height, atStart: top), width: d, height: d)
    }

    /// The corner nearest a dropped bubble's centre.
    public static func corner(nearest point: Point2D, area: Rect2D) -> BubbleCorner {
        let left = point.x < area.minX + area.width / 2
        let top = point.y < area.minY + area.height / 2
        switch (top, left) {
        case (true, true): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }
}

/// What the shell does to its bubble to match the flow's wish (`design/04` §2.12).
public enum BubbleChange: Hashable, Sendable {
    case none, create, remove, resize
    /// Another camera needs a new capture session; the bubble keeps its corner.
    case recreate

    public static func decide(current: BubbleWish?, wish: BubbleWish?) -> BubbleChange {
        switch (current, wish) {
        case (nil, nil): .none
        case (nil, _?): .create
        case (_?, nil): .remove
        case (let current?, let wish?):
            current.cameraDevice != wish.cameraDevice ? .recreate : current.size != wish.size ? .resize : .none
        }
    }
}
