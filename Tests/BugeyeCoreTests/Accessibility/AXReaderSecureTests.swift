import BugeyeCore
import Testing

@Suite struct AXReaderSecureTests {
    /// M4: an adapter that forgets `isSecure` on a secure text field still withholds it.
    @Test func aSecureTextFieldSubroleIsSecure() {
        let field = AXElementInfo(
            role: "AXTextField", subrole: "AXSecureTextField", title: "pw", text: "pw", frame: .zero, isTextEntry: true)
        #expect(field.isSecure)
        #expect(field.title == nil)
    }
}
