import BugeyeCore
import CoreGraphics
import CoreText
import Foundation

/// Runs a `DisplayList` with Core Graphics (Editor E11, contracts K10): the editor's canvas and exports, and
/// Recording's overlay window, all draw through it.
///
/// The list is top-left, y down, in its own pixels. `execute` does the one flip (when the context is y-up), and
/// draws images, blur results and text upright in that y-down space. Shadow offsets and blurs are multiplied by the
/// context's device scale, because `setShadow` works in device space and ignores the CTM (`design/03` §2.6,
/// `27eebe8`).
public struct DisplayListExecutor: Sendable {
    /// The image registered under an id (the editor registers the capture as "capture").
    public typealias ImageProvider = @Sendable (_ imageID: String) -> CGImage?
    /// `sourceRect` (pixels of the image registered under `sourceImageID`, top-left) with `effect` applied, edges
    /// clamped to `sourceRect`, as an image of `sourceRect`'s size; nil draws nothing.
    public typealias BlurProvider =
        @Sendable (_ sourceImageID: String, _ sourceRect: Rect2D, _ effect: BlurEffect) -> CGImage?

    private let images: ImageProvider
    private let blur: BlurProvider

    public init(images: @escaping ImageProvider = { _ in nil }, blur: @escaping BlurProvider = { _, _, _ in nil }) {
        self.images = images
        self.blur = blur
    }

    /// √|det| of the context's user-space-to-device transform: 1 in a 1:1 bitmap, 2 on a Retina view at 100 %.
    public static func deviceScale(of context: CGContext) -> Double {
        let t = context.userSpaceToDeviceSpaceTransform
        let scale = (abs(Double(t.a * t.d - t.b * t.c))).squareRoot()
        return scale > 0 ? scale : 1
    }

    /// Draws `list` into `context`, whose current user space maps one unit to one list pixel with the list's
    /// top-left at the user-space origin. With `contextIsFlipped` false (y up, e.g. a bitmap context) the executor
    /// flips once about `list.size.height`, so the list must span the context's height; with true (a flipped
    /// `NSView`'s context, already y down) it draws as is. The graphics state, text matrix and text position are
    /// restored afterwards. Drawing stops at a `popGroup` with no matching push; groups left open at the end are
    /// closed; a `clip` outside any group is ignored (`DisplayList.isBalanced` rejects it). Group opacities multiply
    /// when nested; a nested group's shadow replaces its parent's for the drawing inside it.
    public func execute(_ list: DisplayList, in context: CGContext, contextIsFlipped: Bool) {
        context.saveGState()
        let textMatrix = context.textMatrix
        let textPosition = context.textPosition
        defer {
            context.restoreGState()
            context.textMatrix = textMatrix
            context.textPosition = textPosition
        }
        if !contextIsFlipped {
            context.translateBy(x: 0, y: CGFloat(list.size.height))
            context.scaleBy(x: 1, y: -1)
        }
        let scale = Self.deviceScale(of: context)
        var layers: [Bool] = []  // per open group: did it begin a transparency layer?
        // The alpha a group's drawing composes with: `setAlpha` replaces the context's alpha, so nested groups
        // multiply it here. Inside a transparency layer CG resets alpha to 1, so an isolated group's children start
        // from 1 again.
        var alphas: [Double] = [1]

        for command in list.commands {
            switch command {
            case .fillPath(let path, let color):
                context.setFillColor(Self.cgColor(color))
                context.addPath(Self.cgPath(path))
                context.fillPath()

            case .strokePath(let path, let color, let lineWidth, let cap, let join, let dash):
                context.saveGState()
                context.setStrokeColor(Self.cgColor(color))
                context.setLineWidth(CGFloat(lineWidth))
                context.setLineCap(Self.cgCap(cap))
                context.setLineJoin(Self.cgJoin(join))
                context.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) })
                context.addPath(Self.cgPath(path))
                context.strokePath()
                context.restoreGState()

