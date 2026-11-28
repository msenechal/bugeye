import BugeyeCore
import Foundation

/// The three lists the canvas draws (E10): the base (everything except the active annotation, cached), the active
/// annotation drawn live on top, and the overlay (selection, handles, crop dimming; never exported).
public struct EditorLists: Hashable, Sendable {
    public var base: DisplayList
    public var active: DisplayList
    public var overlay: DisplayList
}

/// State → display lists (§7). The canvas and every export draw from these lists, so what you see is what you
/// save (`design/03` §5.2).
public enum EditorRenderer {
    /// The id the capture image is registered under, for `image` and `blurRegion`.
    public static let captureImageID = "capture"

    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    /// The selection outline's colour (plan P7): the Blue swatch.
    static let selectionColor = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let handleBorder = RGBAColor(red: 0.5, green: 0.5, blue: 0.5)

    /// `state` is what the canvas shows (the controller's `displayState`); `active` and `hidden` are left out of
    /// the base; `cropMode` draws the crop dimming; `zoom` sizes the overlay in screen points.
    public static func lists(
        state: EditorState, layout: CanvasLayout, metrics: EditorMetrics, active: UUID?, hidden: UUID?,
        selection: UUID?, cropMode: Bool, zoom: Double
    ) -> EditorLists {
        let base = baseList(state: state, layout: layout, metrics: metrics, excluding: [active, hidden])
        var activeCommands: [DisplayCommand] = []
        if let active, active != hidden, let annotation = state.annotation(active) {
            let content =
                [DisplayCommand.pushGroup(GroupStyle()), .clip(.rect(layout.contentRect))]
                + annotationCommands(annotation, state: state, layout: layout, metrics: metrics) + [.popGroup]
            if let frame = layout.frame {
                activeCommands =
                    [
                        .pushGroup(GroupStyle()),
                        .clip(.roundedRect(layout.contentRect, cornerRadius: radius(frame, layout))),
                    ]
                    + content + [.popGroup]
            } else {
                activeCommands = content
            }
        }
        let overlay = overlayList(
            state: state, layout: layout, metrics: metrics, selection: selection == hidden ? nil : selection,
            cropMode: cropMode, zoom: zoom)
        return EditorLists(
            base: base, active: DisplayList(size: layout.size, commands: activeCommands), overlay: overlay)
    }

    /// What Copy, Save, Save As and the drag handle write: the base list of the document's state, nothing active or
    /// hidden, no crop tool (§5.8).
    public static func export(state: EditorState, imageSize: Size2D, metrics: EditorMetrics) -> DisplayList {
        let layout = CanvasLayout(
            imageSize: imageSize, state: state, pixelsPerPoint: metrics.ppp, showingFullImage: false)
        return baseList(state: state, layout: layout, metrics: metrics, excluding: [])
    }

    // MARK: Base

