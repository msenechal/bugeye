import BugeyeCore
import MacAdapters
import Testing

@Suite struct AXPointReaderTests {
    @Test func aSecureFieldHasNoTitleAndIsTextEntry() {
        let info = AXPointReader.info(
            role: "AXTextField", subrole: "AXSecureTextField", title: "Password", description: "pw", frame: .zero)
        #expect(info.isSecure)
        #expect(info.title == nil)
        #expect(info.text == nil)
        #expect(info.isTextEntry)
    }

    @Test func titleElseDescriptionAndNeverText() {
        let button = AXPointReader.info(
            role: "AXButton", subrole: nil, title: "Save", description: "ignored",
            frame: Rect2D(x: 1, y: 2, width: 3, height: 4))
        #expect(button.title == "Save")
        #expect(button.text == nil)
        #expect(!button.isTextEntry)
        #expect(button.frame == Rect2D(x: 1, y: 2, width: 3, height: 4))
        let icon = AXPointReader.info(role: "AXButton", subrole: nil, title: "", description: "Close", frame: .zero)
        #expect(icon.title == "Close")
        let field = AXPointReader.info(role: "AXTextArea", subrole: nil, title: nil, description: nil, frame: .zero)
        #expect(field.isTextEntry)
        #expect(field.title == nil)
    }

    @Test func untrustedAnswersNilAndWindowQueriesAreUnsupported() async throws {
        let reader = AXPointReader(isTrusted: { false })
        #expect(try await reader.element(at: Point2D(x: 10, y: 10)) == nil)
        await #expect(throws: AXPointReader.Failure.unsupported) { try await reader.elements(inWindowOf: 1) }
    }

    /// On the runner (Accessibility rarely granted) the real query must return, not hang or crash.
    @Test func aRealQueryReturns() async throws {
        let reader = AXPointReader()
        _ = try await reader.element(at: Point2D(x: 5, y: 5))
    }
}
