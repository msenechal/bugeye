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

/// One draw command. The core produces these; the macOS shell executes them with Core Graphics.
public enum DisplayCommand: Hashable, Codable, Sendable {
    case fillPath(VectorPath, color: RGBAColor)
    case strokePath(VectorPath, color: RGBAColor, lineWidth: Double)
    /// Draws the image the caller registered under `imageID`, scaled into `rect`.
    case image(imageID: String, rect: Rect2D)
    case textRun(String, origin: Point2D, font: FontDescriptor, color: RGBAColor)
    case blurRegion(Rect2D, radius: Double)
}

/// A canvas size and the commands that paint it, in order.
public struct DisplayList: Hashable, Codable, Sendable {
    public var size: Size2D
    public var commands: [DisplayCommand]

    public init(size: Size2D, commands: [DisplayCommand]) {
        self.size = size
        self.commands = commands
    }

    /// Stable JSON for golden tests: sorted keys, pretty printed, slashes unescaped.
    public func goldenJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
