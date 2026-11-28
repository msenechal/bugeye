import AppKit
import BugeyeCore
import CoreGraphics
import CoreText
import Foundation
import MacAdapters
import Synchronization
import Testing

@Suite struct PasteboardClipboardWriterTests {
    @Test func oneItemHoldsThePNGTheFileURLAndTheText() throws {
        let name = "dev.msenechal.bugeye.test-\(UUID().uuidString)"
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/tmp/Screenshot 1.png")
        try PasteboardClipboardWriter(pasteboardName: name).write(
            ClipboardPayload(png: Data([0x89, 0x50]), fileURL: url, text: "hello"))

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(Set(item.types) == [.png, .fileURL, .string])
        #expect(item.data(forType: .png) == Data([0x89, 0x50]))
        #expect(item.string(forType: .fileURL) == url.absoluteString)
        #expect(item.string(forType: .string) == "hello")
    }

    @Test func onlyTheSetRepresentationsAreWritten() throws {
        let name = "dev.msenechal.bugeye.test-\(UUID().uuidString)"
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        defer { pasteboard.releaseGlobally() }
        try PasteboardClipboardWriter(pasteboardName: name).write(ClipboardPayload(text: "only text"))
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.pasteboardItems?.first?.types == [.string])
    }
}

@Suite struct UserNotificationNotifierTests {
    final class Center: NotificationCenterClient {
        let added = Mutex<[String]>([])
        let answer = Mutex<CheckedContinuation<Bool, Never>?>(nil)

        func requestAuthorization() async -> Bool {
            await withCheckedContinuation { continuation in answer.withLock { $0 = continuation } }
        }

        func add(title: String, body: String) {
            added.withLock { $0.append("\(title)|\(body)") }
        }

        func waitForRequest() async {
            while answer.withLock({ $0 == nil }) { await Task.yield() }
        }

        func grant() {
            answer.withLock { $0?.resume(returning: true) }
        }
    }

    @Test func withNoBundleItOnlyLogs() {
        let lines = Mutex<[String]>([])
        let notifier = UserNotificationNotifier(client: nil, log: { line in lines.withLock { $0.append(line) } })
        notifier.post(title: "Couldn't save to folder", body: "Body")
        #expect(lines.withLock { $0 } == ["Couldn't save to folder: Body"])
    }

    @Test func postsBeforeTheAnswerAreHeldThenDeliveredInOrder() async {
        let center = Center()
        let notifier = UserNotificationNotifier(client: center)
        notifier.post(title: "1", body: "a")
        let authorization = Task { await notifier.requestAuthorization() }
        await center.waitForRequest()
        notifier.post(title: "2", body: "b")
        #expect(center.added.withLock { $0 } == [])
        center.grant()
        await authorization.value
        #expect(center.added.withLock { $0 } == ["1|a", "2|b"])
        notifier.post(title: "3", body: "c")
        #expect(center.added.withLock { $0 } == ["1|a", "2|b", "3|c"])
    }
}

@Suite struct SystemScreenCapturePermissionTests {
    @Test func preflightAnswersWithoutPrompting() {
        _ = SystemScreenCapturePermission().preflight()
    }
}

@Suite struct CoreTextMeasurerTests {
    let measurer = CoreTextMeasurer()

    @Test func widthIsPositiveAndBoldIsWider() {
        let regular = measurer.measure("Hello, Bugeye", font: FontDescriptor(name: "system", size: 13))
        let bold = measurer.measure("Hello, Bugeye", font: FontDescriptor(name: "system", size: 13, weight: 0.4))
        #expect(regular.width > 0)
        #expect(bold.width > regular.width)
        #expect(measurer.measure("", font: FontDescriptor(name: "system", size: 13)).width == 0)
    }

    @Test func ascentAndDescentMatchTheFont() {
        let descriptor = FontDescriptor(name: "system", size: 20, weight: 0.3)
        let font = CoreTextFonts.font(for: descriptor)
        let metrics = measurer.measure("Ag", font: descriptor)
        #expect(abs(metrics.ascent - Double(CTFontGetAscent(font))) < 0.001)
        #expect(abs(metrics.descent - Double(CTFontGetDescent(font))) < 0.001)
        #expect(CTFontGetSize(font) == 20)
    }

