import BugeyeCore
import BugeyeFeatures
import Foundation
import RecordingCore
import Testing

/// Findings of the final review of PR #13.
@Suite struct RecordingFlowReviewTests {
    typealias F = FlowTesting
    let s1 = SessionID(1)

    /// idle → recording for session 1, without `takeStarted`.
    private func liveFlow(options: RecordingOptions = RecordingOptions()) -> RecordingFlow {
        var flow = RecordingFlow(stopKey: F.stopKey)
        F.drive(
            &flow,
            [
                F.toggle(), F.selected(1, options: options), .record(s1, freeBytes: F.plenty), .recorderReady(s1),
                .countdownTick(s1), .countdownTick(s1), .countdownTick(s1),
            ])
        return flow
    }

    private func elapsed(_ effects: [RecordingEffect]?) -> String? {
        for effect in effects ?? [] {
            if case .statusItem(let item?) = effect {
                switch item.badge {
                case .recording(let e), .paused(let e): return e
                case .finishing: return nil
                }
            }
        }
        return nil
    }

    /// C1: a Pause before the first frame keeps the take's clock and start date.
    @Test func aPauseBeforeTheFirstFrameKeepsTheClock() {
        var flow = liveFlow()
        _ = flow.next(.pause(s1, hostNow: 99))
        let date = Date(timeIntervalSince1970: 42)
        #expect(flow.next(.takeStarted(s1, hostTime: 100, date: date)) != nil)
        #expect(elapsed(flow.next(.tick(s1, hostNow: 150))) == "00:00")
        _ = flow.next(.resume(s1, hostNow: 160))
        #expect(elapsed(flow.next(.tick(s1, hostNow: 180))) == "00:20")
        #expect(flow.next(.restart(s1, hostNow: 181)) == [.confirm(s1, .restart)])
        _ = flow.next(.declined(s1, .restart))
        _ = flow.next(F.toggle())
        _ = flow.next(.stopped(s1, .movie(F.movie, duration: 21)))
        #expect(flow.next(.converted(s1, F.movie, isMov: false)) == [.deliver(s1, F.movie, date: date, duration: 21)])
    }

    /// I1: losing Screen Recording mid-take stops it and shows Capture's alert, not an invented notice.
    @Test func aPermissionFailureWhileRecordingShowsTheAlert() {
        var flow = F.recordingFlow()
        let effects = flow.next(.recorderFailed(s1, .userDeclined)) ?? []
        #expect(effects.contains(.screenPermissionAlert))
        #expect(effects.contains(.stopRecorder(s1)))
        _ = flow.next(.stopped(s1, .movie(F.movie, duration: 2)))
        _ = flow.next(.converted(s1, F.movie, isMov: false))
        let done = flow.next(.delivered(s1, nil)) ?? []
        #expect(!done.contains { if case .notify = $0 { true } else { false } })
    }

