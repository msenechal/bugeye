import BugeyeCore
import Foundation
import Testing

@MainActor @Suite struct SelectionTests {
    /// Answers one fixed result and records what it was asked.
    final class Target: AreaSelector {
        var requests: [SelectionRequest] = []
        var cancels: [SelectionPurpose] = []
        let result: SelectionResult
        init(_ result: SelectionResult) { self.result = result }
        func select(_ request: SelectionRequest) async -> SelectionResult {
            requests.append(request)
            return result
        }
        func cancel(_ purpose: SelectionPurpose) { cancels.append(purpose) }
    }

    let area = StoredArea(
        display: DisplayID(1), rect: Rect2D(x: 10, y: 20, width: 30, height: 40),
        displaySize: Size2D(width: 1512, height: 982))

    @Test func requestDefaults() {
        let request = SelectionRequest(purpose: .recording)
        #expect(request.purpose == .recording)
        #expect(!request.startInWindowMode && request.hint == nil && !request.clickSelectsDisplay)
        #expect(!request.windowNeedsDisplayCentre && request.lastArea == nil)
    }

    @Test func storedAreasRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(area)
        #expect(try JSONDecoder().decode(StoredArea.self, from: data) == area)
    }

    @Test func theRelayCancelsWhileItHasNoTarget() async {
        let relay = AreaSelectorRelay()
        #expect(await relay.select(SelectionRequest(purpose: .screenshot)) == .cancelled)
        relay.cancel(.screenshot)  // no-op, no crash
    }

    @Test func theRelayForwardsToItsTarget() async {
        let relay = AreaSelectorRelay()
        let target = Target(.area(area))
        relay.target = target
        let request = SelectionRequest(purpose: .recording, hint: "Select an area", lastArea: area)
        #expect(await relay.select(request) == .area(area))
        relay.cancel(.recording)
        #expect(target.requests == [request])
        #expect(target.cancels == [.recording])
    }

    @Test func activitiesBeginAndEndIdempotently() {
        let activity = ScreenActivity()
        #expect(activity.active.isEmpty)
        activity.begin(.recording)
        activity.begin(.recording)
        #expect(activity.active == [.recording])
        activity.end(.recording)
        activity.end(.recording)
        #expect(activity.active.isEmpty)
    }

    /// Every activity × request (contracts §4.1.8, K32).
    @Test(
        arguments: [
            (nil, ScreenActivity.Request.screenshot, true),
            (nil, .captureText, true),
            (nil, .startRecording, true),
            (nil, .findCapture, true),
            (ScreenActivity.Activity.screenshotSelection, .screenshot, true),
            (.screenshotSelection, .captureText, true),
            (.screenshotSelection, .startRecording, false),
            (.screenshotSelection, .findCapture, true),
            (.recordingSetup, .screenshot, false),
            (.recordingSetup, .captureText, false),
            (.recordingSetup, .startRecording, true),
            (.recordingSetup, .findCapture, true),
            (.recording, .screenshot, true),
            (.recording, .captureText, false),
            (.recording, .startRecording, true),
            (.recording, .findCapture, true),
        ] as [(ScreenActivity.Activity?, ScreenActivity.Request, Bool)])
    func theGateTable(activity: ScreenActivity.Activity?, request: ScreenActivity.Request, allowed: Bool) {
        let gate = ScreenActivity()
        if let activity { gate.begin(activity) }
        #expect(gate.allows(request) == allowed)
    }

    @Test func endingAnActivityLiftsItsGate() {
        let gate = ScreenActivity()
        gate.begin(.recordingSetup)
        gate.begin(.screenshotSelection)
        #expect(!gate.allows(.screenshot) && !gate.allows(.startRecording))
        gate.end(.recordingSetup)
        #expect(gate.allows(.screenshot) && !gate.allows(.startRecording))
    }
}
