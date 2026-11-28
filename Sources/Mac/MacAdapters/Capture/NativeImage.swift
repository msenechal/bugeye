import BugeyeCore
import CoreGraphics
import Foundation

/// The storage of a `CapturedImage` made on macOS: a `CGImage` in its display's colour space (Capture C7, plan P3).
public final class NativeImage: @unchecked Sendable {
    // CGImage is immutable; the box only makes the reference crossable between tasks.
    public let cgImage: CGImage

    public init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

extension CapturedImage {
    public init(cgImage: CGImage) {
        self.init(pixelWidth: cgImage.width, pixelHeight: cgImage.height, storage: NativeImage(cgImage))
    }

    /// The `CGImage` behind this image; a fake's `PixelBuffer` storage is wrapped as sRGB.
    public var cgImage: CGImage? {
        if let native = storage as? NativeImage { return native.cgImage }
        if let buffer = storage as? PixelBuffer { return PixelBufferImages.cgImage(buffer) }
        return nil
    }
}
