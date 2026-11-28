import RecordingCore
import Testing

/// Every user-visible string of spec §3.1, §4 and §5, character for character.
@Suite struct RecordingStringsTests {
    typealias S = RecordingStrings

    @Test func menuHotkeyAndPane() {
        #expect(S.recordScreen == "Record Screen")
        #expect(S.paneTitle == "Recording")
        #expect(S.videoFormat == "Video format")
        #expect(S.h264 == "H.264 (plays everywhere)")
        #expect(S.hevc == "HEVC (smaller, full 5K/6K resolution)")
        #expect(S.videoFormatNote == "H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304.")
        #expect(S.showAllKeys == "Show all keystrokes (not just shortcuts)")
        #expect(
            S.showAllKeysNote
                == "Off: only presses with ⌘ or ⌃ appear, so what you type (including ⌥ symbols) stays private.")
        #expect(S.selectionHint == "Drag an area · Click to record this display · Space: pick a window · Esc to cancel")
    }

    @Test func optionsBar() {
        #expect(S.record == "● Record")
        #expect(S.recordTooltip == "Start recording (Return)")
        #expect(S.mic == "Mic")
        #expect(S.defaultDevice == "Default")
        #expect(S.micTooltip == "Record your voice")
        #expect(
            S.micDenied == "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.")
        #expect(S.systemAudio == "System audio")
        #expect(S.systemAudioTooltip == "Record the sound your Mac plays")
        #expect(S.cam == "Cam")
        #expect(S.size == "Size")
        #expect(S.small == "Small")
        #expect(S.medium == "Medium")
        #expect(S.large == "Large")
        #expect(S.camera == "Camera")
        #expect(S.camTooltip == "Show your camera in a bubble")
        #expect(S.noCamera == "No camera found.")
        #expect(S.cameraDenied == "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera.")
        #expect(S.keys == "Keys")
        #expect(S.keysTooltip == "Show the shortcuts you press")
        #expect(
            S.keysNeedAccessibility
                == "Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again."
        )
        #expect(S.clicks == "Clicks")
        #expect(S.clicksTooltip == "Highlight mouse clicks")
        #expect(S.frameRate == "Frame rate")
        #expect(S.fps30 == "30 fps")
        #expect(S.fps60 == "60 fps")
        #expect(S.quality == "Quality")
        #expect(S.standard == "Standard")
        #expect(S.high == "High")
        #expect(S.optionsTooltip == "Recording options")
        #expect(S.cancelTooltip == "Cancel (Esc)")
    }

    @Test func whileRecording() {
        #expect(S.pause == "Pause")
        #expect(S.resume == "Resume")
        #expect(S.stop == "Stop")
        #expect(S.restart == "Restart")
        #expect(S.discard == "Discard")
        #expect(S.finishing(percent: nil) == "Finishing…")
        #expect(S.finishing(percent: 42) == "Finishing… 42 %")
        #expect(S.recordingLabel(elapsed: "00:07") == "Recording, 00:07")
        #expect(S.pausedLabel(elapsed: "1:02:03") == "Recording paused, 1:02:03")
        #expect(S.finishingLabel == "Finishing recording")
        #expect(S.restartTitle == "Restart this recording?")
        #expect(S.restartBody == "What you've recorded so far will be thrown away.")
        #expect(S.discardTitle == "Discard this recording?")
        #expect(S.discardBody == "Nothing will be saved.")
        #expect(S.cancel == "Cancel")
    }

    @Test func notices() {
        #expect(
            S.Notice.diskLow
                == RecordingNotice(title: "Not enough disk space", body: "Free at least 1 GB to start a recording."))
        #expect(
            S.Notice.diskFull
                == RecordingNotice(
                    title: "Recording stopped: disk almost full", body: "What was recorded has been kept."))
        #expect(
            S.Notice.stopped(error: "The stream stopped")
                == RecordingNotice(
                    title: "Recording stopped", body: "The stream stopped. What was recorded has been kept."))
        #expect(
            S.Notice.stopped(error: "Disk error.")
                == RecordingNotice(title: "Recording stopped", body: "Disk error. What was recorded has been kept."))
        #expect(
            S.Notice.couldNotStart(error: "No display")
                == RecordingNotice(title: "Couldn't start recording", body: "No display."))
        #expect(
            S.Notice.keptMovie
                == RecordingNotice(
                    title: "Recording saved as a QuickTime movie",
                    body: "There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime.")
        )
        #expect(
            S.Notice.nothingRecorded
                == RecordingNotice(title: "Nothing was recorded", body: "The recording stopped before the first frame.")
        )
        #expect(
            S.Notice.cameraUnavailable
                == RecordingNotice(
                    title: "Camera unavailable (in use by another app?)", body: "Cam has been turned off."))
        #expect(
            S.Notice.couldNotSave(path: "/Users/m/Library/Caches/x.mov", home: "/Users/m")
                == RecordingNotice(title: "Couldn't save the recording", body: "It is still in ~/Library/Caches/x.mov.")
        )
        #expect(
            S.Notice.couldNotSave(path: "/Volumes/X/a.mov", home: "/Users/m")
                == RecordingNotice(title: "Couldn't save the recording", body: "It is still in /Volumes/X/a.mov."))
        #expect(
            S.Notice.recovered
                == RecordingNotice(
                    title: "Recovered a recording",
                    body: "Bugeye quit while recording. What was recorded has been kept."))
    }

    @Test func anErrorEndsWithAFullStop() {
        #expect(S.sentence("Oops") == "Oops.")
        #expect(S.sentence("Oops.") == "Oops.")
        #expect(S.sentence("  Oops  ") == "Oops.")
        #expect(S.sentence("") == "")
    }
}
