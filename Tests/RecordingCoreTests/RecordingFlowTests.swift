import BugeyeCore
import BugeyeFeatures
import Foundation
import RecordingCore
import Testing

enum FlowTesting {
    static let area = StoredArea(
        display: DisplayID(1), rect: Rect2D(x: 10, y: 20, width: 640, height: 360),
        displaySize: Size2D(width: 1512, height: 982))
    static let granted = RecordingPermissions(microphone: .granted, camera: .granted, accessibility: .granted)
    static let devices = CaptureDeviceList(microphones: ["mic"], cameras: ["cam"])
    static let plenty: Int64 = 50_000_000_000
    static let stopKey = KeyCombo("5", [.shift, .command])
    static let movie = URL(fileURLWithPath: "/tmp/Take-1.mov")

    static func toggle(permitted: Bool = true, allows: Bool = true) -> RecordingEvent {
        .toggle(screenPermitted: permitted, activityAllows: allows, lastArea: area)
    }

    static func selected(
        _ s: Int, _ result: SelectionResult = .area(area), options: RecordingOptions = RecordingOptions(),
        permissions: RecordingPermissions = granted, devices: CaptureDeviceList = devices
    ) -> RecordingEvent {
        .selected(SessionID(s), result, options: options, permissions: permissions, devices: devices)
    }

    /// Drives a flow through `events`, requiring each to be taken.
    @discardableResult
    static func drive(_ flow: inout RecordingFlow, _ events: [RecordingEvent]) -> [[RecordingEffect]] {
        events.map { event in
            guard let effects = flow.next(event) else {
                Issue.record("not taken: \(event) in \(flow.state)")
                return []
            }
            return effects
        }
    }

    /// idle → recording for session 1 (recorder ready before the countdown ends).
    static func recordingFlow(options: RecordingOptions = RecordingOptions()) -> RecordingFlow {
        var flow = RecordingFlow(stopKey: stopKey)
        drive(
            &flow,
            [
                toggle(), selected(1, options: options), .record(SessionID(1), freeBytes: plenty),
                .recorderReady(SessionID(1)), .countdownTick(SessionID(1)), .countdownTick(SessionID(1)),
                .countdownTick(SessionID(1)),
                .takeStarted(SessionID(1), hostTime: 100, date: Date(timeIntervalSince1970: 0)),
            ])
        return flow
    }
}

@Suite struct RecordingFlowTableTests {
    typealias F = FlowTesting
    let s1 = SessionID(1)

    @Test func aToggleTheActivityRefusesIsLoggedAndDropped() {
        var flow = RecordingFlow()
        #expect(flow.next(F.toggle(allows: false)) == [.log("busy: dropped toggle")])
        #expect(flow.state == .idle)
    }

    @Test func withoutScreenRecordingCapturesAlertShows() {
        var flow = RecordingFlow()
        #expect(flow.next(F.toggle(permitted: false)) == [.screenPermissionAlert])
        #expect(flow.state == .idle)
    }

    @Test func aToggleOpensTheRecordingSelection() {
        var flow = RecordingFlow()
        let effects = flow.next(F.toggle())
        let request = SelectionRequest(
            purpose: .recording,
            hint: "Drag an area · Click to record this display · Space: pick a window · Esc to cancel",
            clickSelectsDisplay: true, windowNeedsDisplayCentre: true, lastArea: F.area)
        #expect(effects == [.activity(.begin(.recordingSetup)), .selection(request), .log("begin 1")])
        #expect(flow.state == .selecting(s1))
    }

    @Test(arguments: [SelectionResult.cancelled, .busy])
    func aCancelledSelectionEndsSetUp(result: SelectionResult) {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        #expect(flow.next(F.selected(1, result)) == [.activity(.end(.recordingSetup)), .log("finish 1")])
        #expect(flow.state == .idle)
    }

