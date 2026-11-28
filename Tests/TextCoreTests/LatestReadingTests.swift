import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@testable import TextCore

@Suite struct LatestReadingTests {
    func image(_ width: Int) throws -> PixelBuffer {
        try PixelBuffer(width: width, height: 10, fill: RGBA8(red: 255, green: 255, blue: 255))
    }

    @Test func aNewerCallMakesTheOlderReturnNilAndCancelsIt() async throws {
        let gate = FakeGate()
        let text = FakeTextReader(
            steps: [.gate(gate, [ocr("old", rect(0, 0, 5, 5))])], fallback: .lines([ocr("new", rect(0, 0, 5, 5))]))
        let latest = LatestReading(reader: TextMapReader(reader: text, files: FakeImageFileReader()))
        let first = try image(1)
        let older = Task { await latest.read(first, pixelsPerPoint: 2) }
        #expect(await eventually { gate.waiting == 1 })
        let newer = await latest.read(try image(2), pixelsPerPoint: 2)
        let olderDone = Completion(Task { await older.value })
        #expect(await eventually { olderDone.isDone })  // M5: a regression fails here instead of hanging
        #expect(await older.value == nil)
        #expect(gate.waiting == 0)  // cancelled, not left waiting
        #expect(newer?.lines.map(\.text) == ["new"])
    }

    @Test func anOlderReadThatFinishesAfterANewerOneStartedReturnsNil() async throws {
        let gate = FakeGate()
        let newerGate = FakeGate()
        let text = FakeTextReader(steps: [.gate(gate, []), .gate(newerGate, [])])
        let latest = LatestReading(reader: TextMapReader(reader: text, files: FakeImageFileReader()))
        let first = try image(1)
        let second = try image(2)
        let older = Task { await latest.read(first, pixelsPerPoint: 2) }
        #expect(await eventually { gate.waiting == 1 })
        let newer = Task { await latest.read(second, pixelsPerPoint: 2) }
        #expect(await eventually { newerGate.waiting == 1 })
        #expect(await older.value == nil)
        newerGate.open()
        #expect(await newer.value != nil)
    }

    @Test func errorsGiveNil() async throws {
        let text = FakeTextReader(steps: [.failure("broke")])
        let latest = LatestReading(reader: TextMapReader(reader: text, files: FakeImageFileReader()))
        #expect(await latest.read(try image(1), pixelsPerPoint: 2) == nil)
    }

    @Test func nothingIsCached() async throws {
        let text = FakeTextReader(lines: [ocr("x", rect(0, 0, 5, 5))])
        let latest = LatestReading(reader: TextMapReader(reader: text, files: FakeImageFileReader()))
        let one = try image(3)
        _ = await latest.read(one, pixelsPerPoint: 2)
        _ = await latest.read(one, pixelsPerPoint: 2)
        #expect(text.calls.count == 2)
    }

    @Test func cancellingTheCallerCancelsItsRead() async throws {
        // M4.
        let gate = FakeGate()
        let text = FakeTextReader(steps: [.gate(gate, [])])
        let latest = LatestReading(reader: TextMapReader(reader: text, files: FakeImageFileReader()))
        let one = try image(1)
        let caller = Task { await latest.read(one, pixelsPerPoint: 2) }
        #expect(await eventually { gate.waiting == 1 })
        caller.cancel()
        let done = Completion(Task { await caller.value })
        #expect(await eventually { done.isDone })
        #expect(await caller.value == nil)
        #expect(gate.waiting == 0)
    }
}
