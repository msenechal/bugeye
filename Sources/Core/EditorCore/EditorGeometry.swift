import BugeyeCore
import Foundation

/// The pixel scale and the text measurer: what text and step geometry need besides the shape.
public struct EditorMetrics: Sendable {
    /// `max(1, item.pixelsPerPoint)`.
    public var ppp: Double
    public var measurer: any TextMeasuring

    public init(ppp: Double, measurer: any TextMeasuring) {
        self.ppp = max(1, ppp)
        self.measurer = measurer
    }
}

/// Plain geometry helpers (§5.4, §6.1).
public enum EditorGeometry {
    /// Below this, in image pixels, a shape or crop isn't meaningful.
    public static let minimumExtent = 3.0

    /// Rounded to whole pixels, intersected with the image, nil under 3 px on either side.
    public static func clampedCrop(_ rect: Rect2D, imageSize: Size2D) -> Rect2D? {
        let r = rect.standardized
        let rounded = Rect2D(
            x: r.minX.rounded(), y: r.minY.rounded(), width: r.maxX.rounded() - r.minX.rounded(),
            height: r.maxY.rounded() - r.minY.rounded())
        let image = Rect2D(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        guard let clamped = rounded.intersection(image), clamped.width >= minimumExtent,
            clamped.height >= minimumExtent
        else { return nil }
        return clamped
    }

    /// `to` moved onto the nearest multiple of 45° around `from`, keeping the length.
    public static func snapped45(from: Point2D, to: Point2D) -> Point2D {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return to }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return Point2D(x: from.x + length * cos(angle), y: from.y + length * sin(angle))
    }

    /// The rect from a drag; `square` makes both sides the longer one, toward the drag.
    public static func rect(from: Point2D, to: Point2D, square: Bool) -> Rect2D {
        var dx = to.x - from.x
        var dy = to.y - from.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return Rect2D(x: from.x, y: from.y, width: dx, height: dy).standardized
    }

    public static func distance(_ p: Point2D, toSegment a: Point2D, _ b: Point2D) -> Double {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        var t = lengthSquared > 0 ? ((p.x - a.x) * vx + (p.y - a.y) * vy) / lengthSquared : 0
        t = min(1, max(0, t))
        let x = a.x + t * vx - p.x
        let y = a.y + t * vy - p.y
        return (x * x + y * y).squareRoot()
    }

    /// Closed-interval overlap, so a flat (zero-height or zero-width) box inside `visible` counts (plan P13).
    public static func overlaps(_ a: Rect2D, _ visible: Rect2D) -> Bool {
        a.maxX >= visible.minX && a.minX <= visible.maxX && a.maxY >= visible.minY && a.minY <= visible.maxY
    }

    public static func bounds(of points: [Point2D]) -> Rect2D {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return Rect2D(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func outset(_ rect: Rect2D, by d: Double) -> Rect2D {
        let r = rect.standardized
        return Rect2D(x: r.minX - d, y: r.minY - d, width: r.width + 2 * d, height: r.height + 2 * d)
    }

    static func offset(_ rect: Rect2D, by d: Point2D) -> Rect2D {
        let r = rect.standardized
        return Rect2D(x: r.minX + d.x, y: r.minY + d.y, width: r.width, height: r.height)
    }
}

func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }

/// A text annotation's lines, laid out with the measurer (§7, plan P5).
public struct TextLayout: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public var string: String
        public var width: Double
        /// The left end of the baseline, in the annotation's pixels.
        public var baseline: Point2D
    }

    public var font: FontDescriptor
    public var ascent: Double
    public var descent: Double
    public var lines: [Line]
    public var bounds: Rect2D

    /// The bold system font at `fontSize` points × ppp.
    public static func font(fontSize: Double, ppp: Double) -> FontDescriptor {
        FontDescriptor(name: FontDescriptor.systemFontName, size: fontSize * ppp, weight: 0.4)
    }

    public init(string: String, origin: Point2D, fontSize: Double, ppp: Double, measurer: any TextMeasuring) {
        font = Self.font(fontSize: fontSize, ppp: ppp)
        let reference = measurer.measure(" ", font: font)
        ascent = reference.ascent
        descent = reference.descent
        let lineHeight = ascent + descent
        let strings = string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var lines: [Line] = []
        for (index, text) in strings.enumerated() {
            let width = text.isEmpty ? 0 : measurer.measure(text, font: font).width
            lines.append(
                Line(
                    string: text, width: width,
                    baseline: Point2D(x: origin.x, y: origin.y + ascent + Double(index) * lineHeight)))
        }
        self.lines = lines
        bounds = Rect2D(
            origin: origin,
            size: Size2D(width: lines.map(\.width).max() ?? 0, height: Double(lines.count) * lineHeight))
    }
}
