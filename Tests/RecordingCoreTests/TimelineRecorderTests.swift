import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

/// Shared set-up: the recorded area's top-left is (100, 50) in Quartz global points; the first frame is at host
/// second 1000.
enum TimelineTesting {
    static let origin = Point2D(x: 100, y: 50)
    static let start = 1000.0

    static func header(keys: Bool = true, elements: Bool = true) -> TimelineHeader {
        TimelineHeader(
            take: UUID(), startedAt: Date(timeIntervalSince1970: 1_795_788_192.481),
            target: TimelineHeader.Target(
                kind: .area, display: DisplayID(1), scale: 2, window: nil,
                area: Rect2D(x: origin.x, y: origin.y, width: 1280, height: 720)),
            video: TimelineHeader.Video(width: 2560, height: 1440, fps: 30), cursorHz: 30, hasKeys: keys,
            hasElements: elements)
    }

    static func recorder(
        in dir: TempDirectory, keys: Bool = true, elements: Bool = true, reader: (any AXReader)? = nil,
        limits: TimelineLimits = TimelineLimits(), timeout: Duration = .milliseconds(250)
    ) throws -> (TimelineRecorder, URL) {
        let url = dir.file("Take-x.timeline.jsonl")
        let configuration = TimelineRecorder.Configuration(
            url: url, header: header(keys: keys, elements: elements), limits: limits, lookupTimeout: timeout)
        return (try TimelineRecorder(configuration, reader: reader, startedAt: start), url)
    }

    /// Host seconds for a video time in ms (no pauses).
    static func at(_ ms: Int) -> Double { start + Double(ms) / 1000 }

    static func global(_ x: Double, _ y: Double) -> Point2D { Point2D(x: origin.x + x, y: origin.y + y) }

    static func press(_ keyCode: UInt16, _ characters: String, _ modifiers: Set<TimelineModifier> = [])
        -> TimelineInput
    {
        .key(KeyPress(keyCode: keyCode, characters: characters, modifiers: modifiers))
    }

    static func lines(_ url: URL) throws -> [TimelineLine] {
        try TimelineReader.read(Data(contentsOf: url)).lines
    }
}

@Suite struct TimelineRecorderTests {
    typealias T = TimelineTesting

