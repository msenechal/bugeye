import BugeyeCore
import Foundation

/// Stroke width in points (Editor §5.5); a numbered step's diameter follows it (§7).
public enum StrokeWidth: String, Hashable, Codable, Sendable, CaseIterable {
    case thin, medium, thick

    public var points: Double {
        switch self {
        case .thin: 2
        case .medium: 4
        case .thick: 8
        }
    }

    /// A numbered step's diameter in points.
    public var stepDiameter: Double {
        switch self {
        case .thin: 22
        case .medium: 28
        case .thick: 36
        }
    }
}

public enum BlurMode: String, Hashable, Codable, Sendable, CaseIterable { case pixelate, blur }

/// What every annotation carries: colour, width and shadow (§6.1).
public struct AnnotationStyle: Hashable, Codable, Sendable {
    public var color: RGBAColor
    public var width: StrokeWidth
    public var shadow: Bool

    public init(color: RGBAColor = EditorPalette.red, width: StrokeWidth = .medium, shadow: Bool = false) {
        self.color = color
        self.width = width
        self.shadow = shadow
    }
}

/// Positions are image pixels, top-left, y down; `fontSize` is in points (§4).
public enum AnnotationShape: Hashable, Codable, Sendable {
    case arrow(from: Point2D, to: Point2D)
    case line(from: Point2D, to: Point2D)
    case rectangle(Rect2D, filled: Bool)
    case ellipse(Rect2D, filled: Bool)
    /// `origin` is the top-left of the first line's box.
    case text(origin: Point2D, string: String, fontSize: Double)
    case pen([Point2D])
    case highlighter([Point2D])
    /// `strength` 1…3.
    case blur(Rect2D, mode: BlurMode, strength: Int)
    /// The number is computed from the z-order (E7).
    case step(center: Point2D)

    /// The tool that draws this shape, whose options it shows when selected.
    public var tool: EditorTool {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .pen: .pen
        case .highlighter: .highlighter
        case .blur: .blur
        case .step: .step
        }
    }
}

public struct Annotation: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle = AnnotationStyle()) {
        self.id = id
        self.shape = shape
        self.style = style
    }
}

public enum FrameFill: Hashable, Codable, Sendable {
    /// Index into `EditorPalette`'s gradients, 0…3.
    case gradient(Int)
    case white
    case black
}

/// The background frame (§5.6). Padding and radius are in points.
public struct BackgroundFrame: Hashable, Codable, Sendable {
    public var padding: Double
    public var fill: FrameFill
    public var cornerRadius: Double
    public var shadow: Bool

    public static let paddingRange: ClosedRange<Double> = 0...160
    public static let cornerRadiusRange: ClosedRange<Double> = 0...32

    public init(padding: Double = 48, fill: FrameFill = .gradient(0), cornerRadius: Double = 10, shadow: Bool = true) {
        self.padding = padding
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
}

/// The document's whole state: undo keeps snapshots of it (§6.2).
public struct EditorState: Hashable, Codable, Sendable {
    /// Z-order, bottom first.
    public var annotations: [Annotation]
    /// Image pixels, already clamped (`EditorGeometry.clampedCrop`).
    public var crop: Rect2D?
    public var frame: BackgroundFrame?

    public init(annotations: [Annotation] = [], crop: Rect2D? = nil, frame: BackgroundFrame? = nil) {
        self.annotations = annotations
        self.crop = crop
        self.frame = frame
    }

    public func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }
}

/// One set per editor, shared by every tool, not persisted (E9).
public struct ToolOptions: Hashable, Codable, Sendable {
    public var color: RGBAColor
    public var width: StrokeWidth
    public var filled: Bool
    public var shadow: Bool
    /// Points: 16, 24, 36 or 48.
    public var fontSize: Double
    public var blurMode: BlurMode
    /// 1…3.
    public var blurStrength: Int

    public static let fontSizes: [Double] = [16, 24, 36, 48]

    public init(
        color: RGBAColor = EditorPalette.red, width: StrokeWidth = .medium, filled: Bool = false, shadow: Bool = false,
        fontSize: Double = 24, blurMode: BlurMode = .pixelate, blurStrength: Int = 2
    ) {
        self.color = color
        self.width = width
        self.filled = filled
        self.shadow = shadow
        self.fontSize = fontSize
        self.blurMode = blurMode
        self.blurStrength = blurStrength
    }
}

/// The swatches and frame fills (§5.5, §5.6).
public enum EditorPalette {
    public struct Swatch: Hashable, Sendable {
        public let name: String
        public let color: RGBAColor
    }

    public struct Fill: Hashable, Sendable {
        public let name: String
        public let fill: FrameFill
    }

    public static let red = RGBAColor(red: 1, green: 0.23, blue: 0.19)

    public static let swatches: [Swatch] = [
        Swatch(name: "Red", color: red),
        Swatch(name: "Orange", color: RGBAColor(red: 1, green: 0.58, blue: 0)),
        Swatch(name: "Yellow", color: RGBAColor(red: 1, green: 0.8, blue: 0)),
        Swatch(name: "Green", color: RGBAColor(red: 0.2, green: 0.78, blue: 0.35)),
        Swatch(name: "Blue", color: RGBAColor(red: 0, green: 0.48, blue: 1)),
        Swatch(name: "Black", color: RGBAColor(red: 0, green: 0, blue: 0)),
    ]

    public static let gradients: [[RGBAColor]] = [
        [RGBAColor(red: 0.39, green: 0.40, blue: 0.95), RGBAColor(red: 0.93, green: 0.36, blue: 0.70)],
        [RGBAColor(red: 1, green: 0.62, blue: 0.27), RGBAColor(red: 0.96, green: 0.31, blue: 0.45)],
        [RGBAColor(red: 0.20, green: 0.80, blue: 0.75), RGBAColor(red: 0.16, green: 0.42, blue: 0.90)],
        [RGBAColor(red: 0.30, green: 0.32, blue: 0.36), RGBAColor(red: 0.08, green: 0.08, blue: 0.10)],
    ]

    public static let fills: [Fill] = [
        Fill(name: "Indigo to pink", fill: .gradient(0)),
        Fill(name: "Orange to coral", fill: .gradient(1)),
        Fill(name: "Teal to blue", fill: .gradient(2)),
        Fill(name: "Graphite", fill: .gradient(3)),
        Fill(name: "White", fill: .white),
        Fill(name: "Black", fill: .black),
    ]

    /// Two colours for a gradient (an unknown index falls back to the first), one for a solid fill.
    public static func gradientColors(_ index: Int) -> [RGBAColor] {
        gradients.indices.contains(index) ? gradients[index] : gradients[0]
    }

    public static func fillColors(_ fill: FrameFill) -> [RGBAColor] {
        switch fill {
        case .gradient(let index): gradientColors(index)
        case .white: [RGBAColor(red: 1, green: 1, blue: 1)]
        case .black: [RGBAColor(red: 0, green: 0, blue: 0)]
        }
    }
}
