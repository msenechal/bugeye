import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@testable import RecordingCore

/// Edge cases from the final review of PR #4.
@Suite struct TimelineRecorderEdgeTests {
    typealias T = TimelineTesting
    static let save = TimelineElementLookupTests.save

    private func statuses(_ url: URL) throws -> [Int: TimelineElementStatus] {
        var out: [Int: TimelineElementStatus] = [:]
        for line in try T.lines(url) {
            if case .elementStatus(let click, let status) = line.event { out[click] = status }
        }
        return out
    }

    /// I1: a reader that ignores cancellation stays "in flight" after its deadline: later clicks are skipped,
    /// so hung Accessibility calls never pile up.
    @Test func aReaderStuckPastItsDeadlineStillCountsAsInFlight() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let gate = FakeAXReader.Gate()
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]], gate: gate)
        let (recorder, url) = try T.recorder(in: dir, reader: reader, timeout: .milliseconds(20))
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        await recorder.waitForLookup()
        for n in 2...5 {
            await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100 * n))
        }
        #expect(gate.entered == 1)
        gate.open()
        _ = await recorder.finish(at: T.at(1000))
        #expect(try statuses(url) == [1: .timeout, 2: .skipped, 3: .skipped, 4: .skipped, 5: .skipped])
    }

    /// I2: a 30 Hz sampler with a millisecond of jitter keeps every sample.
    @Test func aJitteredSamplerKeepsEverySample() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        var random = SplitMix64(seed: 7)
        var ms = 0.0
        for n in 0..<300 {
            let jitter = n == 0 ? 0 : Double(Int(random.next() % 3) - 1)  // −1, 0 or +1 ms
            await recorder.record(.move(T.global(Double(n), 0)), at: T.start + (ms + jitter) / 1000)
            ms += 1000.0 / 30
        }
        _ = await recorder.finish(at: T.at(20_000))
        #expect(try T.lines(url).filter { if case .move = $0.event { true } else { false } }.count == 300)
    }

    /// I3: once finish has begun, input is refused and `end` keeps finish's time.
    @Test func inputDuringFinishIsRefused() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let gate = FakeAXReader.Gate()
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]], gate: gate)
        let (recorder, url) = try T.recorder(in: dir, reader: reader, timeout: .seconds(30))
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        await gate.waitUntilEntered(count: 1)
        let finishing = Task { await recorder.finish(at: T.at(200)) }
        var waited = 0
        while await recorder.acceptsInput, waited < 10_000 {
            await Task.yield()
            waited += 1
        }
        #expect(await !recorder.acceptsInput)
        await recorder.record(.move(T.global(1, 1)), at: T.at(5000))
        await recorder.record(.scroll(T.global(1, 1), dx: 0, dy: 3), at: T.at(5100))
        await recorder.pause(at: T.at(5200))
        gate.open()
        _ = await finishing.value
        let lines = try T.lines(url)
        #expect(lines.last == TimelineLine(t: 200, event: .end(events: 2)))
        #expect(lines.count == 3)
    }

    /// I4 and I6: a late element line that crosses the cap never puts `trunc` back in time.
    @Test func aTruncLineNeverGoesBackInTime() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let header = T.header()
        let headerBytes = TimelineLineEncoder.header(header).utf8.count + 1
        let key = TimelineLine(t: 1000, event: .key(try #require(TimelineKey(key: "S", modifiers: [.cmd]))))
        let keyBytes = TimelineLineEncoder.line(key).utf8.count + 1
        let writer = try TimelineWriter(
            url: dir.file("t.jsonl"), header: header,
            limits: TimelineLimits(cursorBytes: 1 << 20, totalBytes: headerBytes + keyBytes + 20 + 256, reserve: 256))
        writer.append(key)
        let element = TimelineElement(
            role: "AXButton", subrole: nil, title: String(repeating: "x", count: 60), frame: .zero)!
        writer.append(TimelineLine(t: 100, event: .element(click: 1, element)))
        writer.finish(t: 2000)
        let lines = try T.lines(dir.file("t.jsonl"))
        #expect(lines.map(\.t) == [1000, 1000, 2000])
        #expect(lines[1].event == .trunc(.size))
    }

    /// I6: a cursor cap that would itself cross the size cap truncates by size.
    @Test func aCursorCapPastTheSizeCapTruncatesBySize() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let header = T.header()
        let headerBytes = TimelineLineEncoder.header(header).utf8.count + 1
        let writer = try TimelineWriter(
            url: dir.file("t.jsonl"), header: header,
            limits: TimelineLimits(cursorBytes: headerBytes + 10, totalBytes: headerBytes + 10 + 256, reserve: 256))
        writer.append(TimelineLine(t: 5, event: .move(Point2D(x: 1, y: 1))))
        writer.append(TimelineLine(t: 6, event: .pause))
        writer.finish(t: 7)
        #expect(try T.lines(dir.file("t.jsonl")).map(\.event) == [.trunc(.size), .end(events: 1)])
        #expect(writer.truncations == [.size])
    }

    /// I6: a write error stops the timeline quietly and is reported.
    @Test func aWriteErrorIsReportedAndLaterWritesAreNoOps() throws {
        let path = "/dev/full"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let writer = try TimelineWriter(
            url: URL(fileURLWithPath: path), handle: FileHandle(forWritingAtPath: path)!, header: T.header(),
            limits: TimelineLimits(), flushHeader: false)
        writer.append(TimelineLine(t: 1, event: .pause))
        writer.flush()
        #expect(writer.error != nil)
        #expect(!writer.isOpen)
        writer.append(TimelineLine(t: 2, event: .resume))
        writer.finish(t: 3)
        #expect(writer.error != nil)
    }

    /// claude-review #4: a header that can't be written fails the recorder's creation, not its finish.
    @Test func anUnwritableHeaderThrows() throws {
        let path = "/dev/full"
        guard FileManager.default.fileExists(atPath: path) else { return }
        #expect(throws: (any Error).self) {
            try TimelineWriter(
                url: URL(fileURLWithPath: path), handle: FileHandle(forWritingAtPath: path)!, header: T.header(),
                limits: TimelineLimits())
        }
    }

    /// I6: a lookup that lands after a discard writes nothing and recreates nothing.
    @Test func aLookupLandingAfterDiscardWritesNothing() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let gate = FakeAXReader.Gate()
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]], gate: gate)
        let (recorder, url) = try T.recorder(in: dir, reader: reader, timeout: .seconds(30))
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        await gate.waitUntilEntered(count: 1)
        await recorder.discard()
        gate.open()
        await recorder.waitForLookup()
        try await Task.sleep(for: .milliseconds(20))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// I6: a pause writes the scroll group it ends; M3: a click open across a pause is forgotten.
    @Test func pauseWritesThePendingScrollAndForgetsOpenClicks() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.scroll(T.global(1, 1), dx: 0, dy: 4), at: T.at(100))
        await recorder.record(.down(.left, T.global(2, 2), clicks: 1), at: T.at(150))
        await recorder.pause(at: T.at(200))
        await recorder.resume(at: T.at(400))
        await recorder.record(.up(.left, T.global(2, 2)), at: T.at(500))
        _ = await recorder.finish(at: T.at(600))
        #expect(
            try T.lines(url).map(\.event) == [
                .scroll(at: Point2D(x: 1, y: 1), dx: 0, dy: 4),
                .down(id: 1, button: .left, at: Point2D(x: 2, y: 2), clicks: 1), .pause, .resume, .end(events: 4),
            ])
    }

    /// M2: the header reaches the file at once, so a take that dies in its first second keeps a readable timeline.
    @Test func theHeaderIsWrittenAtOnce() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (_, url) = try T.recorder(in: dir)
        #expect(try TimelineReader.read(Data(contentsOf: url)).lines.isEmpty)
    }

    /// M7: without a reader, the header doesn't claim elements are watched.
    @Test func noReaderMeansNoElementsInTheHeader() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir, elements: true, reader: nil)
        _ = await recorder.finish(at: T.at(10))
        #expect(try TimelineReader.read(Data(contentsOf: url)).header.hasElements == false)
    }
}

@Suite struct TimelineDateTests {
    /// I5: milliseconds are rounded the same way on every platform.
    @Test func startedAtIsRoundedToTheMillisecond() {
        #expect(
            TimelineLineEncoder.iso8601(Date(timeIntervalSince1970: 1_795_788_192.481)) == "2026-11-27T14:03:12.481Z")
        #expect(
            TimelineLineEncoder.iso8601(Date(timeIntervalSince1970: 1_795_788_192.9996)) == "2026-11-27T14:03:13.000Z")
        #expect(TimelineLineEncoder.iso8601(Date(timeIntervalSince1970: 0.0004)) == "1970-01-01T00:00:00.000Z")
    }

    /// M9: a header without milliseconds still reads.
    @Test func wholeSecondsAreAccepted() {
        #expect(TimelineLineEncoder.date("2026-11-27T14:03:12Z") == Date(timeIntervalSince1970: 1_795_788_192))
        #expect(TimelineLineEncoder.date("2026-11-27T14:03:12.481Z") != nil)
    }
}
