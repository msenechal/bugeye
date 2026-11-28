import BugeyeCore
import Foundation
import Testing

/// The value types of the Wave 1 ports (contracts §4.1.5).
@Suite struct ContractPortTests {
    @Test func windowIDsWrapTheirRawValueAndRoundTrip() throws {
        let id = WindowID(42)
        #expect(id.rawValue == 42)
        #expect(try JSONDecoder().decode(WindowID.self, from: JSONEncoder().encode(id)) == id)
    }

    @Test func textLineMetricsHoldTheirValues() {
        let metrics = TextLineMetrics(width: 10, ascent: 8, descent: 2)
        #expect(metrics.width == 10 && metrics.ascent == 8 && metrics.descent == 2)
    }
}
