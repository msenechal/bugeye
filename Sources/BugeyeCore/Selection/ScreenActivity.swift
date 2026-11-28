/// design/01 §1.2's HotkeyRoute, shared by Capture and Recording: which requests are refused while a screen
/// activity runs. Each epic begins and ends its own activities.
@MainActor
public final class ScreenActivity {
    public enum Activity: String, Hashable, Sendable {
        /// Capture: from request to idle, purpose `.screenshot` only.
        case screenshotSelection
        /// Recording: selecting, configuring, countingDown (K32).
        case recordingSetup
        /// Recording: starting, recording, paused, finishing.
        case recording
    }

    public enum Request: Hashable, Sendable { case screenshot, captureText, startRecording, findCapture }

    public private(set) var active: Set<Activity> = []

    public init() {}

    /// Idempotent.
    public func begin(_ activity: Activity) {
        active.insert(activity)
    }

    /// Idempotent.
    public func end(_ activity: Activity) {
        active.remove(activity)
    }

    /// screenshot: not during recordingSetup. captureText: not during recordingSetup or recording.
    /// startRecording: not during screenshotSelection. findCapture: always. Stopping a recording is never asked.
    public func allows(_ request: Request) -> Bool {
        switch request {
        case .screenshot: !active.contains(.recordingSetup)
        case .captureText: active.isDisjoint(with: [.recordingSetup, .recording])
        case .startRecording: !active.contains(.screenshotSelection)
        case .findCapture: true
        }
    }
}
