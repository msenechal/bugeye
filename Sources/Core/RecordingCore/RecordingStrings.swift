import Foundation

/// A notice's title and body, posted through `Notifier`.
public struct RecordingNotice: Hashable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Every user-visible string of the Recording epic, copied from the spec (§3.1, §4, §5).
public enum RecordingStrings {
    // Menu, hotkey, pane (§3.1, §4).
    public static let recordScreen = "Record Screen"
    public static let paneTitle = "Recording"
    public static let videoFormat = "Video format"
    public static let h264 = "H.264 (plays everywhere)"
    public static let hevc = "HEVC (smaller, full 5K/6K resolution)"
    public static let videoFormatNote = "H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304."
    public static let showAllKeys = "Show all keystrokes (not just shortcuts)"
    public static let showAllKeysNote =
        "Off: only presses with ⌘ or ⌃ appear, so what you type (including ⌥ symbols) stays private."

    // Selection (§5.1).
    public static let selectionHint =
        "Drag an area · Click to record this display · Space: pick a window · Esc to cancel"

    // Options bar (§5.2).
    public static let record = "● Record"
    public static let recordTooltip = "Start recording (Return)"
    public static let mic = "Mic"
    public static let defaultDevice = "Default"
    public static let micTooltip = "Record your voice"
    public static let micDenied =
        "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone."
    public static let systemAudio = "System audio"
    public static let systemAudioTooltip = "Record the sound your Mac plays"
    public static let cam = "Cam"
    public static let size = "Size"
    public static let small = "Small"
    public static let medium = "Medium"
    public static let large = "Large"
    public static let camera = "Camera"
    public static let camTooltip = "Show your camera in a bubble"
    public static let noCamera = "No camera found."
    public static let cameraDenied =
        "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera."
    public static let keys = "Keys"
    public static let keysTooltip = "Show the shortcuts you press"
    public static let keysNeedAccessibility =
        "Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again."
    public static let clicks = "Clicks"
    public static let clicksTooltip = "Highlight mouse clicks"
    public static let frameRate = "Frame rate"
    public static let fps30 = "30 fps"
    public static let fps60 = "60 fps"
    public static let quality = "Quality"
    public static let standard = "Standard"
    public static let high = "High"
    public static let optionsTooltip = "Recording options"
    public static let cancelTooltip = "Cancel (Esc)"

    // While recording (§5.3).
    public static let pause = "Pause"
    public static let resume = "Resume"
    public static let stop = "Stop"
    public static let restart = "Restart"
    public static let discard = "Discard"
    public static let cancel = "Cancel"
    public static let finishingLabel = "Finishing recording"
    public static let restartTitle = "Restart this recording?"
    public static let restartBody = "What you've recorded so far will be thrown away."
    public static let discardTitle = "Discard this recording?"
    public static let discardBody = "Nothing will be saved."

    /// `Finishing…` until progress is known, then `Finishing… <n> %`.
    public static func finishing(percent: Int?) -> String {
        percent.map { "Finishing… \($0) %" } ?? "Finishing…"
    }

    public static func recordingLabel(elapsed: String) -> String { "Recording, \(elapsed)" }

    public static func pausedLabel(elapsed: String) -> String { "Recording paused, \(elapsed)" }

    /// `path` as `~/…` when it is under `home`.
    public static func homeRelative(_ path: String, home: String) -> String {
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }

    /// An error's description as a sentence: trimmed, ending with a full stop.
    public static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return [".", "?", "!", "…"].contains(where: trimmed.hasSuffix) ? trimmed : trimmed + "."
    }

    // Notices (§5.7).
    public enum Notice {
        public static let diskLow = RecordingNotice(
            title: "Not enough disk space", body: "Free at least 1 GB to start a recording.")
        public static let diskFull = RecordingNotice(
            title: "Recording stopped: disk almost full", body: "What was recorded has been kept.")
        public static let keptMovie = RecordingNotice(
            title: "Recording saved as a QuickTime movie",
            body: "There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime.")
        public static let nothingRecorded = RecordingNotice(
            title: "Nothing was recorded", body: "The recording stopped before the first frame.")
        public static let cameraUnavailable = RecordingNotice(
            title: "Camera unavailable (in use by another app?)", body: "Cam has been turned off.")
        public static let recovered = RecordingNotice(
            title: "Recovered a recording", body: "Bugeye quit while recording. What was recorded has been kept.")

        public static func stopped(error: String) -> RecordingNotice {
            let kept = "What was recorded has been kept."
            let text = sentence(error)
            return RecordingNotice(title: "Recording stopped", body: text.isEmpty ? kept : text + " " + kept)
        }

        public static func couldNotStart(error: String) -> RecordingNotice {
            RecordingNotice(title: "Couldn't start recording", body: sentence(error))
        }

        /// `path` in `~/…` form when it is under `home`.
        public static func couldNotSave(path: String, home: String) -> RecordingNotice {
            RecordingNotice(
                title: "Couldn't save the recording", body: "It is still in \(homeRelative(path, home: home)).")
        }
    }
}