    @Test func anAreaIsStoredAndTheBarOpensWithEffectiveOptions() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        let options = RecordingOptions(mic: true, keys: true, camera: true)
        let permissions = RecordingPermissions(microphone: .denied, camera: .granted, accessibility: .granted)
        let effects = flow.next(F.selected(1, options: options, permissions: permissions))
        var effective = options
        effective.mic = false
        #expect(
            effects == [
                .storeLastArea(F.area), .showBorder(.area(F.area), .dashed),
                .showBar(options: options, effective: effective),
                .bubble(BubbleWish(cameraDevice: "", size: .medium)),
            ])
    }

    @Test func aWindowIsTargetedAndNotStoredAsTheLastArea() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        let frame = Rect2D(x: 0, y: 0, width: 800, height: 600)
        let effects = flow.next(F.selected(1, .window(WindowID(9), display: DisplayID(2), frame: frame)))
        let target = RecordingTarget.window(WindowID(9), display: DisplayID(2), frame: frame)
        #expect(
            effects == [
                .showBorder(target, .dashed),
                .showBar(options: RecordingOptions(), effective: RecordingOptions()),
            ])
    }

    @Test func anOptionPersistsOneKeyAsksOnFirstUseAndUpdatesTheBar() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        let undetermined = RecordingPermissions(accessibility: .granted)
        _ = flow.next(F.selected(1, permissions: undetermined))
        let effects = flow.next(.option(s1, .mic(true)))
        #expect(
            effects == [
                .persist(key: "recording.mic", value: .bool(true)), .requestPermission(.microphone),
                .updateBar(options: RecordingOptions(mic: true), effective: RecordingOptions()),
            ])
        // The answer arrives: the mic becomes effective.
        #expect(
            flow.next(.permissionAnswered(s1, .microphone, .granted))
                == [.updateBar(options: RecordingOptions(mic: true), effective: RecordingOptions(mic: true))])
        // Keys without Accessibility asks every time it is turned on.
        var other = RecordingFlow()
        _ = other.next(F.toggle())
        _ = other.next(F.selected(1, permissions: RecordingPermissions(accessibility: .denied)))
        #expect(other.next(.option(s1, .keys(true)))?.contains(.requestPermission(.accessibility)) == true)
    }

    @Test func turningCamOnAndChangingItsSizeUpdatesTheBubble() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        _ = flow.next(F.selected(1))
        #expect(flow.next(.option(s1, .camera(true)))?.last == .bubble(BubbleWish(cameraDevice: "", size: .medium)))
        #expect(
            flow.next(.option(s1, .bubbleSize(.large)))?.last == .bubble(BubbleWish(cameraDevice: "", size: .large)))
        #expect(
            flow.next(.option(s1, .clicks(true)))?.contains { if case .bubble = $0 { true } else { false } } == false)
        #expect(flow.next(.option(s1, .camera(false)))?.last == .bubble(nil))
    }

    @Test func recordWithLessThan1GBKeepsTheBarAndSaysSo() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        _ = flow.next(F.selected(1))
        #expect(
            flow.next(.record(s1, freeBytes: 999_999_999))
                == [
                    .notify(
                        RecordingNotice(
                            title: "Not enough disk space", body: "Free at least 1 GB to start a recording."))
                ])
        if case .configuring = flow.state {} else { Issue.record("left configuring") }
    }

    @Test func recordStartsTheCountdownAndPreparesTheRecorderWithEffectiveOptions() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        let options = RecordingOptions(mic: true, keys: true, camera: true)
        _ = flow.next(F.selected(1, options: options, permissions: RecordingPermissions()))
        let effects = flow.next(.record(s1, freeBytes: F.plenty))
        #expect(
            effects == [
                .closeBar, .countdown(3),
                .prepareRecorder(s1, RecorderRequest(target: .area(F.area), options: RecordingOptions())),
            ])
    }

    @Test func theCountdownGoesLiveOnlyOnceTheRecorderIsReady() {
        var flow = RecordingFlow(stopKey: F.stopKey)
        F.drive(
            &flow,
            [F.toggle(), F.selected(1, options: RecordingOptions(clicks: true)), .record(s1, freeBytes: F.plenty)])
        #expect(flow.next(.countdownTick(s1)) == [.countdown(2)])
        #expect(flow.next(.countdownTick(s1)) == [.countdown(1)])
        #expect(
            flow.next(.countdownTick(s1))
                == [.closeCountdown, .activity(.end(.recordingSetup)), .activity(.begin(.recording))])
        #expect(flow.state == .starting(s1, .area(F.area), RecordingOptions(clicks: true)))
        let live = flow.next(.recorderReady(s1)) ?? []
        #expect(
            Array(live.prefix(5)) == [
                .beginTake(s1), .showBorder(.area(F.area), .recording),
                .overlays(start: true, clicks: true, keys: false, showAllKeys: false), .inputMonitor(start: true),
                .timeline(.start),
            ])
        #expect(live[5] == .ticker(start: true))
        guard case .statusItem(let item?) = live[6] else {
            Issue.record("no override")
            return
        }
        #expect(item.badge == .recording(elapsed: "00:00"))
        #expect(item.accessibilityLabel == "Recording, 00:00")
        #expect(item.menu.map(\.title) == ["Pause", "Stop", "", "Restart", "Discard"])
        #expect(item.menu[1].shownKey == F.stopKey)
    }

    @Test func noTimelineWhenTheHiddenKeyIsOff() {
        var other = RecordingFlow()
        F.drive(
            &other,
            [
                F.toggle(), F.selected(1, options: RecordingOptions(timeline: false)), .record(s1, freeBytes: F.plenty),
                .recorderReady(s1), .countdownTick(s1), .countdownTick(s1),
            ])
        #expect(other.next(.countdownTick(s1))?.contains(.timeline(.start)) == false)
    }

    @Test func pauseFreezesTheTimerAndResumeRestartsIt() throws {
        var flow = F.recordingFlow()
        let ticked = flow.next(.tick(s1, hostNow: 107.9))
        guard case .statusItem(let running?) = ticked?.first else { throw Fail() }
        #expect(running.badge == .recording(elapsed: "00:07"))
        let paused = flow.next(.pause(s1, hostNow: 108))
        #expect(paused?.first == .pauseRecorder(s1))
        guard case .statusItem(let item?) = flow.next(.tick(s1, hostNow: 200))?.first else { throw Fail() }
        #expect(item.badge == .paused(elapsed: "00:08"))
        #expect(item.accessibilityLabel == "Recording paused, 00:08")
        #expect(item.menu.first?.title == "Resume")
        #expect(flow.next(.resume(s1, hostNow: 300))?.first == .resumeRecorder(s1))
        guard case .statusItem(let resumed?) = flow.next(.tick(s1, hostNow: 302))?.first else { throw Fail() }
        #expect(resumed.badge == .recording(elapsed: "00:10"))
    }

    @Test func everyTenthTickChecksTheDisk() {
        var flow = F.recordingFlow()
        let checks = (1...20).map { flow.next(.tick(s1, hostNow: 100 + Double($0) / 2))?.contains(.diskCheck) == true }
        #expect(checks.enumerated().filter(\.element).map(\.offset) == [9, 19])
        #expect(flow.next(.diskChecked(s1, freeBytes: 300_000_000)) == [])
        let stop = flow.next(.diskChecked(s1, freeBytes: 299_999_999))
        #expect(stop?.contains(.stopRecorder(s1)) == true)
        #expect(
            flow.state
                == .finishing(
                    s1, .stopping,
                    notice: RecordingNotice(
                        title: "Recording stopped: disk almost full", body: "What was recorded has been kept."),
                    startedAt: Date(timeIntervalSince1970: 0), duration: nil))
    }

    @Test func restartAndDiscardAskAfter10Seconds() {
        var flow = F.recordingFlow()
        #expect(flow.next(.discard(s1, hostNow: 110.5)) == [.confirm(s1, .discard)])
        #expect(flow.confirming?.kind == .discard)
        #expect(flow.next(.confirmed(s1, .restart)) == nil)
        #expect(flow.next(.declined(s1, .discard)) == [])
        #expect(flow.confirming == nil)
        #expect(flow.next(.confirmed(s1, .discard)) == nil)
        #expect(flow.next(.restart(s1, hostNow: 120)) == [.confirm(s1, .restart)])
        let restarted = flow.next(.confirmed(s1, .restart)) ?? []
        #expect(restarted.contains(.cancelRecorder(s1)))
        #expect(restarted.contains(.timeline(.discard)))
        #expect(
            restarted.contains(
                .prepareRecorder(SessionID(2), RecorderRequest(target: .area(F.area), options: RecordingOptions()))))
        #expect(
            flow.state
                == .countingDown(SessionID(2), .area(F.area), RecordingOptions(), remaining: 3, recorderReady: false))
    }

    @Test func discardUnder10SecondsThrowsTheTakeAwayAtOnce() {
        var flow = F.recordingFlow()
        let effects = flow.next(.discard(s1, hostNow: 105))
        #expect(
            effects == [
                .ticker(start: false), .inputMonitor(start: false), .bubble(nil), .cancelRecorder(s1),
                .timeline(.discard), .closeBorder, .statusItem(nil), .activity(.end(.recording)), .log("finish 1"),
            ])
        #expect(flow.state == .idle)
    }

    @Test func stopConvertsThenDelivers() throws {
        var flow = F.recordingFlow(options: RecordingOptions(keys: true))
        let stop = flow.next(F.toggle()) ?? []
        #expect(
            Array(stop.prefix(4)) == [
                .ticker(start: false), .inputMonitor(start: false),
                .overlays(start: false, clicks: false, keys: true, showAllKeys: false), .bubble(nil),
            ])
        guard case .statusItem(let finishing?) = stop.first(where: { if case .statusItem = $0 { true } else { false } })
        else {
            throw Fail()
        }
        #expect(finishing.badge == .finishing)
        #expect(finishing.accessibilityLabel == "Finishing recording")
        #expect(
            finishing.menu == [
                StatusItemOverride.Entry(id: "recording.finishing", title: "Finishing…", isEnabled: false)
            ])
        #expect(stop.suffix(3) == [.closeBorder, .stopRecorder(s1), .log("stop user")])
        #expect(
            flow.next(.stopped(s1, .movie(F.movie, duration: 30)))
                == [.timeline(.finish), .convert(s1, F.movie, deadline: 75)])
        guard case .statusItem(let progress?)? = flow.next(.conversionProgress(s1, 0.425))?.first else { throw Fail() }
        #expect(progress.menu.first?.title == "Finishing… 42 %")
        let mp4 = URL(fileURLWithPath: "/tmp/Take-1.mp4")
        #expect(
            flow.next(.converted(s1, mp4, isMov: false)) == [
                .deliver(s1, mp4, date: Date(timeIntervalSince1970: 0), duration: 30)
            ])
        #expect(flow.next(.delivered(s1, nil)) == [.statusItem(nil), .activity(.end(.recording)), .log("finish 1")])
        #expect(flow.state == .idle)
    }

    @Test func aMovFallbackSaysSoAndAStopNoticeComesAfterDelivery() {
        var flow = F.recordingFlow()
        _ = flow.next(.recorderFailed(s1, .other("The stream stopped")))
        _ = flow.next(.stopped(s1, .movie(F.movie, duration: 3)))
        #expect(
            flow.next(.converted(s1, F.movie, isMov: true))?.last
                == .notify(
                    RecordingNotice(
                        title: "Recording saved as a QuickTime movie",
                        body:
                            "There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime."
                    )))
        #expect(
            flow.next(.delivered(s1, nil))?.first
                == .notify(
                    RecordingNotice(
                        title: "Recording stopped", body: "The stream stopped. What was recorded has been kept.")))
    }

    @Test func noFramesDiscardsTheTimelineAndSaysNothingWasRecorded() {
        var flow = F.recordingFlow()
        _ = flow.next(F.toggle())
        #expect(
            flow.next(.stopped(s1, .noFrames))
                == [
                    .timeline(.discard),
                    .notify(
                        RecordingNotice(
                            title: "Nothing was recorded", body: "The recording stopped before the first frame.")),
                    .statusItem(nil), .activity(.end(.recording)), .log("finish 1"),
                ])
    }

    @Test func aStartFailureNotifiesOrShowsTheAlert() {
        var flow = RecordingFlow()
        F.drive(&flow, [F.toggle(), F.selected(1), .record(s1, freeBytes: F.plenty)])
        let failed = flow.next(.recorderFailed(s1, .other("No display")))
        #expect(
            failed?.contains(.notify(RecordingNotice(title: "Couldn't start recording", body: "No display."))) == true)
        #expect(failed?.contains(.cancelRecorder(s1)) == true)
        #expect(failed?.contains(.activity(.end(.recordingSetup))) == true)
        var declined = RecordingFlow()
        F.drive(&declined, [F.toggle(), F.selected(1), .record(s1, freeBytes: F.plenty)])
        #expect(declined.next(.recorderFailed(s1, .userDeclined))?.contains(.screenPermissionAlert) == true)
    }

    @Test func aLostCameraTurnsCamOffAndSaysSo() {
        var flow = F.recordingFlow(options: RecordingOptions(camera: true))
        #expect(
            flow.next(.cameraUnavailable(s1))
                == [
                    .bubble(nil), .persist(key: "recording.camera", value: .bool(false)),
                    .notify(
                        RecordingNotice(
                            title: "Camera unavailable (in use by another app?)", body: "Cam has been turned off.")),
                ])
    }

    @Test func quitInIdleIsAllowedAtOnce() {
        var flow = RecordingFlow()
        #expect(flow.next(.quitRequested) == [.allowQuit])
    }

    struct Fail: Error {}
}

