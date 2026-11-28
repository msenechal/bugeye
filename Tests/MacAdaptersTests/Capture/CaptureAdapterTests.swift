import BugeyeCore
import CoreGraphics
import Foundation
import ImageIO
import MacAdapters
import ScreenCaptureKit
import Testing

// Real ScreenCaptureKit freezes and window captures need Screen Recording, which hosted runners can't grant: they run
// in the Mac batch (Capture §9.4.1–9.4.2). These tests cover everything around them.

@Suite struct ScreenCaptureKitSourceTests {
    @Test func userDeclinedMapsToPermissionDenied() {
        let declined = NSError(domain: SCStreamError.errorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        #expect(ScreenCaptureKitSource.map(declined) == .permissionDenied)
    }

    @Test func portErrorsPassThroughAndOthersKeepTheirDescription() {
        #expect(ScreenCaptureKitSource.map(ScreenSourceError.windowNotFound) == .windowNotFound)
        let other = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "The stream stopped."])
        #expect(ScreenCaptureKitSource.map(other) == .failed("The stream stopped."))
    }
}

@Suite struct ScreenCaptureKitFreezePlanTests {
    @Test func everyKnownDisplayInScreenCaptureKitsOrder() throws {
        #expect(
            try ScreenCaptureKitSource.targets(
                wanted: nil, available: [DisplayID(2), DisplayID(1)], screens: [DisplayID(1), DisplayID(2)])
                == [DisplayID(2), DisplayID(1)])
    }

    @Test func aDisplayNSScreenDoesNotKnowYetIsSkippedNotFatal() throws {
        #expect(
            try ScreenCaptureKitSource.targets(
                wanted: nil, available: [DisplayID(1), DisplayID(3)], screens: [DisplayID(1)])
                == [DisplayID(1)])
        #expect(throws: ScreenSourceError.displayNotFound) {
            try ScreenCaptureKitSource.targets(wanted: nil, available: [DisplayID(3)], screens: [DisplayID(1)])
        }
    }

    @Test func anAskedForDisplayMustExist() throws {
        #expect(
            try ScreenCaptureKitSource.targets(
                wanted: [DisplayID(1)], available: [DisplayID(2), DisplayID(1)], screens: [DisplayID(1), DisplayID(2)])
                == [DisplayID(1)])
        #expect(throws: ScreenSourceError.displayNotFound) {
            try ScreenCaptureKitSource.targets(
                wanted: [DisplayID(9)], available: [DisplayID(1)], screens: [DisplayID(1)])
        }
    }

    @Test func pixelSizeIsPointsTimesScale() {
        #expect(ScreenCaptureKitSource.pixelSize(pointWidth: 1512, pointHeight: 982, scale: 2) == (3024, 1964))
        #expect(ScreenCaptureKitSource.pixelSize(pointWidth: 1920, pointHeight: 1080, scale: 1) == (1920, 1080))
    }
}

@Suite struct CGWindowListReaderTests {
    @Test func parsesNumberOwnerBoundsLayerAndAlphaInOrder() {
        let list: [[String: Any]] = [
            [
                kCGWindowNumber as String: NSNumber(value: 42), kCGWindowOwnerPID as String: NSNumber(value: 7),
                kCGWindowBounds as String: ["X": 10, "Y": 20, "Width": 300, "Height": 200] as NSDictionary,
                kCGWindowLayer as String: NSNumber(value: 0), kCGWindowAlpha as String: NSNumber(value: 0.5),
            ],
            [kCGWindowNumber as String: NSNumber(value: 43)],  // no owner or bounds: skipped
            [
                kCGWindowNumber as String: NSNumber(value: 44), kCGWindowOwnerPID as String: NSNumber(value: 8),
                kCGWindowBounds as String: ["X": -5, "Y": -6, "Width": 1, "Height": 2] as NSDictionary,
            ],
        ]
        #expect(
            CGWindowListReader.parse(list) == [
                WindowInfo(
                    id: WindowID(42), ownerPID: 7, bounds: Rect2D(x: 10, y: 20, width: 300, height: 200), layer: 0,
                    alpha: 0.5),
                WindowInfo(
                    id: WindowID(44), ownerPID: 8, bounds: Rect2D(x: -5, y: -6, width: 1, height: 2), layer: 0, alpha: 1
                ),
            ])
    }
}

/// A 4 × 4 image whose rows are red, green, blue and white, from the top, tagged with `space`.
func stripes(_ space: CGColorSpace) throws -> CGImage {
    let rows: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]]
    let bytes = rows.flatMap { row in (0..<4).flatMap { _ in row } }
    let buffer = try PixelBuffer(width: 4, height: 4, bytesPerRow: 16, bytes: bytes)
    return try #require(PixelBufferImages.cgImage(buffer, colorSpace: space))
}

