import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the Bugeye mark in code (`design/01` §2.15): the app icon (a dark rounded square, white corner
/// brackets, a yellow bug with a blue lens eye) and the menu-bar template glyph (brackets and bug in
/// black, the eye cut out).
enum IconRenderer {
    enum RenderError: Error {
        case noContext, noImage, encodeFailed
    }

    /// Sizes in the `.iconset` folder `iconutil` turns into `Bugeye.icns`.
    static let iconsetFiles: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    /// The menu-bar glyph is 18 pt.
    static let glyphFiles: [(name: String, pixels: Int)] = [("MenuBarIcon.png", 18), ("MenuBarIcon@2x.png", 36)]

    /// RGBA8 premultiplied pixels, top row first.
    static func iconPixels(side: Int) throws -> [UInt8] {
        try render(side: side) { context, s in drawIcon(in: context, side: s) }
    }

    static func glyphPixels(side: Int) throws -> [UInt8] {
        try render(side: side) { context, s in drawGlyph(in: context, side: s) }
    }

    static func png(side: Int, glyph: Bool) throws -> Data {
        let pixels = try glyph ? glyphPixels(side: side) : iconPixels(side: side)
        let image = try makeImage(pixels, side: side)
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encodeFailed }
        return data as Data
    }

    // MARK: Drawing (Core Graphics, origin bottom-left, `s` = side in pixels)

    static func drawIcon(in context: CGContext, side s: CGFloat) {
        let tile = CGRect(x: 0, y: 0, width: s, height: s)
        let rounded = CGPath(roundedRect: tile, cornerWidth: 0.23 * s, cornerHeight: 0.23 * s, transform: nil)
        context.saveGState()
        context.addPath(rounded)
        context.clip()
        let colors = [rgb(0x2B3242), rgb(0x161A23)] as CFArray
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: .zero, options: [])
        }
        context.restoreGState()

        drawBrackets(in: context, side: s, color: CGColor(gray: 1, alpha: 1))
        drawBug(in: context, side: s, body: rgb(0xFFC93C), seam: rgb(0xE5A515))
        let eye = eyeRect(side: s)
        context.setFillColor(rgb(0x3D8BFF))
        context.fillEllipse(in: eye)
        context.setFillColor(CGColor(gray: 1, alpha: 0.85))
        let glint = eye.insetBy(dx: eye.width * 0.32, dy: eye.height * 0.32)
        context.fillEllipse(in: glint.offsetBy(dx: -eye.width * 0.1, dy: eye.height * 0.1))
    }

    static func drawGlyph(in context: CGContext, side s: CGFloat) {
        let black = CGColor(gray: 0, alpha: 1)
        drawBrackets(in: context, side: s, color: black)
        drawBug(in: context, side: s, body: black, seam: nil)
        // Cut the lens out as a ring at least 2 px wide at 1× (design/01 §2.15).
        let eye = eyeRect(side: s)
        context.setBlendMode(.clear)
        context.fillEllipse(in: eye)
        context.setBlendMode(.normal)
        let ring = max(2, s * 0.06)
        context.setFillColor(black)
        context.fillEllipse(in: eye.insetBy(dx: ring, dy: ring))
    }

    static func drawBrackets(in context: CGContext, side s: CGFloat, color: CGColor) {
        let inset = 0.16 * s
        let arm = 0.17 * s
        let lo = inset
        let hi = s - inset
        context.setStrokeColor(color)
        context.setLineWidth(max(1, 0.06 * s))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] {
            context.move(to: CGPoint(x: x, y: y + dy * arm))
            context.addLine(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        context.strokePath()
    }

    static func drawBug(in context: CGContext, side s: CGFloat, body: CGColor, seam: CGColor?) {
        let bodyRect = CGRect(x: 0.35 * s, y: 0.27 * s, width: 0.30 * s, height: 0.36 * s)
        let head = CGRect(x: 0.42 * s, y: 0.58 * s, width: 0.16 * s, height: 0.14 * s)
        context.setFillColor(body)
        context.fillEllipse(in: head)
        context.fillEllipse(in: bodyRect)
        if let seam {
            context.setStrokeColor(seam)
            context.setLineWidth(max(1, 0.02 * s))
            context.move(to: CGPoint(x: bodyRect.midX, y: bodyRect.minY + 0.03 * s))
            context.addLine(to: CGPoint(x: bodyRect.midX, y: bodyRect.maxY - 0.03 * s))
            context.strokePath()
        }
    }

    static func eyeRect(side s: CGFloat) -> CGRect {
        CGRect(x: 0.40 * s, y: 0.36 * s, width: 0.20 * s, height: 0.20 * s)
    }

    // MARK: Bitmaps

    private static func render(side: Int, draw: (CGContext, CGFloat) -> Void) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw RenderError.noContext }
            draw(context, CGFloat(side))
        }
        return pixels
    }

    private static func makeImage(_ pixels: [UInt8], side: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw RenderError.noImage }
        return image
    }

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
