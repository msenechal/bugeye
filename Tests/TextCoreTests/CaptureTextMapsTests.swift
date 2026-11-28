import BugeyeCore
import BugeyeTestSupport
import Foundation
import Synchronization
import Testing

@testable import TextCore

/// Collects log lines. Thread-safe.
final class LogBox: Sendable {
    private let state = Mutex<[TextLogLine]>([])
    func append(_ line: TextLogLine) { state.withLock { $0.append(line) } }
    var lines: [TextLogLine] { state.withLock { $0 } }
}

/// A store with fakes. Each capture's image is `width` pixels wide, so `text.calls` shows which capture was read.
final class StoreHarness: Sendable {
    let files = FakeImageFileReader()
    let text: FakeTextReader
    let clock = ManualClock()
    let store: CaptureTextMaps
    private let logged = LogBox()
    private let stamp = Mutex<Double>(0)

    init(steps: [FakeTextReader.Step] = [], fallback: FakeTextReader.Step? = nil, capacity: Int = 200) {
        let line = OCRLine(text: "Save", bounds: Rect2D(x: 0, y: 0, width: 1, height: 1), confidence: 1)
        text = FakeTextReader(steps: steps, fallback: fallback ?? .lines([line]))
        let reader = TextMapReader(reader: text, files: files, clock: clock)
        let logged = self.logged
        store = CaptureTextMaps(reader: reader, files: files, capacity: capacity, log: { logged.append($0) })
    }

    var logs: [TextLogLine] { logged.lines }

    /// The read widths, in call order.
    var reads: [Int] { text.calls.map(\.width) }

    func fingerprint() -> FileFingerprint {
        let n = stamp.withLock {
            $0 += 1; return $0
        }
        return FileFingerprint(size: Int64(n), modified: Date(timeIntervalSince1970: n))
    }

    /// A capture whose file exists, `width` wide.
    func capture(width: Int, kind: CaptureKind = .screenshot, height: Int = 10) throws -> CaptureItem {
        let id = CaptureID()
        let url = URL(fileURLWithPath: "/captures/\(id).png")
        try put(url, width: width, height: height)
        return CaptureItem(
            id: id, fileURL: url, isSaved: false, kind: kind, createdAt: Date(), pixelsPerPoint: 2)
    }

    func put(_ url: URL, width: Int, height: Int = 10) throws {
        files.set(
            url, image: try PixelBuffer(width: width, height: height, fill: RGBA8(red: 255, green: 255, blue: 255)),
            fingerprint: fingerprint())
    }

    func send(_ change: CaptureChange, _ item: CaptureItem) async {
        await store.handle(CaptureEvent(change: change, item: item, origin: "test"))
    }

    func moved(_ item: CaptureItem, to name: String, change: CaptureChange = .moved) async throws -> CaptureItem {
        var item = item
        let width = try await files.info(of: item.fileURL).width
        item.fileURL = URL(fileURLWithPath: "/saved/\(name).png")
        try put(item.fileURL, width: width)
        files.remove(URL(fileURLWithPath: "/captures/\(item.id).png"))
        await send(change, item)
        return item
    }

    func mapTask(_ item: CaptureItem) -> Task<CaptureTextMap, any Error> {
        let store = self.store
        return Task { try await store.map(for: item) }
    }
}

@Suite struct CaptureTextMapsTests {
    // MARK: Q1, Q2: one read at a time; demand first (oldest), then the newest background read.

