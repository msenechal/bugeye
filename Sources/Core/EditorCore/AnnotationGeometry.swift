import BugeyeCore
import Foundation

/// A resize handle: eight around a rect-like shape, two on a line or arrow (I3).
public enum AnnotationHandle: String, Hashable, Sendable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, start, end
}

extension AnnotationShape {
    /// False for degenerate input (§5.4): segments under 3 px, rect-likes under 3 px on a side, strokes under
    /// 3 px on both sides. Text and steps are always meaningful.
    public var isMeaningful: Bool {
        let minimum = EditorGeometry.minimumExtent
        switch self {
        case .arrow(let from, let to), .line(let from, let to):
            return EditorGeometry.distance(from, toSegment: to, to) >= minimum
        case .rectangle(let rect, _), .ellipse(let rect, _), .blur(let rect, _, _):
            return rect.width >= minimum && rect.height >= minimum
        case .pen(let points), .highlighter(let points):
            let bounds = EditorGeometry.bounds(of: points)
            return bounds.width >= minimum || bounds.height >= minimum
        case .text, .step:
            return true
        }
    }

    public func translated(by d: Point2D) -> AnnotationShape {
        switch self {
        case .arrow(let from, let to): .arrow(from: from + d, to: to + d)
        case .line(let from, let to): .line(from: from + d, to: to + d)
        case .rectangle(let rect, let filled): .rectangle(EditorGeometry.offset(rect, by: d), filled: filled)
        case .ellipse(let rect, let filled): .ellipse(EditorGeometry.offset(rect, by: d), filled: filled)
        case .text(let origin, let string, let fontSize): .text(origin: origin + d, string: string, fontSize: fontSize)
        case .pen(let points): .pen(points.map { $0 + d })
        case .highlighter(let points): .highlighter(points.map { $0 + d })
        case .blur(let rect, let mode, let strength):
            .blur(EditorGeometry.offset(rect, by: d), mode: mode, strength: strength)
        case .step(let center): .step(center: center + d)
        }
    }

    /// The shape with `handle` moved to `point`; a rect-like shape flips when dragged past its opposite edge.
    /// Shapes without that handle come back unchanged.
    public func resized(_ handle: AnnotationHandle, to point: Point2D) -> AnnotationShape {
        switch self {
        case .arrow(let from, let to):
            switch handle {
            case .start: return .arrow(from: point, to: to)
            case .end: return .arrow(from: from, to: point)
            default: return self
            }
        case .line(let from, let to):
            switch handle {
            case .start: return .line(from: point, to: to)
            case .end: return .line(from: from, to: point)
            default: return self
            }
        case .rectangle(let rect, let filled):
            return .rectangle(Self.resize(rect, handle, point), filled: filled)
        case .ellipse(let rect, let filled):
            return .ellipse(Self.resize(rect, handle, point), filled: filled)
        case .blur(let rect, let mode, let strength):
            return .blur(Self.resize(rect, handle, point), mode: mode, strength: strength)
        case .text, .pen, .highlighter, .step:
            return self
        }
    }

    static func resize(_ rect: Rect2D, _ handle: AnnotationHandle, _ p: Point2D) -> Rect2D {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        switch handle {
        case .topLeft: (minX, minY) = (p.x, p.y)
        case .top: minY = p.y
        case .topRight: (maxX, minY) = (p.x, p.y)
        case .right: maxX = p.x
        case .bottomRight: (maxX, maxY) = (p.x, p.y)
        case .bottom: maxY = p.y
        case .bottomLeft: (minX, maxY) = (p.x, p.y)
        case .left: minX = p.x
        case .start, .end: break
        }
        return Rect2D(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }
}

extension Annotation {
    /// The stroke's width in image pixels (highlighter: 3 × width).
    public func strokePixels(_ metrics: EditorMetrics) -> Double {
        let points = style.width.points * metrics.ppp
        if case .highlighter = shape { return 3 * points }
        return points
    }