    @Test func unknownNamesFallBackToTheSystemFont() {
        let unknown = CoreTextFonts.font(for: FontDescriptor(name: "No Such Font 123", size: 12))
        let system = CoreTextFonts.font(for: FontDescriptor(name: "system", size: 12))
        #expect(CTFontCopyPostScriptName(unknown) as String == CTFontCopyPostScriptName(system) as String)
        let helvetica = CoreTextFonts.font(for: FontDescriptor(name: "Helvetica", size: 12))
        #expect((CTFontCopyFamilyName(helvetica) as String) == "Helvetica")
    }

    @Test func sixtyFourCharactersMeasureQuickly() {
        let line = String(repeating: "W", count: 64)
        let font = FontDescriptor(name: "system", size: 14)
        _ = measurer.measure(line, font: font)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<100 { _ = measurer.measure(line, font: font) }
        }
        // K38's budget is 1 ms on the user's Mac; a hosted runner gets 5 ms on average.
        #expect(elapsed / 100 < .milliseconds(5))
    }
}

@Suite struct PixelBufferImagesTests {
    /// A 3 × 2 image with one semi-transparent premultiplied pixel and row padding.
    func sample() throws -> PixelBuffer {
        let rows: [[UInt8]] = [
            [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 9, 9, 9, 9],
            [64, 32, 0, 128, 10, 20, 30, 255, 200, 100, 50, 255, 9, 9, 9, 9],
        ]
        return try PixelBuffer(width: 3, height: 2, bytesPerRow: 16, bytes: rows.flatMap { $0 })
    }

    func pixels(_ buffer: PixelBuffer) -> [RGBA8?] {
        (0..<buffer.height).flatMap { y in (0..<buffer.width).map { x in buffer.pixel(x: x, y: y) } }
    }

    @Test func aRoundTripInSRGBIsByteForByte() throws {
        let buffer = try sample()
        let image = try #require(PixelBufferImages.cgImage(buffer))
        #expect(image.width == 3 && image.height == 2)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        let back = try #require(PixelBufferImages.pixelBuffer(image))
        #expect(pixels(back) == pixels(buffer))
    }

    @Test func aRectIsCutFromTheTopLeft() throws {
        let image = try #require(PixelBufferImages.cgImage(try sample()))
        let cut = try #require(PixelBufferImages.pixelBuffer(image, rect: Rect2D(x: 1, y: 1, width: 2, height: 1)))
        #expect(cut.width == 2 && cut.height == 1)
        #expect(pixels(cut) == [RGBA8(red: 10, green: 20, blue: 30), RGBA8(red: 200, green: 100, blue: 50)])
    }

    @Test func aP3ImageIsKeptInP3WhenAsked() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let buffer = try sample()
        let image = try #require(PixelBufferImages.cgImage(buffer, colorSpace: p3))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        let back = try #require(PixelBufferImages.pixelBuffer(image, colorSpace: image.colorSpace))
        #expect(pixels(back) == pixels(buffer))
    }

    @Test func previewsAreAtMost480WideAndNeverUpscaled() throws {
        let wide = try #require(
            PixelBufferImages.cgImage(
                try PixelBuffer(width: 2000, height: 1000, fill: RGBA8(red: 1, green: 2, blue: 3))))
        let preview = try #require(PixelBufferImages.preview(wide))
        #expect(preview.width == 480 && preview.height == 240)
        let small = try #require(
            PixelBufferImages.cgImage(try PixelBuffer(width: 300, height: 100, fill: RGBA8(red: 1, green: 2, blue: 3))))
        let same = try #require(PixelBufferImages.preview(small))
        #expect(same.width == 300 && same.height == 100)
        #expect(same.pixel(x: 0, y: 0) == RGBA8(red: 1, green: 2, blue: 3))
    }
}