    @Test func everyKindIsWrittenRelativeToTheArea() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(10, 20)), at: T.at(0))
        await recorder.record(.down(.left, T.global(30, 40), clicks: 1), at: T.at(100))
        await recorder.record(.up(.left, T.global(30, 41)), at: T.at(180))
        await recorder.record(.scroll(T.global(5, 5), dx: 0, dy: -12), at: T.at(300))
        await recorder.record(T.press(1, "s", [.cmd]), at: T.at(400))
        await recorder.record(
            .focus(
                app: "com.apple.Safari", name: "Safari", window: WindowID(7),
                frame: Rect2D(x: 0, y: 0, width: 9, height: 9)),
            at: T.at(500))
        await recorder.record(.area(Rect2D(x: 140, y: 80, width: 1280, height: 720)), at: T.at(600))
        await recorder.record(.move(Point2D(x: 150, y: 90)), at: T.at(700))
        let summary = await recorder.finish(at: T.at(1000))
        let lines = try T.lines(url)
        let cmdS = try #require(TimelineKey(key: "S", modifiers: [.cmd]))
        #expect(
            lines == [
                TimelineLine(t: 0, event: .move(Point2D(x: 10, y: 20))),
                TimelineLine(t: 100, event: .down(id: 1, button: .left, at: Point2D(x: 30, y: 40), clicks: 1)),
                TimelineLine(t: 180, event: .up(id: 1, button: .left, at: Point2D(x: 30, y: 41))),
                TimelineLine(t: 300, event: .scroll(at: Point2D(x: 5, y: 5), dx: 0, dy: -12)),
                TimelineLine(t: 400, event: .key(cmdS)),
                TimelineLine(
                    t: 500,
                    event: .focus(
                        app: "com.apple.Safari", name: "Safari", window: WindowID(7),
                        frame: Rect2D(x: 0, y: 0, width: 9, height: 9))),
                TimelineLine(t: 600, event: .area(Rect2D(x: 140, y: 80, width: 1280, height: 720))),
                // Relative to the new area's top-left.
                TimelineLine(t: 700, event: .move(Point2D(x: 10, y: 10))),
                TimelineLine(t: 1000, event: .end(events: 8)),
            ])
        #expect(summary.events == 8)
        #expect(summary.bytes == (try Data(contentsOf: url)).count)
        #expect(summary.error == nil)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasSuffix("\n"))
        #expect(text.hasPrefix(TimelineLineEncoder.header(try TimelineReader.read(Data(text.utf8)).header) + "\n"))
    }

    @Test func cursorMovesAreSampledAt30HzAndHalfAPoint() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(0, 0)), at: T.at(0))
        await recorder.record(.move(T.global(5, 0)), at: T.at(10))  // too soon
        await recorder.record(.move(T.global(0.3, 0.3)), at: T.at(40))  // under 0.5 pt from the last line
        await recorder.record(.move(T.global(0.4, 0.4)), at: T.at(80))  // 0.57 pt
        await recorder.record(.move(T.global(0.4, 0.4)), at: T.at(200))  // not moved
        _ = await recorder.finish(at: T.at(300))
        #expect(
            try T.lines(url).map(\.event) == [
                .move(Point2D(x: 0, y: 0)), .move(Point2D(x: 0.4, y: 0.4)), .end(events: 2),
            ])
    }

    @Test func clicksArePairedById() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.down(.left, T.global(1, 1), clicks: 1), at: T.at(0))
        await recorder.record(.down(.right, T.global(2, 2), clicks: 1), at: T.at(10))
        await recorder.record(.up(.right, T.global(2, 2)), at: T.at(20))
        await recorder.record(.up(.left, T.global(1, 1)), at: T.at(30))
        await recorder.record(.down(.other, T.global(3, 3), clicks: 2), at: T.at(40))
        await recorder.record(.up(.other, T.global(3, 3)), at: T.at(50))
        await recorder.record(.up(.left, T.global(1, 1)), at: T.at(60))  // no down: dropped
        _ = await recorder.finish(at: T.at(100))
        #expect(
            try T.lines(url).map(\.event) == [
                .down(id: 1, button: .left, at: Point2D(x: 1, y: 1), clicks: 1),
                .down(id: 2, button: .right, at: Point2D(x: 2, y: 2), clicks: 1),
                .up(id: 2, button: .right, at: Point2D(x: 2, y: 2)),
                .up(id: 1, button: .left, at: Point2D(x: 1, y: 1)),
                .down(id: 3, button: .other, at: Point2D(x: 3, y: 3), clicks: 2),
                .up(id: 3, button: .other, at: Point2D(x: 3, y: 3)),
                .end(events: 6),
            ])
    }

    @Test func scrollsAreSummedOver100Milliseconds() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.scroll(T.global(1, 1), dx: 0, dy: -10), at: T.at(0))
        await recorder.record(.scroll(T.global(2, 2), dx: 1, dy: -10), at: T.at(50))
        await recorder.record(.scroll(T.global(3, 3), dx: 0, dy: -5), at: T.at(100))
        await recorder.record(.scroll(T.global(4, 4), dx: 0, dy: 7), at: T.at(150))  // a new group
        await recorder.record(.down(.left, T.global(5, 5), clicks: 1), at: T.at(160))  // ends it
        await recorder.record(.scroll(T.global(6, 6), dx: 0, dy: 1), at: T.at(170))
        _ = await recorder.finish(at: T.at(200))  // writes the last group
        #expect(
            try T.lines(url).map { [$0.t: $0.event] } == [
                [0: .scroll(at: Point2D(x: 3, y: 3), dx: 1, dy: -25)],
                [150: .scroll(at: Point2D(x: 4, y: 4), dx: 0, dy: 7)],
                [160: .down(id: 1, button: .left, at: Point2D(x: 5, y: 5), clicks: 1)],
                [170: .scroll(at: Point2D(x: 6, y: 6), dx: 0, dy: 1)],
                [200: .end(events: 4)],
            ])
    }

    @Test func inputBeforeTheFirstFrameOrInAPauseIsDroppedAndPausesAreMarked() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.down(.left, T.global(0, 0), clicks: 1), at: T.start - 0.5)
        await recorder.record(.move(T.global(1, 1)), at: T.at(1000))
        await recorder.pause(at: T.at(2000))
        await recorder.record(.move(T.global(9, 9)), at: T.at(2500))  // captured in the pause
        await recorder.resume(at: T.at(5000))
        await recorder.record(.move(T.global(2, 2)), at: T.at(6000))
        _ = await recorder.finish(at: T.at(7000))
        #expect(
            try T.lines(url) == [
                TimelineLine(t: 1000, event: .move(Point2D(x: 1, y: 1))),
                TimelineLine(t: 2000, event: .pause),
                TimelineLine(t: 2000, event: .resume),
                TimelineLine(t: 3000, event: .move(Point2D(x: 2, y: 2))),
                TimelineLine(t: 4000, event: .end(events: 4)),
            ])
    }

    @Test func timeNeverGoesBackwardsInFileOrder() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(1, 1)), at: T.at(500))
        await recorder.record(.down(.left, T.global(1, 1), clicks: 1), at: T.at(400))  // arrived late
        _ = await recorder.finish(at: T.at(600))
        #expect(try T.lines(url).map(\.t) == [500, 500, 600])
    }

    @Test func keysAreShortcutsOnlyNeverRepeatsAndOnlyWhenWatched() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(T.press(1, "s", [.cmd]), at: T.at(0))
        await recorder.record(
            .key(KeyPress(keyCode: 1, characters: "s", modifiers: [.cmd], isRepeat: true)), at: T.at(10))
        await recorder.record(T.press(1, "s"), at: T.at(20))
        await recorder.record(T.press(1, "s", [.shift]), at: T.at(30))
        await recorder.record(T.press(123, "", [.shift]), at: T.at(40))
        _ = await recorder.finish(at: T.at(50))
        #expect(try T.lines(url).compactMap { if case .key(let k) = $0.event { k.key } else { nil } } == ["S", "Left"])

        let dir2 = try TempDirectory()
        defer { dir2.remove() }
        let (unwatched, url2) = try T.recorder(in: dir2, keys: false)
        await unwatched.record(T.press(1, "s", [.cmd]), at: T.at(0))
        _ = await unwatched.finish(at: T.at(50))
        #expect(try T.lines(url2).map(\.event) == [.end(events: 0)])
    }

    @Test func discardDeletesTheFile() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(1, 1)), at: T.at(0))
        await recorder.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))
        await recorder.discard()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Nothing after a discard recreates it.
        await recorder.record(.move(T.global(5, 5)), at: T.at(100))
        _ = await recorder.finish(at: T.at(200))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aCrashTruncatedFileReadsBackWithoutItsPartialLine() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(1, 1)), at: T.at(0))
        await recorder.record(.move(T.global(2, 2)), at: T.at(100))
        await recorder.flush()
        // The process dies mid-append.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"t":200,"k":"mo"#.utf8))
        try handle.close()
        let read = try TimelineReader.read(Data(contentsOf: url))
        #expect(read.lines.map(\.t) == [0, 100])
        await recorder.discard()
    }

    @Test func flushAppendsWhatIsBuffered() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        await recorder.record(.move(T.global(1, 1)), at: T.at(0))
        #expect(try T.lines(url).isEmpty)
        await recorder.flush()
        #expect(try T.lines(url).count == 1)
        await recorder.discard()
    }

    @Test func thePeriodicFlushWritesWithoutBeingAsked() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("t.timeline.jsonl")
        let recorder = try TimelineRecorder(
            TimelineRecorder.Configuration(
                url: url, header: T.header(), flushInterval: .milliseconds(10)),
            reader: nil, startedAt: T.start)
        await recorder.startFlushing()
        await recorder.record(.move(T.global(1, 1)), at: T.at(0))
        var waited = 0
        while (try T.lines(url)).isEmpty, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(try T.lines(url).count == 1)
        await recorder.discard()
    }
}

