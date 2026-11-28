import BugeyeCore
import BugeyeTestSupport
import Foundation
import Synchronization
import Testing

@testable import TextCore

@Suite struct TextMapReaderTests {
    func blank(_ width: Int, _ height: Int) throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, fill: RGBA8(red: 255, green: 255, blue: 255))
    }

    func reader(
        _ text: FakeTextReader, files: FakeImageFileReader = FakeImageFileReader(), clock: ManualClock = ManualClock()
    ) -> TextMapReader {
        TextMapReader(reader: text, files: files, clock: clock)
    }

    @Test func aOneXScrollingImageIsReadAsEnlargedFourThousandRowStrips() async throws {
        let text = FakeTextReader(steps: [
            .lines([]), .lines([]), .lines([ocr("late", rect(20, 400, 80, 20))]),
        ])
        let map = try await reader(text).read(.buffer(try blank(100, 4500)), pixelsPerPoint: 1)
        #expect(text.calls.map(\.width) == [200, 200, 200])
        #expect(text.calls.map(\.height) == [4000, 4000, 1400])
        // Strip 3 starts at row 3800; its boxes are halved and moved down.
        #expect(map.lines.map(\.box) == [rect(10, 4000, 40, 10)])
        #expect(map.width == 100)
        #expect(map.height == 4500)
    }

    @Test func aTwoXImageIsReadUnscaled() async throws {
        let text = FakeTextReader(lines: [ocr("Save", rect(5, 5, 40, 20))])
        let map = try await reader(text).read(.buffer(try blank(50, 100)), pixelsPerPoint: 2)
        #expect(text.calls.map(\.width) == [50])
        #expect(text.calls.map(\.height) == [100])
        #expect(map.lines.map(\.text) == ["Save"])
        #expect(map.lines.map(\.box) == [rect(5, 5, 40, 20)])
    }

    @Test func aFileIsDecodedStripByStrip() async throws {
        let files = FakeImageFileReader()
        let url = URL(fileURLWithPath: "/captures/tall.png")
        files.set(url, image: try blank(2, 8200), fingerprint: FileFingerprint(size: 1, modified: Date()))
        let text = FakeTextReader()
        let map = try await reader(text, files: files).read(.file(url), pixelsPerPoint: 2)
        #expect(files.calls.map(\.rows) == [0..<4000, 3800..<7800, 7600..<8200])
        #expect(text.calls.map(\.height) == [4000, 4000, 600])
        #expect(map.height == 8200)
        #expect(map.isEmpty)
    }

    @Test func theMergeDropsBandLinesReplacesCutLinesAndKeepsTheRest() async throws {
        // 8,200 px at 2×: strip 1 starts at 3800, its top band is 3800..<4000.
        let text = FakeTextReader(steps: [
            .lines([
                ocr("top", rect(0, 100, 50, 20)),
                ocr("in band", rect(0, 3900, 50, 20)),
                ocr("cut", rect(0, 3990, 50, 10)),  // cut by the strip's bottom edge
            ]),
            .lines([
                ocr("in band", rect(0, 100, 50, 20)),  // 3900..3920: entirely in the band, dropped
                ocr("cut whole", rect(0, 190, 50, 20)),  // 3990..4010: starts in the band, replaces "cut"
                ocr("below", rect(0, 500, 50, 20)),  // kept
            ]),
            .lines([]),
        ])
        let map = try await reader(text).read(.buffer(try blank(100, 8200)), pixelsPerPoint: 2)
        #expect(map.lines.map(\.text) == ["top", "in band", "cut whole", "below"])
        #expect(map.lines.map(\.box.minY) == [100, 3900, 3990, 4300])
    }

    @Test func aCutLineOnlyReplacesLinesItOverlaps() async throws {
        let text = FakeTextReader(steps: [
            .lines([ocr("left", rect(0, 3990, 50, 10)), ocr("right", rect(200, 3990, 50, 10))]),
            .lines([ocr("left whole", rect(0, 190, 50, 20))]),
            .lines([]),
        ])
        let map = try await reader(text).read(.buffer(try blank(300, 8200)), pixelsPerPoint: 2)
        #expect(map.lines.map(\.text) == ["left whole", "right"])
    }

    @Test func aHangingStripTimesOutAfterTenSecondsOnTheClock() async throws {
        let clock = ManualClock()
        let text = FakeTextReader(steps: [.lines([]), .hang])
        let mapReader = reader(text, clock: clock)
        let image = try blank(10, 8200)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        #expect(await eventually { text.calls.count == 2 && clock.sleepers == 1 })
        clock.advance(by: .milliseconds(9999))
        #expect(clock.sleepers == 1)
        clock.advance(by: .milliseconds(1))
        await #expect(throws: TextMapError.timedOut(strip: 1)) { try await task.value }
    }

    @Test func readerErrorsAreWrapped() async throws {
        let text = FakeTextReader(steps: [.failure("vision broke")])
        await #expect(throws: TextMapError.recognitionFailed(String(describing: FakeFailure("vision broke")))) {
            try await reader(text).read(.buffer(try blank(10, 10)), pixelsPerPoint: 2)
        }
    }

    @Test func fileErrorsAreUnreadable() async throws {
        let url = URL(fileURLWithPath: "/captures/gone.png")
        await #expect(throws: TextMapError.unreadable(url)) {
            try await reader(FakeTextReader()).read(.file(url), pixelsPerPoint: 2)
        }
        let files = FakeImageFileReader()
        files.set(url, image: try blank(2, 2), fingerprint: FileFingerprint(size: 1, modified: Date()))
        files.beforePixels = { files, url, _ in files.remove(url) }
        await #expect(throws: TextMapError.unreadable(url)) {
            try await reader(FakeTextReader(), files: files).read(.file(url), pixelsPerPoint: 2)
        }
    }

    @Test func cancellingTheReadThrowsCancellationNotATimeout() async throws {
        let gate = FakeGate()
        let clock = ManualClock()
        let text = FakeTextReader(steps: [.gate(gate, [])])
        let mapReader = reader(text, clock: clock)
        let image = try blank(10, 10)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        #expect(await eventually { gate.waiting == 1 })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationIsCheckedBetweenStrips() async throws {
        let text = FakeTextReader()
        let count = Mutex(0)
        let mapReader = reader(text)
        let image = try blank(10, 8200)
        let task = Task {
            try await mapReader.read(.buffer(image), pixelsPerPoint: 2) {
                // Cancel this read from inside it, before strip 2.
                if count.withLock({
                    $0 += 1; return $0
                }) == 2 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(text.calls.count == 1)
    }

    @Test func beforeStripRunsBeforeEachStripAndItsErrorStopsTheRead() async throws {
        let text = FakeTextReader()
        let count = Mutex(0)
        await #expect(throws: FakeFailure("moved")) {
            try await reader(text).read(.buffer(try blank(10, 8200)), pixelsPerPoint: 2) {
                if count.withLock({
                    $0 += 1; return $0
                }) == 3 {
                    throw FakeFailure("moved")
                }
            }
        }
        #expect(count.withLock { $0 } == 3)
        #expect(text.calls.count == 2)
    }
}

