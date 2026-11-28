import BugeyeCore
import BugeyeTestSupport
import CoreGraphics
import EditorCore
import Foundation
import MacAdapters
import Testing

@testable import BugeyeApp

/// Pixel probes of the export render (§9 macOS CI, E21): colours at named points and ink bounds, computed here.
@Suite struct EditorExportTests {
    static let red = RGBA8(red: 255, green: 0, blue: 0)
    static let blue = RGBA8(red: 0, green: 0, blue: 255)

    /// A capture whose top half is red and bottom half blue (sRGB, opaque), or any per-pixel colour.
    static func capture(width: Int, height: Int, _ pixel: (Int, Int) -> RGBA8) throws -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                bytes += [p.red, p.green, p.blue, p.alpha]
            }
        }
        let buffer = try PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
        return try #require(PixelBufferImages.cgImage(buffer))
    }

    static func topRedBottomBlue(_ width: Int = 100, _ height: Int = 60) throws -> CGImage {
        try capture(width: width, height: height) { _, y in y < height / 2 ? red : blue }
    }

    static func render(_ state: EditorState, _ capture: CGImage, ppp: Double = 1) throws -> PixelBuffer {
        let image = try #require(
            EditorImages.render(
                state: state, capture: capture, metrics: EditorMetrics(ppp: ppp, measurer: CoreTextMeasurer()),
                blur: BlurCache()))
        return try #require(PixelBufferImages.pixelBuffer(image))
    }

    static func close(_ a: RGBA8?, _ b: RGBA8, tolerance: Int = 3) -> Bool {
        guard let a else { return false }
        return abs(Int(a.red) - Int(b.red)) <= tolerance && abs(Int(a.green) - Int(b.green)) <= tolerance
            && abs(Int(a.blue) - Int(b.blue)) <= tolerance && abs(Int(a.alpha) - Int(b.alpha)) <= tolerance
    }

    @Test func aShapeAtTheTopLeftLandsTopLeft() throws {
        let state = EditorState(annotations: [
            Annotation(
                shape: .rectangle(Rect2D(x: 0, y: 0, width: 10, height: 10), filled: true),
                style: AnnotationStyle(color: RGBAColor(red: 0, green: 0, blue: 0)))
        ])
        let buffer = try Self.render(state, try Self.topRedBottomBlue())
        #expect(Self.close(buffer.pixel(x: 2, y: 2), RGBA8(red: 0, green: 0, blue: 0)))
        #expect(Self.close(buffer.pixel(x: 50, y: 5), Self.red))
        #expect(Self.close(buffer.pixel(x: 50, y: 55), Self.blue))
    }

    @Test(arguments: [BlurMode.pixelate, .blur])
    func aStrongBlurSamplesThePixelsUnderIt(mode: BlurMode) throws {
        let state = EditorState(annotations: [
            Annotation(shape: .blur(Rect2D(x: 0, y: 0, width: 60, height: 20), mode: mode, strength: 3))
        ])
        let buffer = try Self.render(state, try Self.topRedBottomBlue(100, 120))
        // a mirrored source would bring the blue bottom up
        #expect(Self.close(buffer.pixel(x: 30, y: 10), Self.red, tolerance: 8))
        #expect(Self.close(buffer.pixel(x: 30, y: 110), Self.blue))
    }

    @Test func aBlurReallyChangesThePixelsUnderIt() throws {
        let stripes = try Self.capture(width: 60, height: 60) { x, _ in x % 2 == 0 ? Self.red : Self.blue }
        let state = EditorState(annotations: [
            Annotation(shape: .blur(Rect2D(x: 0, y: 0, width: 60, height: 60), mode: .pixelate, strength: 3))
        ])
        let buffer = try Self.render(state, stripes, ppp: 2)
        let a = try #require(buffer.pixel(x: 10, y: 10))
        let b = try #require(buffer.pixel(x: 11, y: 10))
        #expect(a == b)
        #expect(a.red > 60 && a.blue > 60)
    }

    @Test func cropFrameAnd2xGiveTheRightSizesAndPlaces() throws {
        let capture = try Self.capture(width: 200, height: 100) { x, y in RGBA8(red: UInt8(x), green: UInt8(y), blue: 7)
        }
        let state = EditorState(
            crop: Rect2D(x: 20, y: 10, width: 100, height: 50),
            frame: BackgroundFrame(padding: 10, fill: .black, cornerRadius: 10, shadow: false))
        let buffer = try Self.render(state, capture, ppp: 2)
        #expect(buffer.width == 140 && buffer.height == 90)
        #expect(Self.close(buffer.pixel(x: 2, y: 2), RGBA8(red: 0, green: 0, blue: 0)))
        #expect(Self.close(buffer.pixel(x: 21, y: 21), RGBA8(red: 0, green: 0, blue: 0)))  // the rounded corner
        #expect(Self.close(buffer.pixel(x: 70, y: 45), RGBA8(red: 70, green: 35, blue: 7)))
    }

    @Test func theFrameShadowFollowsATransparentCapturesContent() throws {
        let capture = try Self.capture(width: 100, height: 100) { x, y in
            (40..<60).contains(x) && (40..<60).contains(y) ? Self.red : RGBA8(red: 0, green: 0, blue: 0, alpha: 0)
        }
        let state = EditorState(frame: BackgroundFrame(padding: 20, fill: .white, cornerRadius: 0, shadow: true))
        let buffer = try Self.render(state, capture)
        let white = RGBA8(red: 255, green: 255, blue: 255)
        #expect(Self.close(buffer.pixel(x: 70, y: 70), Self.red))
        let under = try #require(buffer.pixel(x: 70, y: 83))  // below the square: in its shadow
        #expect(under.red < 235)
        #expect(Self.close(buffer.pixel(x: 112, y: 30), white))  // inside the content, far from the square
    }

    @Test func overlappingHighlighterStrokesDoNotDarken() throws {
        let white = try Self.capture(width: 200, height: 60) { _, _ in RGBA8(red: 255, green: 255, blue: 255) }
        let state = EditorState(annotations: [
            Annotation(
                shape: .highlighter([
                    Point2D(x: 20, y: 30), Point2D(x: 180, y: 30), Point2D(x: 100, y: 30), Point2D(x: 100, y: 31),
                ]), style: AnnotationStyle(color: RGBAColor(red: 0, green: 0, blue: 1)))
        ])
        let buffer = try Self.render(state, white)
        let single = try #require(buffer.pixel(x: 40, y: 30))
        let overlap = try #require(buffer.pixel(x: 120, y: 30))
        #expect(single.red < 200)  // 40 % blue over white
        #expect(abs(Int(single.red) - Int(overlap.red)) <= 2)
    }

    @Test func textMatchesCoreTextMeasurer() throws {
        let white = try Self.capture(width: 300, height: 80) { _, _ in RGBA8(red: 255, green: 255, blue: 255) }
        let state = EditorState(annotations: [
            Annotation(
                shape: .text(origin: Point2D(x: 10, y: 10), string: "Hello", fontSize: 36),
                style: AnnotationStyle(color: RGBAColor(red: 0, green: 0, blue: 0)))
        ])
        let buffer = try Self.render(state, white)
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        for y in 0..<buffer.height {
            for x in 0..<buffer.width where (buffer.pixel(x: x, y: y)?.red ?? 255) < 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
            }
        }
        let font = TextLayout.font(fontSize: 36, ppp: 1)
        let measured = CoreTextMeasurer().measure("Hello", font: font)
        #expect(Double(maxX - minX + 1) <= measured.width + 1)
        #expect(Double(maxX - minX + 1) >= measured.width * 0.8)
        #expect(minY >= 10)
        #expect(Double(minY) < 10 + measured.ascent)
    }

    @Test func aPNGRoundTripsAndDecodeKeepsTheSize() throws {
        let dir = try TempDirectory("editor-png")
        defer { dir.remove() }
        let image = try Self.topRedBottomBlue()
        let data = try #require(EditorImages.encodePNG(image))
        let url = dir.file("a.png")
        try data.write(to: url)
        let decoded = try EditorImages.decode(url).get()
        #expect(decoded.width == 100 && decoded.height == 60)
        guard case .failure(let failure) = EditorImages.decode(dir.file("missing.png")) else {
            Issue.record("decoded a missing file")
            return
        }
        #expect(failure.reason == "missing")
        try Data("junk".utf8).write(to: dir.file("junk.png"))
        guard case .failure(let junk) = EditorImages.decode(dir.file("junk.png")) else {
            Issue.record("decoded junk")
            return
        }
        #expect(junk.reason == "unreadable")
    }

    @Test func theBlurCacheIsClearedPast64Entries() throws {
        let image = try Self.topRedBottomBlue()
        let cache = BlurCache()
        for i in 0..<64 {
            _ = cache.image(
                image, rect: Rect2D(x: 0, y: 0, width: 4, height: 4), effect: .pixelate(cellSize: Double(i + 1)))
        }
        #expect(cache.count == 64)
        _ = cache.image(image, rect: Rect2D(x: 0, y: 0, width: 4, height: 4), effect: .pixelate(cellSize: 100))
        #expect(cache.count == 1)
    }
}
