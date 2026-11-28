import BugeyeCore

/// Zoom (§5.7): ×1.25 steps, 10 %–800 %, 100 % = one view point per canvas point.
public enum ZoomModel {
    public static let step = 1.25
    public static let range: ClosedRange<Double> = 0.1...8
    public static let actualSize = 1.0
    /// Points left free on each side by Zoom to Fit.
    public static let fitMargin = 20.0

    public static func clamp(_ zoom: Double) -> Double { min(range.upperBound, max(range.lowerBound, zoom)) }
    public static func zoomIn(_ zoom: Double) -> Double { clamp(zoom * step) }
    public static func zoomOut(_ zoom: Double) -> Double { clamp(zoom / step) }

    /// min(1, (viewport − 2 × 20 pt) / canvas) on the tighter axis, clamped. Both sizes in points.
    public static func fit(viewport: Size2D, canvas: Size2D) -> Double {
        guard canvas.width > 0, canvas.height > 0 else { return actualSize }
        let x = (viewport.width - 2 * fitMargin) / canvas.width
        let y = (viewport.height - 2 * fitMargin) / canvas.height
        return clamp(min(1, x, y))
    }
}

/// The window's first size (§5.1), in points.
public enum WindowSizing {
    /// Toolbar 40 + divider 1 + options strip 36 + divider 1.
    public static let chromeHeight = 78.0
    public static let margin = 40.0
    public static let minimumContentSize = Size2D(width: 640, height: 420)
    public static let screenFraction = 0.85

    /// The canvas + 40 pt each way + the chrome, capped at 85 % of the screen's visible frame, at least the minimum.
    public static func initialContentSize(canvasPoints: Size2D, screenVisible: Size2D, barsHeight: Double = 0)
        -> Size2D
    {
        let width = min(canvasPoints.width + margin, screenVisible.width * screenFraction)
        let height = min(
            canvasPoints.height + margin + chromeHeight + barsHeight, screenVisible.height * screenFraction)
        return Size2D(
            width: max(minimumContentSize.width, width), height: max(minimumContentSize.height, height))
    }
}
