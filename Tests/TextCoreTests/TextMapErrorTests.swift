import BugeyeCore
import Foundation
import Testing

@testable import TextCore

@Suite struct TextMapErrorTests {
    @Test func descriptionsNeverNameTheFile() {
        let id = CaptureID()
        let url = URL(fileURLWithPath: "/Users/me/Desktop/Secret plan.png")
        #expect(TextMapError.timedOut(strip: 2).description == "timed out on strip 2")
        #expect(TextMapError.unreadable(url).description == "unreadable")
        #expect(TextMapError.recognitionFailed("boom").description == "recognition failed: boom")
        #expect(TextMapError.captureGone(id).description == "capture gone")
        #expect(TextMapError.changedWhileReading(id).description == "changed while reading")
        #expect(!String(describing: TextMapError.unreadable(url)).contains("Secret"))
    }
}
