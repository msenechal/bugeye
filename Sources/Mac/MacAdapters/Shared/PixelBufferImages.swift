import BugeyeCore
import CoreGraphics
import Foundation

/// The one `PixelBuffer` ↔ `CGImage` conversion (contracts §4.4, K9). `PixelBuffer` is RGBA8, premultiplied
/// alpha, sRGB unless its producer documents otherwise.
public enum PixelBufferImages {
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    /// Wraps the bytes as RGBA8 premultiplied last, tagged `colorSpace` (nil = sRGB), no conversion.
    public static func cgImage(_ buffer: PixelBuffer, colorSpace: CGColorSpace? = nil) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer.bytes) as CFData) else { return nil }
        return CGImage(
            width: buffer.width, height: buffer.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: buffer.bytesPerRow, space: colorSpace ?? sRGB, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draws the image (or `rect`, in its pixels, top-left origin) into RGBA8 premultiplied in `colorSpace`
    /// (nil = sRGB; pass `image.colorSpace` to keep the source's space, Editor E5).
    public static func pixelBuffer(_ image: CGImage, rect: Rect2D? = nil, colorSpace: CGColorSpace? = nil)
        -> PixelBuffer?
    {
        let area = (rect ?? Rect2D(x: 0, y: 0, width: Double(image.width), height: Double(image.height))).standardized
        let width = Int(area.width.rounded())
        let height = Int(area.height.rounded())
        guard width > 0, height > 0 else { return nil }
        // The image placed so that `area`'s top-left lands on the context's top-left (CG's origin is bottom-left).
        let frame = CGRect(
            x: -area.minX, y: area.maxY - Double(image.height), width: Double(image.width),
            height: Double(image.height))
        return render(width: width, height: height, colorSpace: colorSpace ?? sRGB, quality: .none) { context in
            context.draw(image, in: frame)
        }
    }

    /// At most `CaptureEvent.previewMaxWidth` wide, never upscaled, high-quality interpolation, sRGB.
    public static func preview(_ image: CGImage) -> PixelBuffer? {
        let scale = min(1, Double(CaptureEvent.previewMaxWidth) / Double(image.width))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        return render(width: width, height: height, colorSpace: sRGB, quality: .high) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func render(
        width: Int, height: Int, colorSpace: CGColorSpace, quality: CGInterpolationQuality,
        draw: (CGContext) -> Void
    ) -> PixelBuffer? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: colorSpace, bitmapInfo: bitmapInfo)
            else { return false }
            context.interpolationQuality = quality
            context.setBlendMode(.copy)
            draw(context)
            return true
        }
        guard drawn else { return nil }
        return try? PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
    }
}
