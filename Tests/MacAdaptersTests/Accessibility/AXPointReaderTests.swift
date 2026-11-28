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

    /// PR #17 review I1: a text field's title (or description) can be what was typed: never kept.
    @Test func textEntryElementsKeepNoTitle() {
        for (role, subrole) in [
            ("AXTextField", nil), ("AXTextArea", nil), ("AXComboBox", nil), ("AXTextField", "AXSearchField"),
        ] {
            let info = AXPointReader.info(
                role: role, subrole: subrole, title: "hunter2", description: "hunter2", frame: .zero)
            #expect(info.title == nil)
            #expect(info.text == nil)
            #expect(info.isTextEntry)
        }
    }

    @Test func untrustedAnswersNilAndWindowQueriesAreUnsupported() async throws {
        let reader = AXPointReader(isTrusted: { false })
        #expect(try await reader.element(at: Point2D(x: 10, y: 10)) == nil)
        await #expect(throws: AXPointReader.Failure.unsupported) { try await reader.elements(inWindowOf: 1) }
    }

    /// The real calls run (the runner isn't trusted, so they fail fast) and the lookup returns within its deadline.
    @Test func aRealQueryReturnsWithinItsDeadline() async throws {
        let reader = AXPointReader(deadline: 0.25, isTrusted: { true })
        let started = ContinuousClock.now
        _ = try await reader.element(at: Point2D(x: 5, y: 5))
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}
