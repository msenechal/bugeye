import BugeyeCore
import Foundation

// design/02 §2.2's five spaces as types (Capture §4). There are no implicit conversions: the only bridges are the
// named functions below, so a missing or doubled flip doesn't compile.

/// Cocoa global: origin at the bottom-left of the primary display, y up, points.
public struct CocoaPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    /// y' = primaryHeight − y.
    public func toQuartz(primaryHeight: Double) -> QuartzPoint { QuartzPoint(x: x, y: primaryHeight - y) }
}

/// Cocoa global rect (see `CocoaPoint`).
public struct CocoaRect: Hashable, Sendable {
    public var raw: Rect2D
    public init(_ raw: Rect2D) { self.raw = raw.standardized }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(Rect2D(x: x, y: y, width: width, height: height))
    }
    /// y' = primaryHeight − maxY.
    public func toQuartz(primaryHeight: Double) -> QuartzRect {
        QuartzRect(x: raw.minX, y: primaryHeight - raw.maxY, width: raw.width, height: raw.height)
    }
    public func contains(_ point: CocoaPoint) -> Bool { raw.contains(Point2D(x: point.x, y: point.y)) }
    /// Max edges included: `NSEvent.mouseLocation` reports `y == maxY` on a display's top row.
    public func containsClosed(_ point: CocoaPoint) -> Bool {
        point.x >= raw.minX && point.x <= raw.maxX && point.y >= raw.minY && point.y <= raw.maxY
    }
}

/// Quartz global: origin at the top-left of the primary display, y down, points.
public struct QuartzPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public func toCocoa(primaryHeight: Double) -> CocoaPoint { CocoaPoint(x: x, y: primaryHeight - y) }
}

/// Quartz global rect (see `QuartzPoint`).
public struct QuartzRect: Hashable, Sendable {
    public var raw: Rect2D
    public init(_ raw: Rect2D) { self.raw = raw.standardized }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(Rect2D(x: x, y: y, width: width, height: height))
    }
    public func toCocoa(primaryHeight: Double) -> CocoaRect {
        CocoaRect(x: raw.minX, y: primaryHeight - raw.maxY, width: raw.width, height: raw.height)
    }
    public func contains(_ point: QuartzPoint) -> Bool { raw.contains(Point2D(x: point.x, y: point.y)) }
    public var centre: QuartzPoint { QuartzPoint(x: raw.minX + raw.width / 2, y: raw.minY + raw.height / 2) }
    /// This rect relative to a display's top-left corner.
    public func displayLocal(displayQuartzFrame display: QuartzRect) -> DisplayRect {
        DisplayRect(
            x: raw.minX - display.raw.minX, y: raw.minY - display.raw.minY, width: raw.width, height: raw.height)
    }
}

/// One overlay view's own space: origin at its bottom-left, y up, points. The view covers its display's frame.
public struct ViewPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    /// y' = displayHeight − y.
    public func displayLocal(displayHeight: Double) -> DisplayPoint { DisplayPoint(x: x, y: displayHeight - y) }
}

/// A rect in one overlay view (see `ViewPoint`).
public struct ViewRect: Hashable, Sendable {
    public var raw: Rect2D
    public init(_ raw: Rect2D) { self.raw = raw.standardized }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(Rect2D(x: x, y: y, width: width, height: height))
    }
    /// y' = displayHeight − maxY.
    public func displayLocal(displayHeight: Double) -> DisplayRect {
        DisplayRect(x: raw.minX, y: displayHeight - raw.maxY, width: raw.width, height: raw.height)
    }
}

/// Display-local: origin at the top-left of one display, y down, points.
public struct DisplayPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public func viewPoint(displayHeight: Double) -> ViewPoint { ViewPoint(x: x, y: displayHeight - y) }
    public func quartz(displayQuartzFrame display: QuartzRect) -> QuartzPoint {
        QuartzPoint(x: display.raw.minX + x, y: display.raw.minY + y)
    }
    public func distance(to other: DisplayPoint) -> Double { hypot(other.x - x, other.y - y) }
}

/// A display-local rect (see `DisplayPoint`): `StoredArea.rect` and `SelectionResult.area` use this space.
public struct DisplayRect: Hashable, Sendable {
    public var raw: Rect2D
    public init(_ raw: Rect2D) { self.raw = raw.standardized }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(Rect2D(x: x, y: y, width: width, height: height))
    }
    public var width: Double { raw.width }
    public var height: Double { raw.height }

    public func viewRect(displayHeight: Double) -> ViewRect {
        ViewRect(x: raw.minX, y: displayHeight - raw.maxY, width: raw.width, height: raw.height)
    }

    /// × `scale`, rounded outward, intersected with the image; nil below 1 × 1 px. `scale` is always the frozen
    /// image's pixel width ÷ the display's point width (design/02 §2.3).
    public func pixelRect(scale: Double, imageWidth: Int, imageHeight: Int) -> PixelRect? {
        let tolerance = 1e-6
        let x0 = (raw.minX * scale + tolerance).rounded(.down)
        let y0 = (raw.minY * scale + tolerance).rounded(.down)
        let x1 = (raw.maxX * scale - tolerance).rounded(.up)
        let y1 = (raw.maxY * scale - tolerance).rounded(.up)
        let image = Rect2D(x: 0, y: 0, width: Double(imageWidth), height: Double(imageHeight))
        guard x1 > x0, y1 > y0, let clipped = Rect2D(x: x0, y: y0, width: x1 - x0, height: y1 - y0).intersection(image),
            clipped.width >= 1, clipped.height >= 1
        else { return nil }
        return PixelRect(clipped)
    }
}

/// Pixels of a frozen image: origin at its top-left, y down.
public struct PixelRect: Hashable, Sendable {
    public var raw: Rect2D
    public init(_ raw: Rect2D) { self.raw = raw.standardized }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(Rect2D(x: x, y: y, width: width, height: height))
    }
}

extension DisplayInfo {
    public var cocoaFrame: CocoaRect { CocoaRect(frame) }

    public func quartzFrame(primaryHeight: Double) -> QuartzRect { cocoaFrame.toQuartz(primaryHeight: primaryHeight) }

    /// The display's size in points.
    public var pointSize: Size2D { Size2D(width: frame.width, height: frame.height) }

    /// The height of the primary display (the one whose Cocoa frame starts at the origin); else the first display's;
    /// 0 for none.
    public static func primaryHeight(of displays: [DisplayInfo]) -> Double {
        let primary = displays.first { $0.frame.minX == 0 && $0.frame.minY == 0 } ?? displays.first
        return primary?.frame.height ?? 0
    }
}
