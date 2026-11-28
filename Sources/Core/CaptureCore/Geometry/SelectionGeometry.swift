import BugeyeCore
import Foundation

/// The axis a ⇧ drag holds still: `.x` keeps the ⇧ point's x, `.y` its y.
public enum LockedAxis: Hashable, Sendable { case x, y }

/// One area drag on one display, in display-local points (design/02 §1.2, §2.8).
public struct Drag: Hashable, Sendable {
    public var display: DisplayID
    public var anchor: DisplayPoint
    public var current: DisplayPoint
    public var fromCentre: Bool
    /// Where the pointer was when ⇧ took effect (plan P9).
    public private(set) var shiftPoint: DisplayPoint?
    public private(set) var lockedAxis: LockedAxis?

    public init(display: DisplayID, anchor: DisplayPoint, fromCentre: Bool) {
        self.display = display
        self.anchor = anchor
        current = anchor
        self.fromCentre = fromCentre
    }

    /// Applies a drag event. Modifiers come from every event (design/02 §3.2), the point is clamped to the display.
    /// ⇧ sets its point only once the selection has a width and a height, and locks the axis that moved less once
    /// the pointer is more than 2 pt from that point; releasing ⇧ unlocks.
    public mutating func update(to point: DisplayPoint, shift: Bool, option: Bool, displaySize: Size2D) {
        current = DisplayPoint(
            x: min(max(point.x, 0), displaySize.width), y: min(max(point.y, 0), displaySize.height))
        fromCentre = option
        guard shift else {
            shiftPoint = nil
            lockedAxis = nil
            return
        }
        if shiftPoint == nil {
            let size = rect(displaySize: displaySize)
            if size.width > 0, size.height > 0 { shiftPoint = current }
        } else if lockedAxis == nil, let shiftPoint, current.distance(to: shiftPoint) > 2 {
            lockedAxis = abs(current.x - shiftPoint.x) < abs(current.y - shiftPoint.y) ? .x : .y
        }
    }

    /// The pointer after the ⇧ lock.
    public var effectiveCurrent: DisplayPoint {
        guard let lockedAxis, let shiftPoint else { return current }
        switch lockedAxis {
        case .x: return DisplayPoint(x: shiftPoint.x, y: current.y)
        case .y: return DisplayPoint(x: current.x, y: shiftPoint.y)
        }
    }

    /// The selection, clipped to the display (Capture I6).
    public func rect(displaySize: Size2D) -> DisplayRect {
        let point = effectiveCurrent
        let raw: Rect2D
        if fromCentre {
            let dx = abs(point.x - anchor.x)
            let dy = abs(point.y - anchor.y)
            raw = Rect2D(x: anchor.x - dx, y: anchor.y - dy, width: 2 * dx, height: 2 * dy)
        } else {
            raw = Rect2D(x: anchor.x, y: anchor.y, width: point.x - anchor.x, height: point.y - anchor.y).standardized
        }
        let bounds = Rect2D(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
        if raw.isEmpty {
            let x = min(max(raw.minX, 0), displaySize.width)
            let y = min(max(raw.minY, 0), displaySize.height)
            let width = min(raw.width, displaySize.width - x)
            let height = min(raw.height, displaySize.height - y)
            return DisplayRect(x: x, y: y, width: max(0, width), height: max(0, height))
        }
        return DisplayRect(raw.intersection(bounds) ?? Rect2D(x: anchor.x, y: anchor.y, width: 0, height: 0))
    }
}

/// The loupe's 15 × 15 sample and the pointer's cell inside it.
public struct LoupeSample: Hashable, Sendable {
    public var rect: PixelRect
    public var markerColumn: Int
    public var markerRow: Int
    public init(rect: PixelRect, markerColumn: Int, markerRow: Int) {
        self.rect = rect
        self.markerColumn = markerColumn
        self.markerRow = markerRow
    }
}

/// The overlay's measurements (design/02 §1.2), all in display-local points unless named otherwise.
public enum SelectionGeometry {
    public static let minimumSize = 4.0
    public static let loupeDiameter = 120.0
    public static let loupeOffset = 20.0
    public static let loupeSamplePixels = 15
    public static let readoutOffset = Size2D(width: 8, height: 24)

    /// At least 4 × 4 pt.
    public static func isCapturable(_ rect: DisplayRect) -> Bool {
        rect.width >= minimumSize && rect.height >= minimumSize
    }

    /// 20 pt below-right of the pointer, flipped near the right and bottom edges, always fully on screen.
    public static func loupeFrame(pointer: DisplayPoint, displaySize: Size2D) -> DisplayRect {
        let size = loupeDiameter
        var x = pointer.x + loupeOffset
        var y = pointer.y + loupeOffset
        if x + size > displaySize.width { x = pointer.x - loupeOffset - size }
        if y + size > displaySize.height { y = pointer.y - loupeOffset - size }
        x = min(max(x, 0), max(0, displaySize.width - size))
        y = min(max(y, 0), max(0, displaySize.height - size))
        return DisplayRect(x: x, y: y, width: size, height: size)
    }

    /// A fixed 15 × 15 square around the pointer's pixel, slid inside the image (never shrunk).
    public static func loupeSample(pointerPixelX: Int, pointerPixelY: Int, imageWidth: Int, imageHeight: Int)
        -> LoupeSample
    {
        let n = loupeSamplePixels
        func start(_ p: Int, _ limit: Int) -> Int { min(max(p - n / 2, 0), max(0, limit - n)) }
        let x0 = start(pointerPixelX, imageWidth)
        let y0 = start(pointerPixelY, imageHeight)
        return LoupeSample(
            rect: PixelRect(x: Double(x0), y: Double(y0), width: Double(n), height: Double(n)),
            markerColumn: min(max(pointerPixelX - x0, 0), n - 1), markerRow: min(max(pointerPixelY - y0, 0), n - 1))
    }

    /// `W × H` (U+00D7), rounded points.
    public static func readoutText(_ selection: DisplayRect) -> String {
        "\(Int(selection.width.rounded())) \u{00D7} \(Int(selection.height.rounded()))"
    }

    /// 8 pt right of and 24 pt below the selection's bottom-right corner, kept on screen (plan P8).
    public static func readoutFrame(selection: DisplayRect, labelSize: Size2D, displaySize: Size2D) -> DisplayRect {
        var x = selection.raw.maxX + readoutOffset.width
        var y = selection.raw.maxY + readoutOffset.height
        x = min(max(x, 0), max(0, displaySize.width - labelSize.width))
        y = min(max(y, 0), max(0, displaySize.height - labelSize.height))
        return DisplayRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
    }
}