/// A recogniser that ignores cancellation until the test releases it (Vision's `perform` may not be cancellable).
final class StubbornReader: TextReader, Sendable {
    private let released = Mutex(false)
    private let started = Mutex(false)
    private let sawCancel = Mutex(false)
    var hasStarted: Bool { started.withLock { $0 } }
    var sawCancellation: Bool { sawCancel.withLock { $0 } }
    func release() { released.withLock { $0 = true } }

    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] {
        started.withLock { $0 = true }
        while !released.withLock({ $0 }) {
            if Task.isCancelled { sawCancel.withLock { $0 = true } }
            try? await Task.sleep(for: .milliseconds(1))
        }
        throw FakeFailure("cancelled late")
    }
}

@Suite struct TextMapReaderReviewTests {
    func blank(_ width: Int, _ height: Int) throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, fill: RGBA8(red: 255, green: 255, blue: 255))
    }

    @Test func aReaderThatIgnoresCancellationStillTimesOut() async throws {
        let clock = ManualClock()
        let stubborn = StubbornReader()
        let mapReader = TextMapReader(reader: stubborn, files: FakeImageFileReader(), clock: clock)
        let image = try blank(10, 10)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        #expect(await eventually { stubborn.hasStarted && clock.sleepers == 1 })
        let completion = Completion(task)
        clock.advance(by: .seconds(10))
        let finished = await eventually { completion.isDone }
        stubborn.release()
        #expect(finished)
        await #expect(throws: TextMapError.timedOut(strip: 0)) { try await task.value }
        #expect(await eventually { stubborn.sawCancellation })
    }

    @Test func aCancelledReadWaitsForItsRecogniserUpToTheStripTimeout() async throws {
        // Slice 3 review I2: a cancelled read must not free the store's one read slot while its recogniser still
        // runs, so it resolves only when the recogniser returns or the strip timeout passes.
        let clock = ManualClock()
        let stubborn = StubbornReader()
        let mapReader = TextMapReader(reader: stubborn, files: FakeImageFileReader(), clock: clock)
        let image = try blank(10, 10)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        #expect(await eventually { stubborn.hasStarted && clock.sleepers == 1 })
        let completion = Completion(task)
        task.cancel()
        #expect(await eventually { stubborn.sawCancellation })
        try await Task.sleep(for: .milliseconds(20))
        #expect(!completion.isDone)
        clock.advance(by: .seconds(10))
        let finished = await eventually { completion.isDone }
        stubborn.release()
        #expect(finished)
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func aCancelledReadResolvesAsSoonAsItsRecogniserReturns() async throws {
        let clock = ManualClock()
        let stubborn = StubbornReader()
        let mapReader = TextMapReader(reader: stubborn, files: FakeImageFileReader(), clock: clock)
        let image = try blank(10, 10)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        #expect(await eventually { stubborn.hasStarted })
        let completion = Completion(task)
        task.cancel()
        stubborn.release()
        #expect(await eventually { completion.isDone })
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func theTimeoutIsPerStripNotPerRead() async throws {
        let clock = ManualClock()
        let gate = FakeGate()
        let text = FakeTextReader(steps: [.gate(gate, []), .hang])
        let mapReader = TextMapReader(reader: text, files: FakeImageFileReader(), clock: clock)
        let image = try blank(10, 8200)
        let task = Task { try await mapReader.read(.buffer(image), pixelsPerPoint: 2) }
        let completion = Completion(task)
        #expect(await eventually { gate.waiting == 1 && clock.sleepers == 1 })
        clock.advance(by: .seconds(9))
        gate.open()
        #expect(await eventually { text.calls.count == 2 && clock.sleepers == 1 })
        clock.advance(by: .seconds(9))
        try await Task.sleep(for: .milliseconds(20))
        #expect(!completion.isDone)
        clock.advance(by: .seconds(1))
        await #expect(throws: TextMapError.timedOut(strip: 1)) { try await task.value }
    }

    @Test func adjacentLinesOverlappingAtTheStripEdgeAreBothKept() async throws {
        // Review I2: "A above" is entirely in strip 1's band, so strip 1's copy is dropped; the cut "B" must not
        // take strip 0's copy of A with it, since the two only touch by 3 px.
        let text = FakeTextReader(steps: [
            .lines([ocr("A above", rect(0, 3950, 50, 35)), ocr("B cut", rect(0, 3982, 50, 18))]),
            .lines([ocr("A above", rect(0, 150, 50, 35)), ocr("B whole", rect(0, 182, 50, 33))]),
            .lines([]),
        ])
        let map = try await TextMapReader(reader: text, files: FakeImageFileReader())
            .read(.buffer(try blank(100, 8200)), pixelsPerPoint: 2)
        #expect(map.lines.map(\.text) == ["A above", "B whole"])
    }

    @Test func theBandCopyIsDroppedEvenWhenItDiffersAndALineEndingAtTheBandEdgeIsInIt() async throws {
        let text = FakeTextReader(steps: [
            .lines([ocr("from strip 0", rect(0, 3900, 50, 20)), ocr("edge 0", rect(100, 3980, 50, 20))]),
            .lines([ocr("from strip 1", rect(5, 100, 50, 20)), ocr("edge 1", rect(105, 180, 50, 20))]),
            .lines([]),
        ])
        let map = try await TextMapReader(reader: text, files: FakeImageFileReader())
            .read(.buffer(try blank(200, 8200)), pixelsPerPoint: 2)
        #expect(map.lines.map(\.text) == ["from strip 0", "edge 0"])
    }
}

/// Becomes true once the watched task has finished, without the test having to await it.
final class Completion: Sendable {
    private let state = Mutex(false)
    var isDone: Bool { state.withLock { $0 } }

    init<T: Sendable>(_ task: Task<T, any Error>) {
        Task { [state = self] in
            _ = try? await task.value
            state.finish()
        }
    }

    private func finish() { state.withLock { $0 = true } }
}

@Suite struct TextMapReaderFileChangeTests {
    @Test func aStripDecodedAtAnotherSizeThanTheFileSaidFailsTheRead() async throws {
        // claude-review on #9: the file is rewritten between `info` and the strip's decode.
        let files = FakeImageFileReader()
        let url = URL(fileURLWithPath: "/captures/rewritten.png")
        let print = FileFingerprint(size: 1, modified: Date())
        files.set(
            url, image: try PixelBuffer(width: 10, height: 20, fill: RGBA8(red: 9, green: 9, blue: 9)),
            fingerprint: print)
        let wider = try PixelBuffer(width: 30, height: 20, fill: RGBA8(red: 9, green: 9, blue: 9))
        files.beforePixels = { files, url, _ in files.set(url, image: wider, fingerprint: print) }
        let text = FakeTextReader()
        await #expect(throws: TextMapError.unreadable(url)) {
            try await TextMapReader(reader: text, files: files).read(.file(url), pixelsPerPoint: 2)
        }
        #expect(text.calls.isEmpty)
    }
}