    /// I2: the bubble's size can change by double-click from the countdown to the end of the take.
    @Test func theBubbleSizeChangesWhileRecording() {
        var flow = F.recordingFlow(options: RecordingOptions(camera: true))
        #expect(
            flow.next(.option(s1, .bubbleSize(.large)))
                == [
                    .persist(key: "recording.bubbleSize", value: .string("large")),
                    .bubble(BubbleWish(cameraDevice: "", size: .large)),
                ])
        // Only the size: other options can't change once the bar is closed.
        #expect(flow.next(.option(s1, .mic(true))) == nil)
        // The new size survives a Restart.
        let restarted = flow.next(.restart(s1, hostNow: 101)) ?? []
        #expect(
            restarted.contains(
                .prepareRecorder(
                    SessionID(2),
                    RecorderRequest(target: .area(F.area), options: RecordingOptions(camera: true, bubbleSize: .large)))
            ))
        var counting = RecordingFlow()
        F.drive(
            &counting,
            [F.toggle(), F.selected(1, options: RecordingOptions(camera: true)), .record(s1, freeBytes: F.plenty)])
        #expect(
            counting.next(.option(s1, .bubbleSize(.small)))?.last == .bubble(BubbleWish(cameraDevice: "", size: .small))
        )
    }

    /// I3: a confirmation survives a pause; a second request doesn't stack alerts; leaving the take dismisses it.
    @Test func theConfirmationBookkeeping() {
        var flow = F.recordingFlow()
        #expect(flow.next(.restart(s1, hostNow: 120)) == [.confirm(s1, .restart)])
        _ = flow.next(.pause(s1, hostNow: 121))
        #expect(flow.next(.discard(s1, hostNow: 122)) == nil)
        let restarted = flow.next(.confirmed(s1, .restart)) ?? []
        #expect(restarted.contains(.cancelRecorder(s1)))

        var stopping = F.recordingFlow()
        _ = stopping.next(.discard(s1, hostNow: 130))
        let stop = stopping.next(F.toggle()) ?? []
        #expect(stop.first == .dismissConfirm(s1))
        #expect(stopping.next(.confirmed(s1, .discard)) == nil)
    }

    /// I4: a recorder that becomes ready for a session that moved on is always cancelled.
    @Test func aLateReadyIsCancelled() {
        var flow = RecordingFlow()
        F.drive(&flow, [F.toggle(), F.selected(1), .record(s1, freeBytes: F.plenty), .cancel(s1)])
        #expect(flow.next(.recorderReady(s1)) == [.cancelRecorder(s1)])
        // Never for a session that was never prepared.
        #expect(flow.next(.recorderReady(SessionID(9))) == nil)
    }

    /// M2: a camera loss with Cam off says nothing.
    @Test func aCameraLossWithCamOffIsSilent() {
        var flow = F.recordingFlow()
        #expect(flow.next(.cameraUnavailable(s1)) == [])
    }

    /// M7: the table rows the first tests missed.
    @Test func quitFromEachSetUpStateAllowsOnce() {
        for steps in 1...3 {
            var flow = RecordingFlow()
            let events: [RecordingEvent] = [
                F.toggle(), F.selected(1), .record(s1, freeBytes: F.plenty), .countdownTick(s1),
                .countdownTick(s1), .countdownTick(s1),
            ]
            F.drive(&flow, Array(events.prefix(steps == 3 ? 6 : steps + 1)))
            let effects = flow.next(.quitRequested) ?? []
            #expect(effects.filter { $0 == .allowQuit }.count == 1)
            #expect(flow.state == .idle)
            if steps == 3 {
                // From starting: the recorder is cancelled and `recording` ends (V21).
                #expect(effects.contains(.cancelRecorder(s1)))
                #expect(effects.contains(.activity(.end(.recording))))
            }
        }
    }

    @Test func targetGoneInEachSetUpState() {
        var configuring = RecordingFlow()
        F.drive(&configuring, [F.toggle(), F.selected(1)])
        #expect(configuring.next(.targetGone(s1))?.contains(.closeBar) == true)
        var counting = RecordingFlow()
        F.drive(&counting, [F.toggle(), F.selected(1), .record(s1, freeBytes: F.plenty)])
        #expect(counting.next(.targetGone(s1))?.contains(.cancelRecorder(s1)) == true)
        #expect(counting.state == .idle)
    }

    @Test func restartFromPaused() {
        var flow = F.recordingFlow()
        _ = flow.next(.pause(s1, hostNow: 101))
        let effects = flow.next(.restart(s1, hostNow: 102)) ?? []
        #expect(effects.contains(.cancelRecorder(s1)))
        #expect(flow.state.session == SessionID(2))
    }
}

@Suite struct RecordingStringsReviewTests {
    /// M1: any final punctuation counts; an empty error leaves no stray space.
    @Test func sentences() {
        #expect(RecordingStrings.sentence("Huh?") == "Huh?")
        #expect(RecordingStrings.sentence("Stop!") == "Stop!")
        #expect(RecordingStrings.sentence("Wait…") == "Wait…")
        #expect(RecordingStrings.Notice.stopped(error: "").body == "What was recorded has been kept.")
    }
}
