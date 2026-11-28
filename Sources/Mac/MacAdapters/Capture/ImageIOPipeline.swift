import BugeyeCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `ImagePipeline` on Core Graphics and ImageIO (Capture C7): crop, downscale in the image's own colour space, PNG.
/// It never decodes a file (contracts K9).
public struct ImageIOPipeline: ImagePipeline {
    public init() {}

    public func crop(_ image: CapturedImage, to rect: Rect2D) -> CapturedImage? {
        guard let cg = image.cgImage else { return nil }
        // CGImage.cropping(to:) takes pixels with the origin at the image's top-left.
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let wanted = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height).intersection(bounds)
        guard !wanted.isNull, wanted.width >= 1, wanted.height >= 1, let cropped = cg.cropping(to: wanted) else {
            return nil
        }
        return CapturedImage(cgImage: cropped)
    }

    public func downscale(_ image: CapturedImage, by factor: Double) -> CapturedImage? {
        guard let cg = image.cgImage, factor > 0 else { return nil }
        let width = max(1, Int((Double(cg.width) * factor).rounded()))
        let height = max(1, Int((Double(cg.height) * factor).rounded()))
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = cg.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: bitmapInfo)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { CapturedImage(cgImage: $0) }
    }

    public func pngData(_ image: CapturedImage) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public func pixelBuffer(_ image: CapturedImage) -> PixelBuffer? {
        image.cgImage.flatMap { PixelBufferImages.pixelBuffer($0) }
    }

    public func preview(_ image: CapturedImage) -> PixelBuffer? {
        image.cgImage.flatMap { PixelBufferImages.preview($0) }
    }
}