/// The named regressions of spec §6 (`design/04` §3).
@Suite struct RecordingFlowRegressionTests {
    typealias F = FlowTesting

    @Test func rapidTogglesLeaveNoStrayRecorder() {
        var flow = RecordingFlow()
        var prepared: [SessionID] = []
        var ended: [SessionID] = []
        func run(_ event: RecordingEvent) {
            for effect in flow.next(event) ?? [] {
                if case .prepareRecorder(let s, _) = effect { prepared.append(s) }
                if case .cancelRecorder(let s) = effect { ended.append(s) }
                if case .stopRecorder(let s) = effect { ended.append(s) }
            }
        }
        for n in 1...5 {
            run(F.toggle())
            run(F.selected(n))
            run(.record(SessionID(n), freeBytes: F.plenty))
            run(F.toggle())
        }
        // Late readiness for every abandoned session.
        for n in 1...5 { run(.recorderReady(SessionID(n))) }
        #expect(prepared == (1...5).map(SessionID.init))
        // Each cancelled at its toggle, and again when its late ready arrives (review I4).
        #expect(ended == prepared + prepared)
        #expect(flow.state == .idle)
    }

    @Test func aStaleFailureCannotStopARestartedTake() {
        var flow = F.recordingFlow()
        _ = flow.next(.restart(SessionID(1), hostNow: 101))
        #expect(flow.next(.recorderFailed(SessionID(1), .other("old"))) == nil)
        #expect(flow.next(.stopped(SessionID(1), .noFrames)) == nil)
        #expect(flow.state.session == SessionID(2))
    }