    static func baseList(state: EditorState, layout: CanvasLayout, metrics: EditorMetrics, excluding: [UUID?])
        -> DisplayList
    {
        var content: [DisplayCommand] = [
            .pushGroup(GroupStyle()), .clip(.rect(layout.contentRect)),
            .image(imageID: captureImageID, rect: layout.imageRect),
        ]
        for annotation in state.annotations where !excluding.contains(annotation.id) {
            content += annotationCommands(annotation, state: state, layout: layout, metrics: metrics)
        }
        content.append(.popGroup)

        guard let frame = layout.frame else { return DisplayList(size: layout.size, commands: content) }
        let ppp = layout.ppp
        let canvas = VectorPath.rect(Rect2D(origin: .zero, size: layout.size))
        var commands: [DisplayCommand] = []
        let colors = EditorPalette.fillColors(frame.fill)
        if colors.count == 1 {
            commands.append(.fillPath(canvas, color: colors[0]))
        } else {
            commands.append(
                .fillLinearGradient(
                    canvas,
                    stops: [
                        GradientStop(location: 0, color: colors[0]), GradientStop(location: 1, color: colors[1]),
                    ], start: .zero, end: Point2D(x: layout.size.width, y: layout.size.height)))
        }
        let shadow =
            frame.shadow
            ? Shadow(
                offset: Point2D(x: 0, y: 6 * ppp), blur: 20 * ppp,
                color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            : nil
        commands.append(.pushGroup(GroupStyle(shadow: shadow, isolated: true)))
        commands.append(.clip(.roundedRect(layout.contentRect, cornerRadius: radius(frame, layout))))
        commands += content
        commands.append(.popGroup)
        return DisplayList(size: layout.size, commands: commands)
    }

    static func radius(_ frame: BackgroundFrame, _ layout: CanvasLayout) -> Double {
        min(frame.cornerRadius * layout.ppp, min(layout.contentRect.width, layout.contentRect.height) / 2)
    }

    // MARK: Annotations

    /// One isolated group per annotation (§7.3): bounds + 16 ppp, 40 % for the highlighter, the shadow when on
    /// (never for highlighter or blur); positions translated by `imageOrigin`.
    static func annotationCommands(
        _ annotation: Annotation, state: EditorState, layout: CanvasLayout, metrics: EditorMetrics
    ) -> [DisplayCommand] {
        let ppp = layout.ppp
        let o = layout.imageOrigin
        let shape = annotation.shape.translated(by: o)
        let color = annotation.style.color
        let w = annotation.style.width.points * ppp
        var isHighlighter = false
        var isBlur = false
        var body: [DisplayCommand] = []

        switch shape {
        case .arrow(let from, let to):
            body = arrow(from: from, to: to, width: w, color: color, ppp: ppp)
        case .line(let from, let to):
            body = [stroke(VectorPath([.move(to: from), .line(to: to)]), color, w)]
        case .rectangle(let rect, let filled):
            body = [
                filled ? .fillPath(.rect(rect.standardized), color: color) : stroke(.rect(rect.standardized), color, w)
            ]
        case .ellipse(let rect, let filled):
            body = [filled ? .fillPath(.ellipse(in: rect), color: color) : stroke(.ellipse(in: rect), color, w)]
        case .text(let origin, let string, let fontSize):
            let text = TextLayout(
                string: string, origin: origin, fontSize: fontSize, ppp: ppp, measurer: metrics.measurer)
            body = text.lines.filter { !$0.string.isEmpty }.map {
                .textRun($0.string, origin: $0.baseline, font: text.font, color: color)
            }
        case .pen(let points):
            body = [stroke(polyline(points), color, w)]
        case .highlighter(let points):
            isHighlighter = true
            body = [stroke(polyline(points), color, 3 * w)]
        case .blur(_, let mode, let strength):
            isBlur = true
            guard case .blur(let imageRect, _, _) = annotation.shape,
                let source = integralRect(imageRect, within: layout.imageSize)
            else { return [] }
            let effect: BlurEffect =
                mode == .pixelate
                ? .pixelate(cellSize: Double(strength) * 6 * ppp) : .gaussian(radius: Double(strength) * 5 * ppp)
            body = [
                .blurRegion(
                    EditorGeometry.offset(source, by: o), sourceImageID: captureImageID, sourceRect: source,
                    effect: effect)
            ]
        case .step(let center):
            body = step(center: center, annotation: annotation, state: state, ppp: ppp, metrics: metrics)
        }

        let bounds = EditorGeometry.offset(annotation.bounds(metrics), by: o)
        let shadow =
            annotation.style.shadow && !isHighlighter && !isBlur
            ? Shadow(
                offset: Point2D(x: 0, y: 2 * ppp), blur: 6 * ppp,
                color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            : nil
        let style = GroupStyle(
            opacity: isHighlighter ? 0.4 : 1, shadow: shadow, isolated: true,
            bounds: EditorGeometry.outset(bounds, by: 16 * ppp))
        return [.pushGroup(style)] + body + [.popGroup]
    }

    static func stroke(_ path: VectorPath, _ color: RGBAColor, _ width: Double) -> DisplayCommand {
        .strokePath(path, color: color, lineWidth: width, cap: .round, join: .round)
    }

    static func polyline(_ points: [Point2D]) -> VectorPath {
        guard let first = points.first else { return VectorPath([]) }
        if points.count == 1 { return VectorPath([.move(to: first), .line(to: first)]) }
        return VectorPath([.move(to: first)] + points.dropFirst().map { .line(to: $0) })
    }

    /// Head length = min(length, max(width × 3.5, 12 ppp)), half-width 0.45 × head; the shaft stops 0.3 × head
    /// inside the head (§7).
    static func arrow(from: Point2D, to: Point2D, width: Double, color: RGBAColor, ppp: Double) -> [DisplayCommand] {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return [] }
        let ux = dx / length
        let uy = dy / length
        let head = min(length, max(width * 3.5, 12 * ppp))
        let halfWidth = 0.45 * head
        let base = Point2D(x: to.x - ux * head, y: to.y - uy * head)
        let shaftEnd = Point2D(x: to.x - ux * 0.7 * head, y: to.y - uy * 0.7 * head)
        let left = Point2D(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth)
        let right = Point2D(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth)
        return [
            stroke(VectorPath([.move(to: from), .line(to: shaftEnd)]), color, width),
            .fillPath(VectorPath([.move(to: to), .line(to: left), .line(to: right), .close]), color: color),
        ]
    }

    /// A filled circle of the width's diameter and its computed number (E7) at 0.55 × diameter, centred by its
    /// measured box; black on light colours, white on dark.
    static func step(center: Point2D, annotation: Annotation, state: EditorState, ppp: Double, metrics: EditorMetrics)
        -> [DisplayCommand]
    {
        let d = annotation.style.width.stepDiameter * ppp
        let circle = Rect2D(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        let number = String(state.stepNumber(of: annotation.id) ?? 1)
        let font = FontDescriptor(name: FontDescriptor.systemFontName, size: 0.55 * d, weight: 0.4)
        let m = metrics.measurer.measure(number, font: font)
        let origin = Point2D(x: center.x - m.width / 2, y: center.y + (m.ascent - m.descent) / 2)
        return [
            .fillPath(.ellipse(in: circle), color: annotation.style.color),
            .textRun(number, origin: origin, font: font, color: labelColor(on: annotation.style.color)),
        ]
    }

    /// `0.299r + 0.587g + 0.114b > 0.6` is light.
    public static func labelColor(on color: RGBAColor) -> RGBAColor {
        0.299 * color.red + 0.587 * color.green + 0.114 * color.blue > 0.6 ? black : white
    }

    /// Rounded outward to whole pixels and intersected with the image (plan P4); nil when nothing is left.
    static func integralRect(_ rect: Rect2D, within image: Size2D) -> Rect2D? {
        let r = rect.standardized
        let x0 = r.minX.rounded(.down)
        let y0 = r.minY.rounded(.down)
        let outward = Rect2D(x: x0, y: y0, width: r.maxX.rounded(.up) - x0, height: r.maxY.rounded(.up) - y0)
        return outward.intersection(Rect2D(origin: .zero, size: image))
    }

    // MARK: Overlay

    static func overlayList(
        state: EditorState, layout: CanvasLayout, metrics: EditorMetrics, selection: UUID?, cropMode: Bool,
        zoom: Double
    ) -> DisplayList {
        let pt = layout.ppp / max(zoom, 0.0001)  // one screen point in canvas pixels
        let o = layout.imageOrigin
        var commands: [DisplayCommand] = []
        if cropMode, let crop = state.crop {
            let c = EditorGeometry.offset(crop.standardized, by: o)
            let w = layout.size.width
            let h = layout.size.height
            let dim = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            let pieces = [
                Rect2D(x: 0, y: 0, width: w, height: max(0, c.minY)),
                Rect2D(x: 0, y: c.maxY, width: w, height: max(0, h - c.maxY)),
                Rect2D(x: 0, y: c.minY, width: max(0, c.minX), height: c.height),
                Rect2D(x: c.maxX, y: c.minY, width: max(0, w - c.maxX), height: c.height),
            ]
            for piece in pieces where !piece.isEmpty { commands.append(.fillPath(.rect(piece), color: dim)) }
            commands.append(.strokePath(.rect(c), color: white, lineWidth: pt))
        }
        if !cropMode, let id = selection, let annotation = state.annotation(id) {
            let bounds = EditorGeometry.outset(EditorGeometry.offset(annotation.bounds(metrics), by: o), by: 2 * pt)
            commands.append(.strokePath(.rect(bounds), color: selectionColor, lineWidth: pt, dash: [4 * pt, 3 * pt]))
            let side = 8 * pt
            for handle in annotation.handles(metrics) {
                let p = handle.point + o
                let square = VectorPath.rect(Rect2D(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side))
                commands.append(.fillPath(square, color: white))
                commands.append(.strokePath(square, color: handleBorder, lineWidth: pt))
            }
        }
        return DisplayList(size: layout.size, commands: commands)
    }
}
