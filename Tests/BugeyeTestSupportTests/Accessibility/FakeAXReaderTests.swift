import BugeyeCore
import BugeyeTestSupport
import Testing

@Suite struct FakeAXReaderTests {
    private let button = AXElementInfo(
        role: "AXButton", title: "Save", text: nil, frame: Rect2D(x: 0, y: 0, width: 10, height: 10),
        isTextEntry: false)

    @Test func answersTheLastElementContainingThePoint() async throws {
        let reader = FakeAXReader(elementsByProcess: [1: [button]])
        #expect(try await reader.element(at: Point2D(x: 5, y: 5)) == button)
        #expect(try await reader.element(at: Point2D(x: 50, y: 5)) == nil)
    }

    @Test func aGateHoldsTheLookupUntilOpened() async throws {
        let gate = FakeAXReader.Gate()
        let reader = FakeAXReader(elementsByProcess: [1: [button]], gate: gate)
        let lookup = Task { try await reader.element(at: Point2D(x: 5, y: 5)) }
        await gate.waitUntilEntered(count: 1)
        #expect(gate.entered == 1)
        gate.open()
        #expect(try await lookup.value == button)
    }

    @Test func aDelayIsCancellable() async throws {
        let reader = FakeAXReader(elementsByProcess: [1: [button]], delay: .seconds(60))
        let lookup = Task { try await reader.element(at: Point2D(x: 5, y: 5)) }
        lookup.cancel()
        await #expect(throws: CancellationError.self) { try await lookup.value }
    }
}