    @Test func atMostOneReadRunsAtATime() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        await h.send(.created, try h.capture(width: 1))
        await h.send(.created, try h.capture(width: 2))
        #expect(await eventually { gate.waiting == 1 })
        try await Task.sleep(for: .milliseconds(20))
        #expect(h.reads == [1])
        gate.open()
        #expect(await eventually { h.reads == [1, 2] })
    }

    @Test func demandReadsComeFirstOldestFirstThenTheNewestBackgroundRead() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let b = try h.capture(width: 2)
        let c = try h.capture(width: 3)
        let d = try h.capture(width: 4)
        let e = try h.capture(width: 5)
        await h.send(.created, a)
        #expect(await eventually { gate.waiting == 1 })
        await h.send(.created, b)
        await h.send(.created, c)
        await h.send(.created, d)
        let onE = h.mapTask(e)  // unknown to the store: an on-demand read (plan P7)
        #expect(await eventually { await h.store.waiters(e.id) == 1 })
        let onB = h.mapTask(b)  // a queued background read becomes on-demand, after e (plan P13)
        #expect(await eventually { await h.store.waiters(b.id) == 1 })
        gate.open()
        _ = try await onE.value
        _ = try await onB.value
        #expect(await eventually { h.reads.count == 5 })
        #expect(h.reads == [1, 5, 2, 4, 3])
    }

    // MARK: Q3: which events queue reads; the mirror.

    @Test func onlyWantedCapturesAreReadInTheBackground() async throws {
        let h = StoreHarness()
        await h.send(.created, try h.capture(width: 1, kind: .recording))
        await h.send(.created, try h.capture(width: 2, kind: .gif))
        await h.send(.created, try h.capture(width: 3))
        #expect(await eventually { h.reads == [3] })
        try await Task.sleep(for: .milliseconds(20))
        #expect(h.reads == [3])
    }

    @Test func editingStartedAndUnknownChangesAreIgnored() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        await h.send(.editingStarted, a)
        await h.send(CaptureChange(rawValue: "somethingNew"), a)
        try await Task.sleep(for: .milliseconds(20))
        #expect(h.reads.isEmpty)
    }

    @Test func savedUpdatesTheURLTheStoreReadsFrom() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let first = try h.capture(width: 1)
        let a = try h.capture(width: 2)
        await h.send(.created, first)
        #expect(await eventually { gate.waiting == 1 })
        await h.send(.created, a)
        let saved = try await h.moved(a, to: "a", change: .saved)
        gate.open()
        #expect(await eventually { await h.store.cached(a.id) != nil })
        #expect(h.files.calls.map(\.url).last == saved.fileURL)
    }

    @Test func theMirrorWinsOverAStaleItem() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        await h.send(.created, a)
        #expect(await eventually { await h.store.cached(a.id) != nil })
        let moved = try await h.moved(a, to: "a")
        let result = try await h.store.map(for: a)  // a still names the old URL
        #expect(result.map.lines.map(\.text) == ["Save"])
        #expect(h.files.calls.map(\.url).last == moved.fileURL)
    }

    // MARK: Q4: cache, join, promote.

    @Test func aCachedMapWithTheSameFingerprintIsReturnedWithoutARead() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        let first = try await h.store.map(for: a)
        let second = try await h.store.map(for: a)
        #expect(first == second)
        #expect(h.reads == [1])
        #expect(first.key.id == a.id)
        #expect(first.key.fingerprint == (try await h.files.info(of: a.fileURL)).fingerprint)
    }

    @Test func aChangedFingerprintIsACacheMiss() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        _ = try await h.store.map(for: a)
        try h.put(a.fileURL, width: 1)
        let second = try await h.store.map(for: a)
        #expect(h.reads == [1, 1])
        #expect(second.key.fingerprint == (try await h.files.info(of: a.fileURL)).fingerprint)
    }

    @Test func aRunningReadIsJoined() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let one = h.mapTask(a)
        let two = h.mapTask(a)
        #expect(await eventually { await h.store.waiters(a.id) == 2 })
        gate.open()
        #expect(try await one.value == (try await two.value))
        #expect(h.reads == [1])
    }

    // MARK: Q5, Q5b: deleted, edited, moved.

    @Test func deletingFailsTheWaitersCancelsTheReadAndEvicts() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let b = try h.capture(width: 2)
        let waiter = h.mapTask(a)
        #expect(await eventually { gate.waiting == 1 })
        await h.send(.created, b)
        await h.send(.deleted, a)
        await #expect(throws: TextMapError.captureGone(a.id)) { try await waiter.value }
        #expect(h.logs.contains(.cancelled(id: a.id, reason: .deleted)))
        #expect(await eventually { await h.store.cached(b.id) != nil })
        #expect(h.reads == [1, 2])
        #expect(await h.store.cached(a.id) == nil)
    }

    @Test func deletingEvictsACachedMap() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        _ = try await h.store.map(for: a)
        await h.send(.deleted, a)
        #expect(await h.store.cached(a.id) == nil)
        #expect(!h.logs.contains(.cancelled(id: a.id, reason: .deleted)))
    }

    @Test func deletingAQueuedReadFailsItsWaitersWithoutReading() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let first = try h.capture(width: 1)
        let a = try h.capture(width: 2)
        await h.send(.created, first)
        #expect(await eventually { gate.waiting == 1 })
        let waiter = h.mapTask(a)
        #expect(await eventually { await h.store.waiters(a.id) == 1 })
        await h.send(.deleted, a)
        await #expect(throws: TextMapError.captureGone(a.id)) { try await waiter.value }
        gate.open()
        try await Task.sleep(for: .milliseconds(20))
        #expect(h.reads == [1])
    }

    @Test func editingCancelsEvictsAndMovesTheWaitersToANewRead() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let waiter = h.mapTask(a)
        #expect(await eventually { gate.waiting == 1 })
        try h.put(a.fileURL, width: 1)
        await h.send(.edited, a)
        let result = try await waiter.value
        #expect(h.logs.contains(.cancelled(id: a.id, reason: .edited)))
        #expect(result.key.fingerprint == (try await h.files.info(of: a.fileURL)).fingerprint)
        #expect(h.reads == [1, 1])
    }

    @Test func editingACachedCaptureEvictsAndRereadsInTheBackground() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        let old = try await h.store.map(for: a)
        try h.put(a.fileURL, width: 1)
        await h.send(.edited, a)
        #expect(await eventually { await h.store.cached(a.id).map { $0 != old } ?? false })
        #expect(h.reads == [1, 1])
    }

    @Test func aMoveMidReadRestartsAtTheNewURLWithTheSameWaiters() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let waiter = h.mapTask(a)
        #expect(await eventually { gate.waiting == 1 })
        let moved = try await h.moved(a, to: "a")
        let result = try await waiter.value
        #expect(h.logs.contains(.cancelled(id: a.id, reason: .moved)))
        #expect(h.files.calls.map(\.url) == [a.fileURL, moved.fileURL])
        #expect(result.key.fingerprint == (try await h.files.info(of: moved.fileURL)).fingerprint)
        #expect(h.logs.contains { if case .read(a.id, _, _, _, _, _, _, .demand) = $0 { true } else { false } })
    }

    @Test func theStripCheckThrowsWhenTheMirrorsURLMoved() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        await h.send(.created, a)
        await #expect(throws: CaptureTextMaps.Moved.self) {
            try await h.store.checkURL(a.id, URL(fileURLWithPath: "/elsewhere.png"))
        }
        try await h.store.checkURL(a.id, a.fileURL)
    }

    // MARK: Q6: the fingerprint after the read.

    @Test func aFileChangedUnderTheReadIsReadOnceMore() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        let changes = Mutex(0)
        let replacement = h.fingerprint()
        h.files.beforePixels = { files, url, _ in
            guard
                changes.withLock({
                    $0 += 1; return $0
                }) == 1
            else { return }
            files.set(
                url, image: try! PixelBuffer(width: 1, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0)),
                fingerprint: replacement)
        }
        let result = try await h.store.map(for: a)
        #expect(result.key.fingerprint == replacement)
        #expect(h.reads == [1, 1])
        #expect(h.logs.filter { $0 == .dropped(id: a.id, reason: .changed) }.count == 1)
    }

    @Test func aFileThatKeepsChangingFailsChangedWhileReading() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        let counter = Mutex(Int64(1000))
        h.files.beforePixels = { files, url, _ in
            let n = counter.withLock {
                $0 += 1; return $0
            }
            files.set(
                url, image: try! PixelBuffer(width: 1, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0)),
                fingerprint: FileFingerprint(size: n, modified: Date()))
        }
        await #expect(throws: TextMapError.changedWhileReading(a.id)) { try await h.store.map(for: a) }
        #expect(h.reads == [1, 1])
        #expect(h.logs.filter { $0 == .dropped(id: a.id, reason: .changed) }.count == 2)
        #expect(await h.store.cached(a.id) == nil)
    }

    // MARK: Q7: failures aren't cached; empty maps are.

    @Test func failuresAreNotCached() async throws {
        let h = StoreHarness(steps: [.failure("vision broke")])
        let a = try h.capture(width: 1)
        let expected = TextMapError.recognitionFailed(String(describing: FakeFailure("vision broke")))
        await #expect(throws: expected) { try await h.store.map(for: a) }
        #expect(h.logs.contains(.failed(id: a.id, error: expected)))
        #expect(await h.store.cached(a.id) == nil)
        _ = try await h.store.map(for: a)
        #expect(h.reads == [1, 1])
    }

    @Test func aMissingFileFailsUnreadable() async throws {
        let h = StoreHarness()
        var a = try h.capture(width: 1)
        a.fileURL = URL(fileURLWithPath: "/nowhere.png")
        await #expect(throws: TextMapError.unreadable(a.fileURL)) { try await h.store.map(for: a) }
    }

    @Test func emptyMapsAreCached() async throws {
        let h = StoreHarness(fallback: .lines([]))
        let a = try h.capture(width: 1)
        #expect(try await h.store.map(for: a).map.isEmpty)
        #expect(try await h.store.map(for: a).map.isEmpty)
        #expect(h.reads == [1])
    }

    @Test func aHangingReadTimesOut() async throws {
        let h = StoreHarness(steps: [.hang])
        let a = try h.capture(width: 1)
        let waiter = h.mapTask(a)
        #expect(await eventually { h.clock.sleepers == 1 })
        h.clock.advance(by: .seconds(10))
        await #expect(throws: TextMapError.timedOut(strip: 0)) { try await waiter.value }
        #expect(h.logs.contains(.failed(id: a.id, error: .timedOut(strip: 0))))
    }

    // MARK: Q8: the LRU.

    @Test func theCacheHoldsCapacityMapsAndAHitRefreshes() async throws {
        let h = StoreHarness(capacity: 2)
        let a = try h.capture(width: 1)
        let b = try h.capture(width: 2)
        let c = try h.capture(width: 3)
        _ = try await h.store.map(for: a)
        _ = try await h.store.map(for: b)
        _ = try await h.store.map(for: a)  // a hit: b is now the oldest
        _ = try await h.store.map(for: c)
        #expect(await h.store.cached(a.id) != nil)
        #expect(await h.store.cached(b.id) == nil)
        #expect(await h.store.cached(c.id) != nil)
        #expect(h.reads == [1, 2, 3])
    }

    // MARK: isCurrent, logs, waiter cancellation.

    @Test func isCurrentFollowsTheFile() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        let result = try await h.store.map(for: a)
        #expect(await h.store.isCurrent(result.key))
        try h.put(a.fileURL, width: 1)
        #expect(await !h.store.isCurrent(result.key))
        await h.send(.deleted, a)
        #expect(await !h.store.isCurrent(result.key))
    }

    @Test func aStoredReadIsLoggedWithItsPriority() async throws {
        let h = StoreHarness()
        let a = try h.capture(width: 7, height: 9)
        await h.send(.created, a)
        #expect(await eventually { await h.store.cached(a.id) != nil })
        #expect(h.logs.count == 1)
        guard case .read(let id, 7, 9, 2, 1, 1, _, .background)? = h.logs.first else {
            Issue.record("unexpected log \(h.logs)")
            return
        }
        #expect(id == a.id)
    }

    @Test func aCancelledWaiterLeavesTheReadToTheOthers() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        let leaving = h.mapTask(a)
        let staying = h.mapTask(a)
        #expect(await eventually { await h.store.waiters(a.id) == 2 })
        leaving.cancel()
        await #expect(throws: CancellationError.self) { try await leaving.value }
        #expect(await eventually { await h.store.waiters(a.id) == 1 })
        gate.open()
        _ = try await staying.value
        #expect(h.reads == [1])
    }

    @Test func aCancelledOnlyWaiterOfAQueuedDemandReadDropsIt() async throws {
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let first = try h.capture(width: 1)
        let a = try h.capture(width: 2)
        await h.send(.created, first)
        #expect(await eventually { gate.waiting == 1 })
        let waiter = h.mapTask(a)
        #expect(await eventually { await h.store.waiters(a.id) == 1 })
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        gate.open()
        try await Task.sleep(for: .milliseconds(20))
        #expect(h.reads == [1])
    }

    // MARK: Slice 3 review

    @Test func aCancelledReadKeepsTheSlotUntilItsRecogniserReturns() async throws {
        // I2: three edits during a read whose recogniser ignores cancellation must not stack recogniser calls.
        let recogniser = OverlapCountingReader()
        let files = FakeImageFileReader()
        let store = CaptureTextMaps(
            reader: TextMapReader(reader: recogniser, files: files, clock: ManualClock()), files: files, log: { _ in })
        let h = StoreHarness()
        let a = try h.capture(width: 1)
        try files.set(
            a.fileURL, image: PixelBuffer(width: 1, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0)),
            fingerprint: h.fingerprint())
        await store.handle(CaptureEvent(change: .created, item: a, origin: "test"))
        #expect(await eventually { recogniser.calls == 1 })
        for _ in 0..<3 {
            try files.set(
                a.fileURL, image: PixelBuffer(width: 1, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0)),
                fingerprint: h.fingerprint())
            await store.handle(CaptureEvent(change: .edited, item: a, origin: "editor"))
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(recogniser.peak == 1)
        recogniser.release()
        #expect(await eventually { await store.cached(a.id) != nil })
        #expect(recogniser.peak == 1)
    }

    @Test func aMoveOfAnUnreadCaptureQueuesABackgroundRead() async throws {
        // M1: the read failed because the file was renamed before its event arrived; the event reads it again.
        let h = StoreHarness()
        var a = try h.capture(width: 1)
        let realURL = a.fileURL
        a.fileURL = URL(fileURLWithPath: "/captures/not-yet-there.png")
        await h.send(.created, a)
        let failed = TextLogLine.failed(id: a.id, error: .unreadable(a.fileURL))
        #expect(await eventually { h.logs.contains(failed) })
        a.fileURL = realURL
        await h.send(.moved, a)
        let id = a.id
        #expect(await eventually { await h.store.cached(id) != nil })
    }

    @Test func aJobWithNoWaitersLeftIsReadAgainInTheBackground() async throws {
        // M2: the waiter of a running demand read leaves, then an edit requeues it: nobody waits, so background.
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let a = try h.capture(width: 1)
        await h.send(.created, a)  // known to the mirror
        #expect(await eventually { gate.waiting == 1 })
        let waiter = h.mapTask(a)
        #expect(await eventually { await h.store.waiters(a.id) == 1 })
        waiter.cancel()
        _ = try? await waiter.value
        try h.put(a.fileURL, width: 1)
        await h.send(.edited, a)
        #expect(await eventually { await h.store.cached(a.id) != nil })
        #expect(h.logs.contains { if case .read(a.id, _, _, _, _, _, _, .background) = $0 { true } else { false } })
    }

    @Test func anEditedQueuedBackgroundReadBecomesTheNewest() async throws {
        // M3: requeue makes an edited background job the newest, so it is read before an older-created one.
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let first = try h.capture(width: 1)
        let b = try h.capture(width: 2)
        let c = try h.capture(width: 3)
        await h.send(.created, first)
        #expect(await eventually { gate.waiting == 1 })
        await h.send(.created, b)
        await h.send(.created, c)
        try h.put(b.fileURL, width: 2)
        await h.send(.edited, b)
        gate.open()
        #expect(await eventually { h.reads.count == 3 })
        #expect(h.reads == [1, 2, 3])
    }

    @Test func anEditResetsTheChangedFileRerun() async throws {
        // M3: after a Q6 mismatch, an edit starts afresh, so the next mismatch is read once more instead of failing.
        let gate = FakeGate()
        let h = StoreHarness(steps: [.lines([]), .gate(gate, [])])
        let a = try h.capture(width: 1)
        let changes = Mutex(0)
        h.files.beforePixels = { files, url, _ in
            guard
                changes.withLock({
                    $0 += 1; return $0
                }) <= 3
            else { return }
            files.set(
                url, image: try! PixelBuffer(width: 1, height: 10, fill: RGBA8(red: 0, green: 0, blue: 0)),
                fingerprint: FileFingerprint(size: Int64(100 + changes.withLock { $0 }), modified: Date()))
        }
        let waiter = h.mapTask(a)
        #expect(await eventually { gate.waiting == 1 })  // the Q6 rerun, held
        await h.send(.edited, a)  // cancels it; the edited read changes the file once more, then once again clean
        let result = try await waiter.value
        #expect(result.key.id == a.id)
        #expect(h.reads.count == 4)
    }

    @Test func aWaiterThatLeavesAPromotedReadReturnsItToTheBackground() async throws {
        // M3, P12: a background read promoted by a waiter goes back to the background when the waiter leaves.
        let gate = FakeGate()
        let h = StoreHarness(steps: [.gate(gate, [])])
        let first = try h.capture(width: 1)
        let b = try h.capture(width: 2)
        await h.send(.created, first)
        #expect(await eventually { gate.waiting == 1 })
        await h.send(.created, b)
        let waiter = h.mapTask(b)
        #expect(await eventually { await h.store.waiters(b.id) == 1 })
        waiter.cancel()
        _ = try? await waiter.value
        gate.open()
        #expect(await eventually { await h.store.cached(b.id) != nil })
        #expect(h.logs.contains { if case .read(b.id, _, _, _, _, _, _, .background) = $0 { true } else { false } })
    }
}

/// Ignores cancellation until released, and counts how many calls ran at once.
final class OverlapCountingReader: TextReader, Sendable {
    private struct State {
        var running = 0
        var peak = 0
        var calls = 0
    }

    private let state = Mutex(State())
    private let latch = ReleaseLatch()
    var peak: Int { state.withLock { $0.peak } }
    var calls: Int { state.withLock { $0.calls } }
    func release() { latch.release() }

    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] {
        state.withLock {
            $0.calls += 1
            $0.running += 1
            $0.peak = max($0.peak, $0.running)
        }
        defer { state.withLock { $0.running -= 1 } }
        await latch.wait()  // suspends, never spins, even once cancelled
        return []
    }
}