    /// The geometric bounds in image pixels (no stroke or shadow outset).
    public func bounds(_ metrics: EditorMetrics) -> Rect2D {
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return EditorGeometry.bounds(of: [from, to])
        case .rectangle(let rect, _), .ellipse(let rect, _), .blur(let rect, _, _):
            return rect.standardized
        case .pen(let points), .highlighter(let points):
            return EditorGeometry.bounds(of: points)
        case .text(let origin, let string, let fontSize):
            return TextLayout(
                string: string, origin: origin, fontSize: fontSize, ppp: metrics.ppp, measurer: metrics.measurer
            ).bounds
        case .step(let center):
            let d = style.width.stepDiameter * metrics.ppp
            return Rect2D(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        }
    }

    /// Handle positions in image pixels (I3).
    public func handles(_ metrics: EditorMetrics) -> [(handle: AnnotationHandle, point: Point2D)] {
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return [(.start, from), (.end, to)]
        case .rectangle(let rect, _), .ellipse(let rect, _), .blur(let rect, _, _):
            let r = rect.standardized
            let midX = r.minX + r.width / 2
            let midY = r.minY + r.height / 2
            return [
                (.topLeft, Point2D(x: r.minX, y: r.minY)), (.top, Point2D(x: midX, y: r.minY)),
                (.topRight, Point2D(x: r.maxX, y: r.minY)), (.right, Point2D(x: r.maxX, y: midY)),
                (.bottomRight, Point2D(x: r.maxX, y: r.maxY)), (.bottom, Point2D(x: midX, y: r.maxY)),
                (.bottomLeft, Point2D(x: r.minX, y: r.maxY)), (.left, Point2D(x: r.minX, y: midY)),
            ]
        case .text, .pen, .highlighter, .step:
            return []
        }
    }

    /// max(stroke width / 2, `minimum`) (I1).
    public func hitTolerance(minimum: Double, _ metrics: EditorMetrics) -> Double {
        max(strokePixels(metrics) / 2, minimum)
    }

    /// I2: segments by distance, rect and ellipse outlines as a ring (the inside too when filled), strokes by
    /// distance to any segment, text, blur and step by bounds. `tolerance` is the minimum hit distance in pixels.
    public func hitTest(_ p: Point2D, tolerance: Double, _ metrics: EditorMetrics) -> Bool {
        let t = hitTolerance(minimum: tolerance, metrics)
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return EditorGeometry.distance(p, toSegment: from, to) <= t
        case .rectangle(let rect, let filled):
            let outer = EditorGeometry.outset(rect, by: t)
            guard Self.closedContains(outer, p) else { return false }
            if filled { return true }
            let r = rect.standardized
            guard r.width > 2 * t, r.height > 2 * t else { return true }
            let inner = EditorGeometry.outset(r, by: -t)
            return !Self.closedContains(inner, p) || Self.onEdge(inner, p)
        case .ellipse(let rect, let filled):
            let r = rect.standardized
            let cx = r.minX + r.width / 2
            let cy = r.minY + r.height / 2
            func inside(_ rx: Double, _ ry: Double) -> Bool {
                guard rx > 0, ry > 0 else { return false }
                let x = (p.x - cx) / rx
                let y = (p.y - cy) / ry
                return x * x + y * y <= 1
            }
            guard inside(r.width / 2 + t, r.height / 2 + t) else { return false }
            if filled { return true }
            return !inside(r.width / 2 - t, r.height / 2 - t)
        case .pen(let points), .highlighter(let points):
            guard let first = points.first else { return false }
            if points.count == 1 { return EditorGeometry.distance(p, toSegment: first, first) <= t }
            return zip(points, points.dropFirst()).contains { EditorGeometry.distance(p, toSegment: $0, $1) <= t }
        case .text, .blur, .step:
            return Self.closedContains(bounds(metrics), p)
        }
    }

    static func closedContains(_ r: Rect2D, _ p: Point2D) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    static func onEdge(_ r: Rect2D, _ p: Point2D) -> Bool {
        p.x == r.minX || p.x == r.maxX || p.y == r.minY || p.y == r.maxY
    }
}

extension EditorState {
    /// 1 + the number of steps below it in z-order (E7); nil for anything that isn't a step.
    public func stepNumber(of id: UUID) -> Int? {
        var count = 0
        for annotation in annotations {
            guard case .step = annotation.shape else { continue }
            count += 1
            if annotation.id == id { return count }
        }
        return nil
    }
}
