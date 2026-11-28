import BugeyeCore
import CoreGraphics
import Foundation
import ImageIO

/// Decodes image files with ImageIO (OCR §3.4, §7, T11): the one decoder of a file into a `PixelBuffer`
/// (contracts K9). Pixels come out RGBA8, premultiplied, converted to sRGB (T8). Runs off the main actor.
public struct ImageIOFileReader: ImageFileReader {
    public init() {}

    @concurrent public func info(of url: URL) async throws -> ImageFileInfo {
        let fingerprint = try Self.fingerprint(of: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0, height > 0
        else { throw ImageFileError.unreadable(url) }
        return ImageFileInfo(width: width, height: height, fingerprint: fingerprint)
    }

    @concurrent public func pixels(of url: URL, rows: Range<Int>?) async throws -> PixelBuffer {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImageFileError.missing(url) }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageFileError.unreadable(url) }
        let range = (rows ?? 0..<image.height).clamped(to: 0..<image.height)
        // Crop first (CGImage rects are top-left origin), then draw only those rows into sRGB (§7).
        guard !range.isEmpty,
            let rows = image.cropping(
                to: CGRect(x: 0, y: range.lowerBound, width: image.width, height: range.count)),
            let pixels = PixelBufferImages.pixelBuffer(rows)
        else { throw ImageFileError.unreadable(url) }
        return pixels
    }

    /// Size and content-modification date, from the file's resource values.
    static func fingerprint(of url: URL) throws -> FileFingerprint {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImageFileError.missing(url) }
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize, let modified = values.contentModificationDate
        else { throw ImageFileError.unreadable(url) }
        return FileFingerprint(size: Int64(size), modified: modified)
    }
}
