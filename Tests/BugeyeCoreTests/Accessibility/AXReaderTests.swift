import BugeyeCore
import Testing

@Suite struct AXReaderTests {
    @Test func textEntryElementsNeverCarryText() {
        let field = AXElementInfo(
            role: "AXTextField", title: "Password", text: "hunter2", frame: .zero, isTextEntry: true)
        #expect(field.text == nil)
        let label = AXElementInfo(role: "AXStaticText", title: nil, text: "Save", frame: .zero, isTextEntry: false)
        #expect(label.text == "Save")
    }

    @Test func secureElementsCarryNoTitleAndNoText() {
        let secure = AXElementInfo(
            role: "AXTextField", subrole: "AXSecureTextField", title: "hunter2", text: "hunter2", frame: .zero,
            isTextEntry: false, isSecure: true)
        #expect(secure.title == nil)
        #expect(secure.text == nil)
        #expect(secure.subrole == "AXSecureTextField")
        #expect(secure.isSecure)
    }

    @Test func oldCallSitesDefaultToNoSubroleAndNotSecure() {
        let button = AXElementInfo(role: "AXButton", title: "Save", text: nil, frame: .zero, isTextEntry: false)
        #expect(button.subrole == nil)
        #expect(!button.isSecure)
        #expect(button.title == "Save")
    }
}
