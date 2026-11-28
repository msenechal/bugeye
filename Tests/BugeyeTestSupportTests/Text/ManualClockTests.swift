import BugeyeTestSupport
import Testing

@Suite struct ManualClockTests {
    @Test func aSleeperWakesOnlyOnceAdvancedPastItsDeadline() async throws {
        let clock = ManualClock()
        let task = Task { try await clock.sleep(for: .seconds(10)) }
        while clock.sleepers == 0 { await Task.yield() }
        clock.advance(by: .seconds(9))
        #expect(clock.sleepers == 1)
        clock.advance(by: .seconds(1))
        try await task.value
        #expect(clock.sleepers == 0)
        #expect(clock.now == ManualClock.Instant(offset: .seconds(10)))
    }

    @Test func aPastDeadlineReturnsAtOnce() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(5))
        try await clock.sleep(until: ManualClock.Instant(offset: .seconds(4)), tolerance: nil)
        #expect(clock.sleepers == 0)
    }

    @Test func cancellingASleeperThrows() async {
        let clock = ManualClock()
        let task = Task { try await clock.sleep(for: .seconds(10)) }
        while clock.sleepers == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.sleepers == 0)
    }

    @Test func instantsMeasureDurations() {
        let a = ManualClock.Instant(offset: .seconds(1))
        #expect(a.advanced(by: .seconds(2)) == ManualClock.Instant(offset: .seconds(3)))
        #expect(a.duration(to: ManualClock.Instant(offset: .seconds(4))) == .seconds(3))
        #expect(a < ManualClock.Instant(offset: .seconds(2)))
    }
}
