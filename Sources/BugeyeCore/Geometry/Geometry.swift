/// A point in a 2-D space whose unit the caller states (points or pixels). Portable: no CoreGraphics.
/// Named `Point2D`, not `Point`: Darwin's MacTypes already has `Point` and `Rect`, and SwiftUI has `Color`
/// and `Path`, so plain names would be ambiguous in every macOS file that imports both (`design/11` §6).
public struct Point2D: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)
}

/// A width and a height. Negative values are allowed until a `Rect2D` is standardized.
public struct Size2D: Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size2D(width: 0, height: 0)
}

/// An origin and a size. Edges are half-open: a rect contains its min edges, not its max edges.
public struct Rect2D: Hashable, Codable, Sendable {
    public var origin: Point2D
    public var size: Size2D

    public init(origin: Point2D, size: Size2D) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point2D(x: x, y: y), size: Size2D(width: width, height: height))
    }

    public static let zero = Rect2D(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { min(origin.x, origin.x + size.width) }
    public var maxX: Double { max(origin.x, origin.x + size.width) }
    public var minY: Double { min(origin.y, origin.y + size.height) }
    public var maxY: Double { max(origin.y, origin.y + size.height) }
    public var width: Double { abs(size.width) }
    public var height: Double { abs(size.height) }

    /// True when the rect has no area.
    public var isEmpty: Bool { width == 0 || height == 0 }

    /// The same rect with a non-negative width and height.
    public var standardized: Rect2D { Rect2D(x: minX, y: minY, width: width, height: height) }

    public func contains(_ point: Point2D) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// The overlapping area, or nil when the rects only touch or don't meet.
    public func intersection(_ other: Rect2D) -> Rect2D? {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return Rect2D(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
