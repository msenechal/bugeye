import BugeyeCore
import CoreGraphics
import Foundation
import MacAdapters
import Synchronization
import Testing

/// Probe tests (Editor E21): colours at named points and bounding boxes of non-transparent pixels, computed here,
/// never stored images.
@Suite struct DisplayListExecutorTests {
    static let red = RGBAColor(red: 1, green: 0, blue: 0)
    static let blue = RGBAColor(red: 0, green: 0, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)

    /// Renders and reads back top-left RGBA8 (sRGB).
    static func pixels(_ list: DisplayList, executor: DisplayListExecutor = DisplayListExecutor()) throws
        -> PixelBuffer
    {
        let image = try #require(executor.render(list))
        return try #require(PixelBufferImages.pixelBuffer(image))
    }

    /// The bounding box (minX, minY, maxX, maxY) of pixels with alpha above `threshold`, or nil.
    static func inkBounds(_ buffer: PixelBuffer, threshold: UInt8 = 16) -> (Int, Int, Int, Int)? {
        var box: (Int, Int, Int, Int)?
        for y in 0..<buffer.height {
            for x in 0..<buffer.width where (buffer.pixel(x: x, y: y)?.alpha ?? 0) > threshold {
                if let b = box {
                    box = (min(b.0, x), min(b.1, y), max(b.2, x), max(b.3, y))
                } else {
                    box = (x, y, x, y)
                }
            }
        }
        return box
    }

