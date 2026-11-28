import BugeyeCore
import BugeyeTestSupport
import CoreGraphics
import Foundation
import ImageIO
import MacAdapters
import Testing
import UniformTypeIdentifiers

/// Writes a PNG of `width` × `height` whose row y is filled by `fill(y)`, in `space`.
func writePNG(
    _ url: URL, width: Int, height: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
    fill: (Int) -> (CGFloat, CGFloat, CGFloat)
) throws {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for y in 0..<height {
        let (r, g, b) = fill(y)
        context.setFillColor(CGColor(colorSpace: space, components: [r, g, b, 1])!)
        // CG's origin is bottom-left: row y from the top is at height − 1 − y.
        context.fill(CGRect(x: 0, y: height - 1 - y, width: width, height: 1))
    }
    let image = try #require(context.makeImage())
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite struct ImageIOFileReaderTests {
    @Test func infoGivesTheSizeAndFingerprint() async throws {
        let folder = try TempDirectory("imageio")
        defer { folder.remove() }
        let url = folder.file("a.png")
        try writePNG(url, width: 7, height: 5) { _ in (1, 1, 1) }
        let info = try await ImageIOFileReader().info(of: url)
        #expect(info.width == 7)
        #expect(info.height == 5)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        #expect(info.fingerprint.size == Int64(size ?? -1))
    }

    @Test func aRowRangeIsDecodedTopRowFirst() async throws {
        let folder = try TempDirectory("imageio")
        defer { folder.remove() }
        let url = folder.file("rows.png")
        try writePNG(url, width: 4, height: 6) { y in (CGFloat(y * 40) / 255, 0, 0) }
        let rows = try await ImageIOFileReader().pixels(of: url, rows: 2..<4)
        #expect(rows.width == 4)
        #expect(rows.height == 2)
        #expect(rows.pixel(x: 0, y: 0)?.red == 80)
        #expect(rows.pixel(x: 3, y: 1)?.red == 120)
        let all = try await ImageIOFileReader().pixels(of: url, rows: nil)
        #expect(all.height == 6)
        #expect(all.pixel(x: 0, y: 5)?.red == 200)
    }

    @Test func aP3PNGComesBackInSRGB() async throws {
        let folder = try TempDirectory("imageio")
        defer { folder.remove() }
        let url = folder.file("p3.png")
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        try writePNG(url, width: 2, height: 2, space: p3) { _ in (0.8, 0.2, 0.2) }
        let pixel = try #require(try await ImageIOFileReader().pixels(of: url, rows: nil).pixel(x: 0, y: 0))
        // P3 (0.8, 0.2, 0.2) is more saturated than sRGB (204, 51, 51): converted, red rises and green falls.
        #expect(pixel.red > 210)
        #expect(pixel.green < 45)
        #expect(pixel.alpha == 255)
    }

    @Test func theFingerprintChangesAfterACaptureFileWriterRewrite() async throws {
        let folder = try TempDirectory("imageio")
        defer { folder.remove() }
        let url = folder.file("edit.png")
        try writePNG(url, width: 3, height: 3) { _ in (1, 1, 1) }
        let before = try await ImageIOFileReader().info(of: url).fingerprint
        let data = try Data(contentsOf: url)
        try CaptureFileWriter(metadata: XattrMetadataStore()).write(data, to: url)
        let after = try await ImageIOFileReader().info(of: url).fingerprint
        #expect(before != after)
    }

    @Test func aMissingFileIsMissing() async throws {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).png")
        await #expect(throws: ImageFileError.missing(url)) { try await ImageIOFileReader().info(of: url) }
        await #expect(throws: ImageFileError.missing(url)) { try await ImageIOFileReader().pixels(of: url, rows: nil) }
    }

    @Test func aFileThatIsNotAnImageIsUnreadable() async throws {
        let folder = try TempDirectory("imageio")
        defer { folder.remove() }
        let url = folder.file("text.png")
        try Data("not a png".utf8).write(to: url)
        await #expect(throws: ImageFileError.unreadable(url)) { try await ImageIOFileReader().info(of: url) }
    }
}