/// Throws `CancellationError` for its own reasons, with its task not cancelled.
struct SelfCancellingReader: TextReader {
    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] { throw CancellationError() }
}

@Suite struct TextMapReaderSpuriousCancellationTests {
    @Test func aRecogniserThatCancelsItselfIsARecognitionFailure() async throws {
        // claude-review on #9: only a cancellation of the read itself is a cancellation.
        let image = try PixelBuffer(width: 4, height: 4, fill: RGBA8(red: 0, green: 0, blue: 0))
        await #expect(throws: TextMapError.recognitionFailed(String(describing: CancellationError()))) {
            try await TextMapReader(reader: SelfCancellingReader(), files: FakeImageFileReader())
                .read(.buffer(image), pixelsPerPoint: 2)
        }
    }
}

@Suite struct TextMapReaderTimeoutRaceTests {
    @Test func aTimeoutIsAlwaysReportedAsATimeoutNeverAsARecognitionFailure() async throws {
        // claude-review on #9: the timer must record `timedOut` before it cancels the recogniser, or the recogniser's
        // own CancellationError can win and be reported as `recognitionFailed`.
        let image = try PixelBuffer(width: 4, height: 4, fill: RGBA8(red: 0, green: 0, blue: 0))
        var outcomes: [String] = []
        for _ in 0..<200 {
            let clock = ManualClock()
            let text = FakeTextReader(steps: [.hang])
            let reader = TextMapReader(reader: text, files: FakeImageFileReader(), clock: clock)
            let task = Task { try await reader.read(.buffer(image), pixelsPerPoint: 2) }
            #expect(await eventually { text.calls.count == 1 && clock.sleepers == 1 })
            clock.advance(by: .seconds(10))
            do {
                _ = try await task.value
                outcomes.append("map")
            } catch {
                outcomes.append(String(describing: error))
            }
        }
        #expect(Set(outcomes) == ["timed out on strip 0"])
    }
}