            case .fillLinearGradient(let path, let stops, let start, let end):
                guard !stops.isEmpty else { continue }
                let colors = stops.map { Self.cgColor($0.color) } as CFArray
                let locations = stops.map { CGFloat($0.location) }
                guard
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations)
                else { continue }
                context.saveGState()
                context.addPath(Self.cgPath(path))
                context.clip()
                context.drawLinearGradient(
                    gradient, start: Self.cgPoint(start), end: Self.cgPoint(end),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.restoreGState()

            case .image(let imageID, let rect):
                guard let image = images(imageID) else { continue }
                Self.drawUpright(image, in: rect, context: context)

            case .textRun(let string, let origin, let font, let color):
                Self.drawText(string, origin: origin, font: font, color: color, context: context)

            case .blurRegion(let rect, let sourceImageID, let sourceRect, let effect):
                guard let image = blur(sourceImageID, sourceRect, effect) else { continue }
                Self.drawUpright(image, in: rect, context: context)

            case .pushGroup(let style):
                context.saveGState()
                let effective = (alphas.last ?? 1) * style.opacity
                context.setAlpha(CGFloat(effective))
                if let shadow = style.shadow {
                    // Device space is y up: a shadow that falls down the list has a negative device offset.
                    context.setShadow(
                        offset: CGSize(width: shadow.offset.x * scale, height: -shadow.offset.y * scale),
                        blur: CGFloat(shadow.blur * scale), color: Self.cgColor(shadow.color))
                }
                if style.isolated {
                    if let bounds = style.bounds {
                        context.beginTransparencyLayer(in: Self.cgRect(bounds), auxiliaryInfo: nil)
                    } else {
                        context.beginTransparencyLayer(auxiliaryInfo: nil)
                    }
                    layers.append(true)
                    alphas.append(1)
                } else {
                    layers.append(false)
                    alphas.append(effective)
                }

            case .popGroup:
                guard let layer = layers.popLast() else { return }
                alphas.removeLast()
                if layer { context.endTransparencyLayer() }
                context.restoreGState()

            case .clip(let path):
                guard !layers.isEmpty else { continue }
                context.addPath(Self.cgPath(path))
                context.clip()
            }
        }
        while let layer = layers.popLast() {
            if layer { context.endTransparencyLayer() }
            context.restoreGState()
        }
    }

    /// Renders `list` into a new RGBA8 premultiplied-last bitmap of `list.size` (rounded up) in `colorSpace`
    /// (nil or a non-RGB space: sRGB). Nil when the size is empty or the context can't be made.
    public func render(_ list: DisplayList, colorSpace: CGColorSpace? = nil) -> CGImage? {
        let maximum = 1 << 16
        guard list.size.width.isFinite, list.size.height.isFinite, list.size.width > 0, list.size.height > 0,
            list.size.width <= Double(maximum), list.size.height <= Double(maximum)
        else { return nil }
        let width = Int(list.size.width.rounded(.up))
        let height = Int(list.size.height.rounded(.up))
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func makeContext(_ space: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        }
        let requested = colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        guard let context = requested.flatMap(makeContext) ?? makeContext(sRGB) else { return nil }
        context.interpolationQuality = .high
        // A list smaller than the rounded-up bitmap still starts at its top-left.
        context.translateBy(x: 0, y: CGFloat(Double(height) - list.size.height))
        execute(list, in: context, contextIsFlipped: false)
        return context.makeImage()
    }

    // MARK: Conversions

    static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(
            srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha))
    }

    static func cgPoint(_ point: Point2D) -> CGPoint { CGPoint(x: point.x, y: point.y) }

    static func cgRect(_ rect: Rect2D) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    static func cgCap(_ cap: LineCap) -> CGLineCap {
        switch cap {
        case .butt: .butt
        case .round: .round
        case .square: .square
        }
    }

    static func cgJoin(_ join: LineJoin) -> CGLineJoin {
        switch join {
        case .miter: .miter
        case .round: .round
        case .bevel: .bevel
        }
    }

    static func cgPath(_ path: VectorPath) -> CGPath {
        let result = CGMutablePath()
        for element in path.elements {
            switch element {
            case .move(let to): result.move(to: cgPoint(to))
            case .line(let to): result.addLine(to: cgPoint(to))
            case .quadCurve(let to, let control): result.addQuadCurve(to: cgPoint(to), control: cgPoint(control))
            case .curve(let to, let control1, let control2):
                result.addCurve(to: cgPoint(to), control1: cgPoint(control1), control2: cgPoint(control2))
            case .close: result.closeSubpath()
            }
        }
        return result
    }

    /// `CGContext.draw` assumes y up; in the executor's y-down space the image is flipped locally so its first
    /// row lands at `rect`'s top.
    static func drawUpright(_ image: CGImage, in rect: Rect2D, context: CGContext) {
        context.saveGState()
        context.translateBy(x: CGFloat(rect.minX), y: CGFloat(rect.maxY))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    /// Core Text lays out y up: the text matrix flips the glyphs back upright at the baseline origin.
    static func drawText(
        _ string: String, origin: Point2D, font: FontDescriptor, color: RGBAColor, context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CoreTextFonts.font(for: font),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(color),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = cgPoint(origin)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
