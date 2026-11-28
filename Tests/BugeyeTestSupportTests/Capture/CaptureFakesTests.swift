import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

private let main = DisplayInfo(id: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 4, height: 2), scale: 2)
private let side = DisplayInfo(id: DisplayID(2), frame: Rect2D(x: 4, y: 0, width: 2, height: 2), scale: 1)

@Suite struct FakeScreenSourceTests {
    @Test func freezeReturnsTheAskedDisplaysInSourceOrderAndCountsOneFetch() async throws {
        let source = FakeScreenSource(displays: [main, side])
        let all = try await source.freeze(displays: nil)
        #expect(all.map(\.display.id) == [DisplayID(1), DisplayID(2)])
        #expect(all[0].image.pixelWidth == 8 && all[0].image.pixelHeight == 4)
        #expect(all[1].image.pixelWidth == 2)
        let one = try await source.freeze(displays: [DisplayID(2)])
        #expect(one.map(\.display.id) == [DisplayID(2)])
        #expect(source.freezeCount == 2)
    }

    @Test func freezeOfAMissingDisplayThrowsDisplayNotFound() async {
        let source = FakeScreenSource(displays: [main])
        await #expect(throws: ScreenSourceError.displayNotFound) {
            try await source.freeze(displays: [DisplayID(9)])
        }
    }

    @Test func scriptedFailuresAreThrownOnce() async throws {
        let source = FakeScreenSource(displays: [main])
        source.failNextFreeze(.permissionDenied)
        await #expect(throws: ScreenSourceError.permissionDenied) { try await source.freeze(displays: nil) }
        _ = try await source.freeze(displays: nil)
    }

    @Test func captureWindowAnswersTheScriptedImagesInOrderAndRecordsSizes() async throws {
        let source = FakeScreenSource(displays: [main])
        let image = try PixelBuffer(width: 3, height: 2, fill: RGBA8(red: 1, green: 2, blue: 3))
        source.windowImages = [WindowID(7): [image]]
        let captured = try await source.captureWindow(WindowID(7), pixelSize: Size2D(width: 3, height: 2))
        #expect(captured.pixelWidth == 3)
        #expect(captured.storage as? PixelBuffer == image)
        #expect(
            source.windowCaptures == [
                FakeScreenSource.WindowCapture(id: WindowID(7), pixelSize: Size2D(width: 3, height: 2))
            ])
        await #expect(throws: ScreenSourceError.windowNotFound) {
            try await source.captureWindow(WindowID(8), pixelSize: Size2D(width: 1, height: 1))
        }
    }
}

@Suite struct FakeScreenSourceGateTests {
    @Test func heldCallsWaitUntilReleased() async throws {
        let source = FakeScreenSource(displays: [main])
        source.hold()
        let task = Task { try await source.freeze(displays: nil) }
        while source.waitingCount < 1 { await Task.yield() }
        #expect(source.freezeCount == 0)
        source.release()
        #expect(try await task.value.count == 1)
        #expect(source.freezeCount == 1)
        // Released: later calls don't wait.
        _ = try await source.freeze(displays: nil)
    }

    @Test func heldWindowCapturesWaitToo() async throws {
        let source = FakeScreenSource(displays: [main])
        source.windowImages = [
            WindowID(1): [try PixelBuffer(width: 1, height: 1, fill: RGBA8(red: 0, green: 0, blue: 0))]
        ]
        source.hold()
        let task = Task { try await source.captureWindow(WindowID(1), pixelSize: Size2D(width: 1, height: 1)) }
        while source.waitingCount < 1 { await Task.yield() }
        #expect(source.windowCaptures.isEmpty)
        source.release()
        #expect(try await task.value.pixelWidth == 1)
    }
}

@Suite struct FakeWindowListReaderTests {
    @Test func answersItsWindows() async {
        let window = WindowInfo(
            id: WindowID(3), ownerPID: 42, bounds: Rect2D(x: 1, y: 2, width: 3, height: 4), layer: 0, alpha: 1)
        let reader = FakeWindowListReader(windows: [window])
        #expect(await reader.windows() == [window])
        #expect(reader.readCount == 1)
    }
}

@Suite struct FakeImagePipelineTests {
    let image = CapturedImage(
        pixelBuffer: try! PixelBuffer(width: 4, height: 2, bytesPerRow: 16, bytes: Array(0..<32).map(UInt8.init)))

    @Test func cropCopiesThePixelsOfTheRect() throws {
        let pipeline = FakeImagePipeline()
        let crop = try #require(pipeline.crop(image, to: Rect2D(x: 1, y: 1, width: 2, height: 1)))
        let buffer = try #require(crop.storage as? PixelBuffer)
        #expect(buffer.width == 2 && buffer.height == 1)
        #expect(buffer.bytes == Array(20..<28).map(UInt8.init))
    }

    @Test func cropOutsideTheImageIsNil() {
        #expect(FakeImagePipeline().crop(image, to: Rect2D(x: 4, y: 0, width: 1, height: 1)) == nil)
    }

    @Test func downscaleRecordsTheFactorAndScalesTheSize() throws {
        let pipeline = FakeImagePipeline()
        let small = try #require(pipeline.downscale(image, by: 0.5))
        #expect(small.pixelWidth == 2 && small.pixelHeight == 1)
        #expect(pipeline.downscaleFactors == [0.5])
    }

    @Test func pngIsDeterministicAndCanFail() {
        let pipeline = FakeImagePipeline()
        let data = pipeline.pngData(image)
        #expect(data == FakeImagePipeline.png(width: 4, height: 2))
        pipeline.failEncoding = true
        #expect(pipeline.pngData(image) == nil)
    }

    @Test func pixelBufferAndPreviewReadTheStorage() throws {
        let pipeline = FakeImagePipeline()
        #expect(pipeline.pixelBuffer(image) == image.storage as? PixelBuffer)
        #expect(pipeline.preview(image)?.width == 4)
    }
}

@Suite @MainActor struct FakeHotkeyRegistrarTests {
    @Test func registersPressesAndRefusesTakenKeys() {
        let registrar = FakeHotkeyRegistrar()
        let key = GlobalKey("3", command: true, shift: true)
        registrar.taken = [GlobalKey("4", command: true, shift: true)]
        var presses = 0
        #expect(registrar.register("a", key: key) { presses += 1 })
        #expect(!registrar.register("b", key: GlobalKey("4", command: true, shift: true)) {})
        #expect(registrar.registered == ["a": key])
        #expect(registrar.press("a"))
        #expect(!registrar.press("b"))
        #expect(presses == 1)
        registrar.unregister("a")
        #expect(registrar.registered.isEmpty)
        #expect(!registrar.press("a"))
    }

    @Test func reRegisteringAnIdReplacesItsKey() {
        let registrar = FakeHotkeyRegistrar()
        _ = registrar.register("a", key: .escape) {}
        _ = registrar.register("a", key: GlobalKey("1", command: true)) {}
        #expect(registrar.registered == ["a": GlobalKey("1", command: true)])
    }
}

@Suite struct FakeSystemShortcutReaderTests {
    @Test func answersItsValues() {
        let reader = FakeSystemShortcutReader(
            hotkeys: [28: SymbolicHotkey(enabled: false, parameters: [51, 20, 1_179_648])], model: "Mac15,3")
        #expect(reader.symbolicHotkeys()?[28]?.enabled == false)
        #expect(reader.hardwareModel() == "Mac15,3")
    }
}