    /// A 2 × 2 image: top row red, bottom row blue.
    static func redOverBlue() throws -> CGImage {
        let bytes: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255]
        let buffer = try PixelBuffer(width: 2, height: 2, bytesPerRow: 8, bytes: bytes)
        return try #require(PixelBufferImages.cgImage(buffer))
    }

    @Test func aFillAtTheTopLeftLandsTopLeft() throws {
        let list = DisplayList(
            size: Size2D(width: 20, height: 20),
            commands: [.fillPath(.rect(Rect2D(x: 0, y: 0, width: 5, height: 5)), color: Self.red)])
        let buffer = try Self.pixels(list)
        #expect(buffer.pixel(x: 1, y: 1) == RGBA8(red: 255, green: 0, blue: 0))
        #expect(buffer.pixel(x: 18, y: 18)?.alpha == 0)
        #expect(buffer.pixel(x: 1, y: 18)?.alpha == 0)
    }

    @Test func anImagesTopRowLandsAtTheTop() throws {
        let image = try Self.redOverBlue()
        let executor = DisplayListExecutor(images: { $0 == "capture" ? image : nil })
        let list = DisplayList(
            size: Size2D(width: 10, height: 10),
            commands: [.image(imageID: "capture", rect: Rect2D(x: 0, y: 0, width: 10, height: 10))])
        let buffer = try Self.pixels(list, executor: executor)
        #expect(buffer.pixel(x: 5, y: 1) == RGBA8(red: 255, green: 0, blue: 0))
        #expect(buffer.pixel(x: 5, y: 8) == RGBA8(red: 0, green: 0, blue: 255))
    }

    @Test func anUnknownImageDrawsNothing() throws {
        let list = DisplayList(
            size: Size2D(width: 10, height: 10),
            commands: [.image(imageID: "missing", rect: Rect2D(x: 0, y: 0, width: 10, height: 10))])
        #expect(Self.inkBounds(try Self.pixels(list)) == nil)
    }

    @Test func aBlurRegionAsksForItsSourceAndDrawsTheResultUprightAtItsRect() throws {
        let image = try Self.redOverBlue()
        let asked = Mutex<[String]>([])
        let executor = DisplayListExecutor(blur: { id, source, effect in
            asked.withLock { $0.append("\(id) \(source) \(effect)") }
            return image
        })
        let source = Rect2D(x: 7, y: 3, width: 4, height: 4)
        let list = DisplayList(
            size: Size2D(width: 10, height: 10),
            commands: [
                .blurRegion(
                    Rect2D(x: 2, y: 2, width: 4, height: 4), sourceImageID: "capture", sourceRect: source,
                    effect: .pixelate(cellSize: 12))
            ])
        let buffer = try Self.pixels(list, executor: executor)
        #expect(asked.withLock { $0 } == ["capture \(source) \(BlurEffect.pixelate(cellSize: 12))"])
        #expect(buffer.pixel(x: 3, y: 2) == RGBA8(red: 255, green: 0, blue: 0))
        #expect(buffer.pixel(x: 3, y: 5) == RGBA8(red: 0, green: 0, blue: 255))
        #expect(buffer.pixel(x: 0, y: 0)?.alpha == 0)
        #expect(buffer.pixel(x: 8, y: 8)?.alpha == 0)
    }

    @Test func strokesHonourTheirCapAndDash() throws {
        let line = VectorPath([.move(to: Point2D(x: 4, y: 10)), .line(to: Point2D(x: 36, y: 10))])
        let butt = DisplayList(
            size: Size2D(width: 40, height: 20),
            commands: [.strokePath(line, color: Self.black, lineWidth: 4, cap: .butt)])
        let round = DisplayList(
            size: Size2D(width: 40, height: 20),
            commands: [.strokePath(line, color: Self.black, lineWidth: 4, cap: .round)])
        #expect(try Self.pixels(butt).pixel(x: 2, y: 10)?.alpha == 0)
        #expect((try Self.pixels(round).pixel(x: 2, y: 10)?.alpha ?? 0) > 200)

        let dashed = DisplayList(
            size: Size2D(width: 40, height: 20),
            commands: [.strokePath(line, color: Self.black, lineWidth: 4, dash: [4, 4])])
        let buffer = try Self.pixels(dashed)
        #expect(buffer.pixel(x: 6, y: 10)?.alpha == 255)
        #expect(buffer.pixel(x: 10, y: 10)?.alpha == 0)
    }

    @Test func gradientsRunFromStartToEndAndExtendPastBoth() throws {
        let list = DisplayList(
            size: Size2D(width: 100, height: 10),
            commands: [
                .fillLinearGradient(
                    .rect(Rect2D(x: 0, y: 0, width: 100, height: 10)),
                    stops: [GradientStop(location: 0, color: Self.red), GradientStop(location: 1, color: Self.blue)],
                    start: Point2D(x: 20, y: 5), end: Point2D(x: 80, y: 5))
            ])
        let buffer = try Self.pixels(list)
        #expect(buffer.pixel(x: 5, y: 5) == RGBA8(red: 255, green: 0, blue: 0))
        #expect(buffer.pixel(x: 95, y: 5) == RGBA8(red: 0, green: 0, blue: 255))
    }

    @Test func aClipLimitsDrawingUntilItsGroupPops() throws {
        let list = DisplayList(
            size: Size2D(width: 20, height: 20),
            commands: [
                .pushGroup(GroupStyle()),
                .clip(.rect(Rect2D(x: 0, y: 0, width: 10, height: 10))),
                .fillPath(.rect(Rect2D(x: 0, y: 0, width: 20, height: 20)), color: Self.red),
                .popGroup,
                .fillPath(.rect(Rect2D(x: 15, y: 0, width: 5, height: 5)), color: Self.blue),
            ])
        let buffer = try Self.pixels(list)
        #expect(buffer.pixel(x: 5, y: 5)?.alpha == 255)
        #expect(buffer.pixel(x: 15, y: 15)?.alpha == 0)
        #expect(buffer.pixel(x: 17, y: 2) == RGBA8(red: 0, green: 0, blue: 255))
    }

    @Test func groupOpacityAppliesAndAnIsolatedGroupDoesNotDarkenOverlaps() throws {
        func overlapping(isolated: Bool) -> DisplayList {
            DisplayList(
                size: Size2D(width: 30, height: 10),
                commands: [
                    .pushGroup(GroupStyle(opacity: 0.5, isolated: isolated)),
                    .fillPath(.rect(Rect2D(x: 0, y: 0, width: 20, height: 10)), color: Self.black),
                    .fillPath(.rect(Rect2D(x: 10, y: 0, width: 20, height: 10)), color: Self.black),
                    .popGroup,
                ])
        }
        let isolated = try Self.pixels(overlapping(isolated: true))
        let single = Int(isolated.pixel(x: 5, y: 5)?.alpha ?? 0)
        let overlap = Int(isolated.pixel(x: 15, y: 5)?.alpha ?? 0)
        #expect(abs(single - 128) <= 2)
        #expect(abs(overlap - single) <= 2)

        let plain = try Self.pixels(overlapping(isolated: false))
        #expect(Int(plain.pixel(x: 15, y: 5)?.alpha ?? 0) > 180)
    }

    @Test func aShadowFallsDownward() throws {
        let list = DisplayList(
            size: Size2D(width: 40, height: 40),
            commands: [
                .pushGroup(
                    GroupStyle(shadow: Shadow(offset: Point2D(x: 0, y: 6), blur: 0, color: Self.black), isolated: true)),
                .fillPath(.rect(Rect2D(x: 10, y: 10, width: 10, height: 10)), color: Self.red),
                .popGroup,
            ])
        let buffer = try Self.pixels(list)
        #expect(buffer.pixel(x: 15, y: 15) == RGBA8(red: 255, green: 0, blue: 0))
        #expect((buffer.pixel(x: 15, y: 23)?.alpha ?? 0) > 200)
        #expect(buffer.pixel(x: 15, y: 23)?.red == 0)
        #expect(buffer.pixel(x: 15, y: 8)?.alpha == 0)
    }

    @Test func aShadowScalesWithTheDeviceScale() throws {
        let list = DisplayList(
            size: Size2D(width: 40, height: 40),
            commands: [
                .pushGroup(GroupStyle(shadow: Shadow(offset: Point2D(x: 0, y: 6), blur: 0, color: Self.black))),
                .fillPath(.rect(Rect2D(x: 10, y: 10, width: 10, height: 10)), color: Self.red),
                .popGroup,
            ])
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(
            CGContext(
                data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.scaleBy(x: 2, y: 2)
        #expect(DisplayListExecutor.deviceScale(of: context) == 2)
        DisplayListExecutor().execute(list, in: context, contextIsFlipped: false)
        let image = try #require(context.makeImage())
        let buffer = try #require(PixelBufferImages.pixelBuffer(image))
        // Scaled, the shadow covers list y 16…26 (device 32…52); unscaled it would stop at list y 23.
        #expect((buffer.pixel(x: 30, y: 49)?.alpha ?? 0) > 200)
        #expect(buffer.pixel(x: 30, y: 49)?.red == 0)
        #expect(buffer.pixel(x: 30, y: 56)?.alpha == 0)
    }

    @Test func aTextRunSitsOnItsBaselineAndMatchesTheMeasurer() throws {
        let font = FontDescriptor(name: FontDescriptor.systemFontName, size: 30, weight: 0.4)
        let list = DisplayList(
            size: Size2D(width: 200, height: 60),
            commands: [.textRun("Hello", origin: Point2D(x: 10, y: 40), font: font, color: Self.black)])
        let box = try #require(Self.inkBounds(try Self.pixels(list)))
        let measured = CoreTextMeasurer().measure("Hello", font: font)
        #expect(box.3 <= 41)  // no descender: the ink stays above the baseline
        #expect(box.1 < 40 - 15)  // the cap height reaches well above it
        #expect(box.0 >= 9 && box.0 <= 14)
        let inkWidth = Double(box.2 - box.0 + 1)
        #expect(inkWidth <= measured.width + 1)
        #expect(inkWidth >= measured.width * 0.8)
    }

    @Test func aPopWithoutAPushStopsDrawing() throws {
        let list = DisplayList(
            size: Size2D(width: 10, height: 10),
            commands: [.popGroup, .fillPath(.rect(Rect2D(x: 0, y: 0, width: 10, height: 10)), color: Self.red)])
        #expect(Self.inkBounds(try Self.pixels(list)) == nil)
    }

    @Test func renderingAnEmptyListGivesNoImage() {
        #expect(DisplayListExecutor().render(DisplayList(size: .zero, commands: [])) == nil)
    }

    /// A context set up like a flipped `NSView`'s (y down), optionally at a device scale.
    static func flippedContext(width: Int, height: Int, scale: Double) throws -> CGContext {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)
        return context
    }

    @Test(arguments: [1.0, 2.0])
    func aFlippedContextIsDrawnWithoutASecondFlip(scale: Double) throws {
        let image = try Self.redOverBlue()
        let executor = DisplayListExecutor(images: { _ in image })
        let font = FontDescriptor(name: FontDescriptor.systemFontName, size: 20, weight: 0.4)
        let list = DisplayList(
            size: Size2D(width: 100, height: 100),
            commands: [
                .fillPath(.rect(Rect2D(x: 0, y: 0, width: 5, height: 5)), color: Self.blue),
                .image(imageID: "capture", rect: Rect2D(x: 80, y: 0, width: 20, height: 20)),
                .textRun("Hello", origin: Point2D(x: 10, y: 60), font: font, color: Self.black),
                .pushGroup(GroupStyle(shadow: Shadow(offset: Point2D(x: 0, y: 6), blur: 0, color: Self.black))),
                .fillPath(.rect(Rect2D(x: 40, y: 75, width: 10, height: 10)), color: Self.red),
                .popGroup,
            ])
        let side = Int(100 * scale)
        let context = try Self.flippedContext(width: side, height: side, scale: scale)
        let matrixBefore = context.textMatrix
        executor.execute(list, in: context, contextIsFlipped: true)
        #expect(context.textMatrix == matrixBefore)
        let rendered = try #require(context.makeImage())
        let buffer = try #require(PixelBufferImages.pixelBuffer(rendered))
        func at(_ x: Double, _ y: Double) -> RGBA8? { buffer.pixel(x: Int(x * scale), y: Int(y * scale)) }
        #expect(at(1, 1) == RGBA8(red: 0, green: 0, blue: 255))
        #expect(at(1, 98)?.alpha == 0)
        #expect(at(90, 2) == RGBA8(red: 255, green: 0, blue: 0))
        #expect(at(90, 18) == RGBA8(red: 0, green: 0, blue: 255))
        // the text's ink sits above its baseline, near the top half of the band
        var ink = 0
        var below = 0
        for y in 40..<72 {
            for x in 10..<70 where (at(Double(x), Double(y))?.alpha ?? 0) > 128 {
                if y < 60 { ink += 1 } else if y > 61 { below += 1 }
            }
        }
        #expect(ink > 20)
        #expect(below == 0)
        // the shadow falls downward: list y 81…91
        #expect((at(45, 89)?.alpha ?? 0) > 200)
        #expect(at(45, 89)?.red == 0)
        #expect(at(45, 72)?.alpha == 0)
    }

    @Test func aNonRGBColourSpaceFallsBackToSRGBAndBadSizesGiveNothing() throws {
        let list = DisplayList(
            size: Size2D(width: 10.5, height: 10.5),
            commands: [.fillPath(.rect(Rect2D(x: 0, y: 0, width: 2, height: 2)), color: Self.red)])
        let image = try #require(
            DisplayListExecutor().render(list, colorSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)))
        #expect(image.width == 11 && image.height == 11)
        #expect(image.colorSpace?.model == .rgb)
        let buffer = try #require(PixelBufferImages.pixelBuffer(image))
        #expect(buffer.pixel(x: 0, y: 0)?.alpha == 255)
        #expect(DisplayListExecutor().render(DisplayList(size: Size2D(width: .nan, height: 4), commands: [])) == nil)
        #expect(
            DisplayListExecutor().render(DisplayList(size: Size2D(width: .infinity, height: 4), commands: [])) == nil)
    }

    @Test(arguments: [false, true])
    func nestedGroupOpacitiesMultiply(innerIsolated: Bool) throws {
        let list = DisplayList(
            size: Size2D(width: 20, height: 10),
            commands: [
                .pushGroup(GroupStyle(opacity: 0.5)),
                .fillPath(.rect(Rect2D(x: 0, y: 0, width: 10, height: 10)), color: Self.black),
                .pushGroup(GroupStyle(opacity: 0.5, isolated: innerIsolated)),
                .fillPath(.rect(Rect2D(x: 10, y: 0, width: 10, height: 10)), color: Self.black),
                .popGroup,
                .popGroup,
            ])
        let buffer = try Self.pixels(list)
        #expect(abs(Int(buffer.pixel(x: 5, y: 5)?.alpha ?? 0) - 128) <= 2)
        #expect(abs(Int(buffer.pixel(x: 15, y: 5)?.alpha ?? 0) - 64) <= 2)
    }

    @Test func anIsolatedGroupsChildrenStartFromFullOpacityInsideItsLayer() throws {
        let list = DisplayList(
            size: Size2D(width: 10, height: 10),
            commands: [
                .pushGroup(GroupStyle(opacity: 0.5, isolated: true)),
                .pushGroup(GroupStyle(opacity: 0.5)),
                .fillPath(.rect(Rect2D(x: 0, y: 0, width: 10, height: 10)), color: Self.black),
                .popGroup,
                .popGroup,
            ])
        #expect(abs(Int(try Self.pixels(list).pixel(x: 5, y: 5)?.alpha ?? 0) - 64) <= 2)
    }
}
