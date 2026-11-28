import BugeyeCore

/// The single source of geometry (§4): canvas size, content rect and where the image sits. Canvas pixels, y down.
public struct CanvasLayout: Hashable, Sendable {
    public let imageSize: Size2D
    public let ppp: Double
    /// The image pixels shown: the crop, or the whole image (always the whole image in the Crop tool).
    public let visible: Rect2D
    /// The frame drawn around the content, nil without one and in the Crop tool.
    public let frame: BackgroundFrame?
    /// `round(frame.padding × ppp)`, 0 without a frame.
    public let padding: Double
    public let size: Size2D
    public let contentRect: Rect2D
    /// Where image pixel (0, 0) lands on the canvas.
    public let imageOrigin: Point2D

    public init(imageSize: Size2D, state: EditorState, pixelsPerPoint: Double, showingFullImage: Bool) {
        self.imageSize = imageSize
        ppp = max(1, pixelsPerPoint)
        let whole = Rect2D(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        visible = showingFullImage ? whole : (state.crop ?? whole)
        frame = showingFullImage ? nil : state.frame
        let scale = ppp
        padding = frame.map { ($0.padding * scale).rounded() } ?? 0
        size = Size2D(width: visible.width + 2 * padding, height: visible.height + 2 * padding)
        contentRect = Rect2D(x: padding, y: padding, width: visible.width, height: visible.height)
        imageOrigin = Point2D(x: padding - visible.minX, y: padding - visible.minY)
    }

    public func imagePoint(fromCanvas point: Point2D) -> Point2D {
        Point2D(x: point.x - imageOrigin.x, y: point.y - imageOrigin.y)
    }

    public func canvasPoint(fromImage point: Point2D) -> Point2D {
        Point2D(x: point.x + imageOrigin.x, y: point.y + imageOrigin.y)
    }

    /// The image's rect on the canvas.
    public var imageRect: Rect2D {
        Rect2D(origin: imageOrigin, size: imageSize)
    }
}