    @Test func aFailureDuringTheCountdownIsNotMissed() {
        var flow = RecordingFlow()
        F.drive(
            &flow,
            [F.toggle(), F.selected(1), .record(SessionID(1), freeBytes: F.plenty), .countdownTick(SessionID(1))])
        let effects = flow.next(.recorderFailed(SessionID(1), .other("Stream failed")))
        #expect(effects?.contains(.notify(RecordingStrings.Notice.couldNotStart(error: "Stream failed"))) == true)
        #expect(flow.state == .idle)
        #expect(flow.next(.countdownTick(SessionID(1))) == nil)
    }

    @Test func quitWaitsForAFinishingRecording() {
        var flow = F.recordingFlow()
        let s = SessionID(1)
        #expect(flow.next(.quitRequested)?.contains(.allowQuit) == false)
        #expect(flow.quitPending)
        #expect(flow.next(.quitRequested) == [])
        #expect(flow.next(.stopped(s, .movie(F.movie, duration: 1)))?.contains(.allowQuit) == false)
        #expect(flow.next(.converted(s, F.movie, isMov: false))?.contains(.allowQuit) == false)
        let delivered = flow.next(.delivered(s, nil)) ?? []
        #expect(delivered.filter { $0 == .allowQuit }.count == 1)
        #expect(!flow.quitPending)
    }