@Suite struct TimelineElementLookupTests {
    typealias T = TimelineTesting

    static let save = AXElementInfo(
        role: "AXButton", title: "Save", text: nil, frame: Rect2D(x: 700, y: 80, width: 60, height: 24),
        isTextEntry: false)
    static let password = AXElementInfo(
        role: "AXTextField", subrole: "AXSecureTextField", title: nil, text: nil,
        frame: Rect2D(x: 100, y: 200, width: 200, height: 24), isTextEntry: true, isSecure: true)

    private func elementEvents(_ url: URL) throws -> [TimelineLine] {
        try T.lines(url).filter {
            switch $0.event {
            case .element, .elementStatus: true
            default: false
            }
        }
    }

    @Test func aClickGetsItsElementSecureFieldsAreWithheldAndNothingIsNone() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save, Self.password]])
        let (recorder, url) = try T.recorder(in: dir, reader: reader)
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        await recorder.waitForLookup()
        await recorder.record(.down(.left, Point2D(x: 150, y: 210), clicks: 1), at: T.at(200))
        await recorder.waitForLookup()
        await recorder.record(.down(.left, Point2D(x: 5000, y: 5000), clicks: 1), at: T.at(300))
        _ = await recorder.finish(at: T.at(400))
        let lines = try elementEvents(url)
        #expect(
            lines == [
                TimelineLine(
                    t: 100,
                    event: .element(
                        click: 1,
                        TimelineElement(
                            role: "AXButton", subrole: nil, title: "Save",
                            frame: Rect2D(x: 600, y: 30, width: 60, height: 24))!)),
                TimelineLine(t: 200, event: .elementStatus(click: 2, .withheld)),
                TimelineLine(t: 300, event: .elementStatus(click: 3, .none)),
            ])
        let lastTwo = try T.lines(url).suffix(2).map(\.event)
        #expect(lastTwo.last == .end(events: 6))
    }

    @Test func aSlowLookupTimesOut() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]], delay: .seconds(60))
        let (recorder, url) = try T.recorder(in: dir, reader: reader, timeout: .milliseconds(20))
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        _ = await recorder.finish(at: T.at(400))
        #expect(try elementEvents(url) == [TimelineLine(t: 100, event: .elementStatus(click: 1, .timeout))])
        #expect(try T.lines(url).last?.event == .end(events: 2))
    }

    @Test func aClickDuringALookupIsSkipped() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let gate = FakeAXReader.Gate()
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]], gate: gate)
        let (recorder, url) = try T.recorder(in: dir, reader: reader, timeout: .seconds(30))
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        await gate.waitUntilEntered(count: 1)
        await recorder.record(.down(.left, Point2D(x: 711, y: 90), clicks: 2), at: T.at(150))
        gate.open()
        _ = await recorder.finish(at: T.at(400))
        let lines = try elementEvents(url)
        #expect(lines.count == 2)
        #expect(lines.first == TimelineLine(t: 150, event: .elementStatus(click: 2, .skipped)))
        if case .element(let click, let element) = lines.last?.event {
            #expect(click == 1)
            #expect(element.title == "Save")
        } else {
            Issue.record("no element line for click 1")
        }
    }

    @Test func noLookupWithoutElementsWatched() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let reader = FakeAXReader(elementsByProcess: [1: [Self.save]])
        let (recorder, url) = try T.recorder(in: dir, elements: false, reader: reader)
        await recorder.record(.down(.left, Point2D(x: 710, y: 90), clicks: 1), at: T.at(100))
        _ = await recorder.finish(at: T.at(400))
        #expect(try elementEvents(url).isEmpty)
    }
}