@Suite struct ImageIOPipelineTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    @Test func cropTakesPixelsFromTheTopLeft() throws {
        let image = CapturedImage(cgImage: try stripes(sRGB))
        let crop = try #require(ImageIOPipeline().crop(image, to: Rect2D(x: 1, y: 1, width: 2, height: 1)))
        #expect(crop.pixelWidth == 2 && crop.pixelHeight == 1)
        let pixels = try #require(ImageIOPipeline().pixelBuffer(crop))
        #expect(pixels.pixel(x: 0, y: 0) == RGBA8(red: 0, green: 255, blue: 0))
    }

    @Test func cropOutsideTheImageIsNil() throws {
        #expect(
            ImageIOPipeline().crop(
                CapturedImage(cgImage: try stripes(sRGB)), to: Rect2D(x: 9, y: 9, width: 2, height: 2)) == nil)
    }

    @Test func downscaleHalvesTheSizeAndKeepsTheColourSpace() throws {
        let small = try #require(ImageIOPipeline().downscale(CapturedImage(cgImage: try stripes(p3)), by: 0.5))
        #expect(small.pixelWidth == 2 && small.pixelHeight == 2)
        #expect(small.cgImage?.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func downscaleKeepsTransparency() throws {
        // Half-transparent grey, premultiplied: alpha 128.
        let buffer = try PixelBuffer(width: 4, height: 4, fill: RGBA8(red: 128, green: 128, blue: 128, alpha: 128))
        let image = CapturedImage(cgImage: try #require(PixelBufferImages.cgImage(buffer)))
        let small = try #require(ImageIOPipeline().downscale(image, by: 0.5))
        let alpha = try #require(ImageIOPipeline().pixelBuffer(small)?.pixel(x: 0, y: 0)?.alpha)
        #expect(abs(Int(alpha) - 128) <= 2)
    }

    @Test func pngRoundTripsWithTheColourSpaceKept() throws {
        let data = try #require(ImageIOPipeline().pngData(CapturedImage(cgImage: try stripes(p3))))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 4 && decoded.height == 4)
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func previewIsAtMost480Wide() throws {
        let buffer = try PixelBuffer(width: 2000, height: 10, fill: RGBA8(red: 1, green: 2, blue: 3))
        let image = CapturedImage(cgImage: try #require(PixelBufferImages.cgImage(buffer)))
        #expect(ImageIOPipeline().preview(image)?.width == 480)
    }

    @Test func aFakesPixelBufferStorageWorksToo() throws {
        let buffer = try PixelBuffer(width: 3, height: 3, fill: RGBA8(red: 9, green: 9, blue: 9))
        #expect(ImageIOPipeline().pngData(CapturedImage(pixelBuffer: buffer)) != nil)
    }
}

@MainActor @Suite struct CarbonHotkeyRegistrarRegistrationTests {
    // An unlikely combo, so the test never collides with a real shortcut on the runner.
    let key = GlobalKey("9", command: true, option: true, control: true, shift: true)

    @Test func reRegisteringAnIdReleasesItsOldKeyFirst() {
        let registrar = CarbonHotkeyRegistrar()
        #expect(registrar.installStatus == 0)
        #expect(registrar.register("test.a", key: key) {})
        // Same id, same key: the old registration is released first, so this succeeds.
        #expect(registrar.register("test.a", key: key) {})
        // Another id can't take a key this process already holds (Carbon refuses an in-process duplicate)…
        #expect(!registrar.register("test.b", key: key) {})
        // …until the first id lets it go.
        registrar.unregister("test.a")
        #expect(registrar.register("test.b", key: key) {})
        registrar.unregister("test.b")
        registrar.unregister("test.never")
    }

    @Test func anUnknownKeyIsRefused() {
        #expect(!CarbonHotkeyRegistrar().register("test.c", key: GlobalKey("?", command: true)) {})
    }
}

@Suite struct CarbonHotkeyRegistrarTests {
    @Test func theSignatureIsBgEy() {
        let s = CarbonHotkeyRegistrar.signature
        let text = String(
            bytes: [UInt8(s >> 24 & 0xFF), UInt8(s >> 16 & 0xFF), UInt8(s >> 8 & 0xFF), UInt8(s & 0xFF)],
            encoding: .ascii)
        #expect(text == "BgEy")
    }

    @Test func keysMapToANSIKeyCodes() {
        #expect(CarbonHotkeyRegistrar.keyCode(for: "3") == 20)
        #expect(CarbonHotkeyRegistrar.keyCode(for: "4") == 21)
        #expect(CarbonHotkeyRegistrar.keyCode(for: "a") == 0)
        #expect(CarbonHotkeyRegistrar.keyCode(for: "\u{1B}") == 53)
        #expect(CarbonHotkeyRegistrar.keyCode(for: "?") == nil)
    }

    @Test func modifiersMapToCarbonBits() {
        #expect(CarbonHotkeyRegistrar.carbonModifiers(GlobalKey("3", command: true, shift: true)) == 0x0100 | 0x0200)
        #expect(CarbonHotkeyRegistrar.carbonModifiers(GlobalKey("3", option: true, control: true)) == 0x0800 | 0x1000)
        #expect(CarbonHotkeyRegistrar.carbonModifiers(.escape) == 0)
    }
}

@Suite struct SystemShortcutDefaultsReaderTests {
    @Test func parsesEnabledAndParameters() {
        let parsed = SystemShortcutDefaultsReader.parse([
            "28": ["enabled": NSNumber(value: 0), "value": ["parameters": [51, 20, 1_179_648], "type": "standard"]],
            "30": ["enabled": NSNumber(value: true)],
            "junk": ["enabled": 1],
        ])
        #expect(
            parsed == [
                28: SymbolicHotkey(enabled: false, parameters: [51, 20, 1_179_648]),
                30: SymbolicHotkey(enabled: true, parameters: []),
            ])
    }

    @Test func theModelIsNotEmpty() {
        #expect(!SystemShortcutDefaultsReader().hardwareModel().isEmpty)
    }
}
