import RecordingCore
import Testing

@Suite struct RecordingClockTests {
    @Test func nothingMapsBeforeTheFirstFrame() {
        var clock = RecordingClock()
        #expect(clock.outputTime(for: 10) == nil)
        #expect(clock.elapsed(at: 10) == 0)
        clock.begin(at: 100)
        #expect(clock.outputTime(for: 99.999) == nil)
        #expect(clock.outputTime(for: 100) == 0)
        #expect(clock.outputTime(for: 101.5) == 1.5)
        #expect(clock.elapsed(at: 103) == 3)
    }

    @Test func pausedSpansAreCutAndSamplesCapturedInAPauseAreDropped() {
        var clock = RecordingClock()
        clock.begin(at: 100)
        clock.pause(at: 105)
        #expect(clock.isPaused)
        // Captured inside the pause, arriving any time later: dropped.
        #expect(clock.outputTime(for: 106) == nil)
        // Captured before the pause point: kept.
        #expect(clock.outputTime(for: 104.5) == 4.5)
        #expect(clock.elapsed(at: 108) == 5)
        clock.resume(at: 110)
        #expect(!clock.isPaused)
        #expect(clock.outputTime(for: 107) == nil)
        #expect(clock.outputTime(for: 110) == 5)
        #expect(clock.outputTime(for: 112) == 7)
        #expect(clock.elapsed(at: 112) == 7)
        // Still right for a sample captured before the pause and handled after the resume.
        #expect(clock.outputTime(for: 103) == 3)
    }

    @Test func severalPausesAddUp() {
        var clock = RecordingClock()
        clock.begin(at: 0)
        clock.pause(at: 2)
        clock.resume(at: 5)
        clock.pause(at: 6)
        clock.resume(at: 10)
        #expect(clock.outputTime(for: 11) == 4)
        #expect(clock.elapsed(at: 11) == 4)
        #expect(clock.milliseconds(for: 11.0015) == 4001)
        #expect(clock.milliseconds(for: 7) == nil)
    }

    @Test func redundantPauseAndResumeAreNoOps() {
        var clock = RecordingClock()
        clock.pause(at: 1)
        #expect(!clock.isPaused)
        clock.begin(at: 10)
        clock.resume(at: 11)
        clock.pause(at: 12)
        clock.pause(at: 13)
        clock.resume(at: 14)
        clock.resume(at: 15)
        #expect(clock.outputTime(for: 16) == 4)
        // A second begin doesn't move the origin.
        clock.begin(at: 20)
        #expect(clock.outputTime(for: 16) == 4)
    }

    @Test func aResumeBeforeThePauseStampIsClamped() {
        var clock = RecordingClock()
        clock.begin(at: 0)
        clock.pause(at: 5)
        clock.resume(at: 4)
        #expect(clock.outputTime(for: 6) == 6)
    }
}