@Suite struct TimelineLimitTests {
    typealias T = TimelineTesting

    @Test func movesStopAtTheCursorCapAndOtherEventsGoOn() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let limits = TimelineLimits(cursorBytes: 2000, totalBytes: 8000, reserve: 512)
        let (recorder, url) = try T.recorder(in: dir, limits: limits)
        for n in 0..<200 {
            await recorder.record(.move(T.global(Double(n), 0)), at: T.at(n * 40))
        }
        await recorder.record(.down(.left, T.global(1, 1), clicks: 1), at: T.at(9000))
        _ = await recorder.finish(at: T.at(9100))
        let lines = try T.lines(url)
        let truncIndex = try #require(lines.firstIndex { $0.event == .trunc(.cursor) })
        #expect(lines[truncIndex...].allSatisfy { if case .move = $0.event { false } else { true } })
        #expect(lines.contains { if case .down = $0.event { true } else { false } })
        #expect(lines.last?.event == .end(events: lines.count - 1))
        #expect(lines.filter { $0.event == .trunc(.cursor) }.count == 1)
        let size = try Data(contentsOf: url).count
        #expect(size > 1500)
    }

    @Test func everythingStopsAtTheSizeCapAndEndIsStillWritten() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let limits = TimelineLimits(cursorBytes: 100_000, totalBytes: 3000, reserve: 256)
        let (recorder, url) = try T.recorder(in: dir, limits: limits)
        for n in 0..<300 {
            await recorder.record(.down(.left, T.global(Double(n), 0), clicks: 1), at: T.at(n * 10))
        }
        let summary = await recorder.finish(at: T.at(5000))
        let data = try Data(contentsOf: url)
        #expect(data.count <= 3000)
        let lines = try T.lines(url)
        #expect(lines.filter { $0.event == .trunc(.size) }.count == 1)
        #expect(lines.last == TimelineLine(t: 5000, event: .end(events: lines.count - 1)))
        #expect(summary.events == lines.count - 1)
        #expect(summary.truncations == [.size])
    }
}
