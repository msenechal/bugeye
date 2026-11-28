import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import MacAdapters
import Testing
import TextCore

@testable import BugeyeApp

@MainActor @Suite struct TextWiringTests {
    @Test func ocrHasNoModule() {
        #expect(TextWiring.modules.isEmpty)
    }

    @Test func installReadsANewScreenshotFromTheBus() async throws {
        let folder = try TempDirectory("text-wiring")
        defer { folder.remove() }
        let context = AppContext.testing(home: folder.url.path)
        let services = TextWiring.install(context)
        let drawn = try PipelineText.draw([("Save", 40, 40)], width: 300, height: 120)
        let url = folder.file("Screenshot.png")
        let image = try #require(PixelBufferImages.cgImage(drawn.image))
        try writeCGImage(image, to: url)
        let item = CaptureItem(
            id: CaptureID(), fileURL: url, isSaved: false, kind: .screenshot, createdAt: Date(), pixelsPerPoint: 2)
        context.captureEvents.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        let result = try await services.maps.map(for: item)
        #expect(result.map.lines.map(\.text) == ["Save"])
        #expect(await services.maps.isCurrent(result.key))
    }
}
