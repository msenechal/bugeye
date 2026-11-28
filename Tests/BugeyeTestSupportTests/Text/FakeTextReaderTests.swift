import BugeyeCore
import BugeyeTestSupport
import Testing

@Suite struct FakeTextReaderTests {
    let image = try! PixelBuffer(width: 3, height: 2, fill: RGBA8(red: 0, green: 0, blue: 0))
    let tall = try! PixelBuffer(width: 1, height: 5, fill: RGBA8(red: 0, green: 0, blue: 0))

    func line(_ text: String) -> OCRLine {
        OCRLine(text: text, bounds: Rect2D(x: 0, y: 0, width: 1, height: 1), confidence: 1)
    }

    @Test func stepsAnswerInCallOrderThenTheFallback() async throws {
        let reader = FakeTextReader(steps: [.lines([line("a")]), .lines([line("b")])], fallback: .lines([line("z")]))
        #expect(try await reader.recognizeText(in: image) == [line("a")])
        #expect(try await reader.recognizeText(in: image) == [line("b")])
        #expect(try await reader.recognizeText(in: image) == [line("z")])
        #expect(try await reader.recognizeText(in: image) == [line("z")])
    }

    @Test func theDefaultFallbackIsNoLines() async throws {
        #expect(try await FakeTextReader().recognizeText(in: image) == [])
    }

    @Test func aFailureThrowsAFakeFailureWithItsMessage() async {
        let reader = FakeTextReader(steps: [.failure("vision broke")])
        await #expect(throws: FakeFailure("vision broke")) { try await reader.recognizeText(in: image) }
    }

    @Test func aHangThrowsCancellationWhenItsTaskIsCancelled() async {
        let reader = FakeTextReader(steps: [.hang])
        let image = self.image
        let task = Task { try await reader.recognizeText(in: image) }
        while reader.calls.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func aGateAnswersOnceOpened() async throws {
        let gate = FakeGate()
        let reader = FakeTextReader(steps: [.gate(gate, [line("late")])])
        let image = self.image
        let task = Task { try await reader.recognizeText(in: image) }
        while gate.waiting == 0 { await Task.yield() }
        gate.open()
        #expect(try await task.value == [line("late")])
    }

    @Test func aGateOpenedBeforeTheCallDoesNotWait() async throws {
        let gate = FakeGate()
        gate.open()
        let reader = FakeTextReader(steps: [.gate(gate, [line("now")])])
        #expect(try await reader.recognizeText(in: image) == [line("now")])
    }

    @Test func aGateThrowsCancellationIfCancelledFirst() async {
        let gate = FakeGate()
        let reader = FakeTextReader(steps: [.gate(gate, [])])
        let image = self.image
        let task = Task { try await reader.recognizeText(in: image) }
        while gate.waiting == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.waiting == 0)
    }

    @Test func callsRecordEachImageSize() async throws {
        let reader = FakeTextReader()
        _ = try await reader.recognizeText(in: image)
        _ = try await reader.recognizeText(in: tall)
        #expect(reader.calls.map(\.width) == [3, 1])
        #expect(reader.calls.map(\.height) == [2, 5])
    }

    @Test func theLinesInitialiserAnswersEveryCall() async throws {
        let reader = FakeTextReader(lines: [line("same")])
        #expect(try await reader.recognizeText(in: image) == [line("same")])
        #expect(try await reader.recognizeText(in: image) == [line("same")])
    }
}
