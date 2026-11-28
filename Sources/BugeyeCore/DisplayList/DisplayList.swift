import Foundation

/// An sRGB colour with components from 0 to 1.
public struct RGBAColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// One step of a path.
public enum PathElement: Hashable, Codable, Sendable {
    case move(to: Point2D)
    case line(to: Point2D)
    case quadCurve(to: Point2D, control: Point2D)
    case curve(to: Point2D, control1: Point2D, control2: Point2D)
    case close
}

/// A vector path, built from elements.
public struct VectorPath: Hashable, Codable, Sendable {
    public var elements: [PathElement]

    public init(_ elements: [PathElement]) {
        self.elements = elements
    }

    /// A closed rectangle, clockwise from the origin.
    public static func rect(_ rect: Rect2D) -> VectorPath {
        VectorPath([
            .move(to: Point2D(x: rect.minX, y: rect.minY)),
            .line(to: Point2D(x: rect.maxX, y: rect.minY)),
            .line(to: Point2D(x: rect.maxX, y: rect.maxY)),
            .line(to: Point2D(x: rect.minX, y: rect.maxY)),
            .close,
        ])
    }
}

/// A font as a description the macOS shell turns into an `NSFont`.
public struct FontDescriptor: Hashable, Codable, Sendable {
    public var name: String
    public var size: Double
    public var weight: Double

    public init(name: String, size: Double, weight: Double = 0) {
        self.name = name
        self.size = size
        self.weight = weight
    }
}

public enum LineCap: String, Hashable, Codable, Sendable { case butt, round, square }
public enum LineJoin: String, Hashable, Codable, Sendable { case miter, round, bevel }

/// A drop shadow, in the list's pixels. The executor multiplies offset and blur by the device scale.
public struct Shadow: Hashable, Codable, Sendable {
    /// Positive y falls downward.
    public var offset: Point2D
    public var blur: Double
    public var color: RGBAColor

    public init(offset: Point2D, blur: Double, color: RGBAColor) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }
}

public struct GroupStyle: Hashable, Codable, Sendable {
    public var opacity: Double
    public var shadow: Shadow?
    /// Composited as one layer: overlaps inside don't darken, and the shadow is cast once.
    public var isolated: Bool
    /// The layer's extent; nil is unbounded.
    public var bounds: Rect2D?

    public init(opacity: Double = 1, shadow: Shadow? = nil, isolated: Bool = false, bounds: Rect2D? = nil) {
        self.opacity = opacity
        self.shadow = shadow
        self.isolated = isolated
        self.bounds = bounds
    }
}

public struct GradientStop: Hashable, Codable, Sendable {
    /// 0…1.
    public var location: Double
    public var color: RGBAColor

    public init(location: Double, color: RGBAColor) {
        self.location = location
        self.color = color
    }
}

public enum BlurEffect: Hashable, Codable, Sendable {
    /// Cell size in pixels.
    case pixelate(cellSize: Double)
    /// Radius in pixels.
    case gaussian(radius: Double)
}

/// One draw command. The core produces these; the macOS executor (Editor-owned, K10) runs them with Core
/// Graphics. Coordinates: origin top-left, y down, in the list's own pixels (`DisplayList.size`); the executor
/// does the one flip.
public enum DisplayCommand: Hashable, Codable, Sendable {
    case fillPath(VectorPath, color: RGBAColor)
    case strokePath(
        VectorPath, color: RGBAColor, lineWidth: Double, cap: LineCap = .butt, join: LineJoin = .miter,
        dash: [Double] = [])
    /// Fills the path with a linear gradient, extended past both ends.
    case fillLinearGradient(VectorPath, stops: [GradientStop], start: Point2D, end: Point2D)
    /// Draws the image the caller registered under `imageID`, scaled into `rect`.
    case image(imageID: String, rect: Rect2D)
    /// `origin` is the left end of the baseline.
    case textRun(String, origin: Point2D, font: FontDescriptor, color: RGBAColor)
    /// Draws `sourceRect` (pixels of the image registered under `sourceImageID`, top-left) with `effect`
    /// applied, edges clamped to `sourceRect`, into `rect`. Samples the source only, never what was drawn before.
    case blurRegion(Rect2D, sourceImageID: String, sourceRect: Rect2D, effect: BlurEffect)
    /// Saves the graphics state and applies the style. Every push has a matching pop.
    case pushGroup(GroupStyle)
    case popGroup
    /// Intersects the clip with the path until the enclosing `popGroup`. Only valid inside a group.
    case clip(VectorPath)
}

