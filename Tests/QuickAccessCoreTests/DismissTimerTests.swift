import QuickAccessCore
import Testing

@Suite struct DismissTimerTests {
    @Test func expiresExactlyAtItsDuration() {
        let timer = DismissTimer(duration: 5, startedAt: 100)
        #expect(timer.isRunning)
        #expect(!timer.isExpired(at: 104.9))
        #expect(timer.isExpired(at: 105))
    }

    @Test func pauseBanksTheElapsedTime() {
        var timer = DismissTimer(duration: 5, startedAt: 0)
        timer.pause(at: 2)
        #expect(!timer.isRunning)
        #expect(timer.remaining == 3)
        #expect(!timer.isExpired(at: 1000))
        timer.resume(at: 10)
        #expect(!timer.isExpired(at: 12.9))
        #expect(timer.isExpired(at: 13))
    }

    @Test func banksAcrossSeveralPauses() {
        var timer = DismissTimer(duration: 10, startedAt: 0)
        timer.pause(at: 3)
        timer.resume(at: 50)
        timer.pause(at: 54)
        timer.resume(at: 100)
        #expect(timer.remaining == 3)
        #expect(!timer.isExpired(at: 102.9))
        #expect(timer.isExpired(at: 103))
    }

    @Test func pauseAndResumeAreIdempotent() {
        var timer = DismissTimer(duration: 5, startedAt: 0)
        timer.pause(at: 1)
        timer.pause(at: 3)
        #expect(timer.remaining == 4)
        timer.resume(at: 10)
        timer.resume(at: 12)
        #expect(timer.isExpired(at: 14))
    }

    @Test func restartGivesTheFullDurationAndRuns() {
        var timer = DismissTimer(duration: 5, startedAt: 0)
        timer.pause(at: 4)
        timer.restart(duration: 5, at: 20)
        #expect(timer.isRunning)
        #expect(!timer.isExpired(at: 24.9))
        #expect(timer.isExpired(at: 25))
    }

    @Test func nilDurationNeverExpires() {
        var timer = DismissTimer(duration: nil, startedAt: 0)
        #expect(!timer.isExpired(at: 1_000_000))
        timer.pause(at: 5)
        timer.resume(at: 6)
        #expect(!timer.isExpired(at: 1_000_000))
        #expect(timer.remaining == nil)
    }
}

@Suite struct DismissTimerPausedTests {
    /// Final review M1: a timer that ran out between two ticks and was then paused (hover, editing, a selection)
    /// isn't expired while paused, so the thumbnail never leaves under the pointer or in the editor.
    @Test func aPausedTimerIsNeverExpired() {
        var timer = DismissTimer(duration: 5, startedAt: 0)
        timer.pause(at: 5.3)
        #expect(!timer.isExpired(at: 100))
        timer.resume(at: 100)
        #expect(timer.isExpired(at: 100))
    }
}