    @Test func recordingHotkeyIsIgnoredDuringAScreenshotSelection() {
        var flow = RecordingFlow()
        #expect(flow.next(F.toggle(allows: false)) == [.log("busy: dropped toggle")])
        #expect(flow.state == .idle)
    }

    @Test func overlaysCloseAtStopNotAfterConversion() {
        var flow = F.recordingFlow(options: RecordingOptions(clicks: true, camera: true))
        let stop = flow.next(F.toggle()) ?? []
        #expect(stop.contains(.overlays(start: false, clicks: true, keys: false, showAllKeys: false)))
        #expect(stop.contains(.bubble(nil)))
        #expect(stop.contains(.inputMonitor(start: false)))
        let convert = flow.next(.stopped(SessionID(1), .movie(F.movie, duration: 1))) ?? []
        #expect(!convert.contains { if case .overlays = $0 { true } else { false } })
    }

    @Test func toggleDuringSelectionCancelsIt() {
        var flow = RecordingFlow()
        _ = flow.next(F.toggle())
        #expect(flow.next(F.toggle()) == [.cancelSelection, .activity(.end(.recordingSetup)), .log("finish 1")])
        #expect(flow.state == .idle)
        // The selection's late result is stale.
        #expect(flow.next(F.selected(1)) == nil)
    }
}