extension VectorPath {
    /// The cubic Bézier constant for a quarter circle.
    static let kappa = 0.5522847498

    /// Four cubic Béziers (κ = 0.5522847498), clockwise from the rightmost point (right, bottom, left, top: y
    /// grows downward).
    public static func ellipse(in rect: Rect2D) -> VectorPath {
        let r = rect.standardized
        let cx = r.minX + r.width / 2
        let cy = r.minY + r.height / 2
        let rx = r.width / 2
        let ry = r.height / 2
        let kx = rx * kappa
        let ky = ry * kappa
        return VectorPath([
            .move(to: Point2D(x: cx + rx, y: cy)),
            .curve(
                to: Point2D(x: cx, y: cy + ry), control1: Point2D(x: cx + rx, y: cy + ky),
                control2: Point2D(x: cx + kx, y: cy + ry)),
            .curve(
                to: Point2D(x: cx - rx, y: cy), control1: Point2D(x: cx - kx, y: cy + ry),
                control2: Point2D(x: cx - rx, y: cy + ky)),
            .curve(
                to: Point2D(x: cx, y: cy - ry), control1: Point2D(x: cx - rx, y: cy - ky),
                control2: Point2D(x: cx - kx, y: cy - ry)),
            .curve(
                to: Point2D(x: cx + rx, y: cy), control1: Point2D(x: cx + kx, y: cy - ry),
                control2: Point2D(x: cx + rx, y: cy - ky)),
            .close,
        ])
    }

    /// Radius clamped to half the shorter side; 0 (or less) gives `rect(_:)`. Clockwise from the top edge's start,
    /// like `rect(_:)`.
    public static func roundedRect(_ rect: Rect2D, cornerRadius: Double) -> VectorPath {
        let r = rect.standardized
        let radius = min(cornerRadius, r.width / 2, r.height / 2)
        guard radius > 0 else { return .rect(rect) }
        let k = radius * kappa
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        return VectorPath([
            .move(to: Point2D(x: x0 + radius, y: y0)),
            .line(to: Point2D(x: x1 - radius, y: y0)),
            .curve(
                to: Point2D(x: x1, y: y0 + radius), control1: Point2D(x: x1 - radius + k, y: y0),
                control2: Point2D(x: x1, y: y0 + radius - k)),
            .line(to: Point2D(x: x1, y: y1 - radius)),
            .curve(
                to: Point2D(x: x1 - radius, y: y1), control1: Point2D(x: x1, y: y1 - radius + k),
                control2: Point2D(x: x1 - radius + k, y: y1)),
            .line(to: Point2D(x: x0 + radius, y: y1)),
            .curve(
                to: Point2D(x: x0, y: y1 - radius), control1: Point2D(x: x0 + radius - k, y: y1),
                control2: Point2D(x: x0, y: y1 - radius + k)),
            .line(to: Point2D(x: x0, y: y0 + radius)),
            .curve(
                to: Point2D(x: x0 + radius, y: y0), control1: Point2D(x: x0, y: y0 + radius - k),
                control2: Point2D(x: x0 + radius - k, y: y0)),
            .close,
        ])
    }
}

extension FontDescriptor {
    /// The system UI font. The executor and the measurer map `weight` the same way (0.4 = bold,
    /// 0.3 = semibold, 0 = regular; `CoreTextFonts`, contracts §4.4).
    public static let systemFontName = "system"
}

/// A canvas size and the commands that paint it, in order.
public struct DisplayList: Hashable, Codable, Sendable {
    public var size: Size2D
    public var commands: [DisplayCommand]

    public init(size: Size2D, commands: [DisplayCommand]) {
        self.size = size
        self.commands = commands
    }

    /// Pushes and pops balance, and every `clip` sits inside a group.
    public var isBalanced: Bool {
        var depth = 0
        for command in commands {
            switch command {
            case .pushGroup: depth += 1
            case .popGroup:
                guard depth > 0 else { return false }
                depth -= 1
            case .clip:
                guard depth > 0 else { return false }
            default: break
            }
        }
        return depth == 0
    }

    /// Stable JSON for golden tests: sorted keys, pretty printed, slashes unescaped.
    public func goldenJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
