import BugeyeCore
import CaptureCore
import Foundation
import Synchronization
import Testing

/// A transparent image with an opaque body and a faint shadow ring around it.
func shadowedImage(width: Int, height: Int, body: Rect2D, shadowAlpha: UInt8 = 60) throws -> PixelBuffer {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let p = Point2D(x: Double(x), y: Double(y))
            let alpha: UInt8
            if body.contains(p) {
                alpha = 255
            } else if Rect2D(x: body.minX - 6, y: body.minY - 6, width: body.width + 12, height: body.height + 12)
                .contains(p)
            {
                alpha = shadowAlpha
            } else {
                alpha = 0
            }
            bytes[(y * width + x) * 4 + 3] = alpha
        }
    }
    return try PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
}

@Suite struct WindowShadowTests {
    @Test func theBodyIsFoundByOpacity() throws {
        let image = try shadowedImage(width: 120, height: 100, body: Rect2D(x: 10, y: 12, width: 100, height: 70))
        #expect(WindowShadow.body(in: image) == PixelRect(x: 10, y: 12, width: 100, height: 70))
    }

    @Test func edgesThatDisagreeByMoreThanTwoPixelsGiveNoBody() throws {
        var image = try shadowedImage(width: 120, height: 100, body: Rect2D(x: 10, y: 12, width: 100, height: 70))
        // A notch on the left edge at the ¼ row: that row's edge sits 5 px further right.
        var bytes = image.bytes
        let row = 100 / 4
        for x in 10..<15 { bytes[(row * 120 + x) * 4 + 3] = 0 }
        image = try PixelBuffer(width: 120, height: 100, bytesPerRow: 480, bytes: bytes)
        #expect(WindowShadow.body(in: image) == nil)
    }

    @Test func aFullyTransparentImageHasNoBody() throws {
        #expect(
            WindowShadow.body(
                in: try PixelBuffer(width: 10, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0, alpha: 0))) == nil)
    }

    @Test func aSqueezedCaptureIsTakenAgainLargerOnce() async throws {
        // A 100 × 50 pt window at 2×: the first capture at 200 × 100 px squeezes the body to 166 px wide.
        let first = try shadowedImage(width: 200, height: 100, body: Rect2D(x: 17, y: 8, width: 166, height: 83))
        let second = try shadowedImage(width: 241, height: 120, body: Rect2D(x: 20, y: 10, width: 200, height: 100))
        let sizes = Mutex<[Size2D]>([])
        let result = try await WindowShadow.atFullScale(
            windowSize: Size2D(width: 100, height: 50), scale: 2,
            capture: { size in
                let count = sizes.withLock {
                    $0.append(size)
                    return $0.count
                }
                return CapturedImage(pixelBuffer: count == 1 ? first : second)
            }, measure: { $0.storage as? PixelBuffer })
        let asked = sizes.withLock { $0 }
        #expect(asked.count == 2)
        #expect(asked[0] == Size2D(width: 200, height: 100))
        // 200 × 100 × 2 / 1.66 = 240.96 × 120.48, rounded.
        #expect(asked[1] == Size2D(width: 241, height: 120))
        #expect(result.pixelWidth == 241)
    }

    @Test func aCaptureAtFullScaleIsKept() async throws {
        let image = try shadowedImage(width: 200, height: 100, body: Rect2D(x: 0, y: 0, width: 200, height: 100))
        let count = Mutex(0)
        let result = try await WindowShadow.atFullScale(
            windowSize: Size2D(width: 100, height: 50), scale: 2,
            capture: { _ in
                count.withLock { $0 += 1 }
                return CapturedImage(pixelBuffer: image)
            }, measure: { $0.storage as? PixelBuffer })
        #expect(count.withLock { $0 } == 1)
        #expect(result.pixelWidth == 200)
    }

    @Test func noBodyKeepsTheFirstImage() async throws {
        let blank = try PixelBuffer(width: 200, height: 100, fill: RGBA8(red: 0, green: 0, blue: 0, alpha: 0))
        let count = Mutex(0)
        _ = try await WindowShadow.atFullScale(
            windowSize: Size2D(width: 100, height: 50), scale: 2,
            capture: { _ in
                count.withLock { $0 += 1 }
                return CapturedImage(pixelBuffer: blank)
            }, measure: { $0.storage as? PixelBuffer })
        #expect(count.withLock { $0 } == 1)
    }

    @Test func aOneXWindowSqueezedIsRecapturedToo() async throws {
        let first = try shadowedImage(width: 400, height: 300, body: Rect2D(x: 34, y: 25, width: 333, height: 250))
        let sizes = Mutex<[Size2D]>([])
        _ = try await WindowShadow.atFullScale(
            windowSize: Size2D(width: 400, height: 300), scale: 1,
            capture: { size in
                sizes.withLock { $0.append(size) }
                return CapturedImage(pixelBuffer: first)
            }, measure: { $0.storage as? PixelBuffer })
        #expect(sizes.withLock { $0.count } == 2)
    }
}
