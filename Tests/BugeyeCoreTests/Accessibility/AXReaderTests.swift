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
}
