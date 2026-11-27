# 04 — Recording, trim and GIF

Covers M3 (recording core), M4 (overlays and window recording), M5 (trim and GIF), and the recording/trim/GIF items fixed in M6 part 4. Recording provenance (M7) is in `06-provenance-and-clipboard.md`; the selection overlay itself in `02-capture-and-quick-access.md`.

Sources: `Sources/CSRecording/*`, `Sources/CleanShotCopy/Recording/*`, `Sources/CleanShotCopy/Media/*`, CSCore `Recording*.swift`, `Keystrokes.swift`, `ClickRings.swift`, `BubbleLayout.swift`, `WindowFollow.swift`, `GifPreset.swift`, `TrimRange.swift`, `DiskGuard.swift`, `OptionsBarPlacement.swift`; spec §7 (+ M3/M4/M5 clarifications) of `2026-10-16-cleanshot-copy-design.md`, `2026-10-21-backlog-design.md` §4.3–4.5; plans m3, m4, m5, m6d; checklists m3–m5, m6-backlog; git history.

---

## 1. What it does

### 1.1 Starting (⇧⌘5)

1. **⇧⌘5** freezes and dims every display, like an area screenshot, with the hint "Drag to record an area · Click to record this display". The user unticks macOS's own ⇧⌘5 once.
2. Choose the target:
   - **drag an area**;
   - **click without dragging**: that whole display;
   - **Return**: the last recording area again;
   - **Space**: window mode; hover highlights windows, click records that window (clicking a mostly off-screen window beeps and keeps the overlay open);
   - **Esc**, a right-click, or ⇧⌘5 again: cancel.
3. The **options bar** appears under the selection (above it if it doesn't fit, inside the bottom edge for a full display), and a dashed white border marks the area.
4. **Record** (or Return) runs a **3 · 2 · 1** countdown in the middle of the area, one second per digit. Esc or ⇧⌘5 cancels during the bar and the countdown.
5. Recording starts: the border turns solid red, the menu-bar icon becomes **● 00:00**.

While the selection, bar or countdown is up, screenshot hotkeys (⇧⌘3/4/6/7) do nothing. ⇧⌘5 during a screenshot selection is ignored (no second overlay). ⇧⌘7 (Capture Text) is ignored during a recording; ⇧⌘4 and ⇧⌘6 still work. ⇧⌘8 (Find Capture) always works.

### 1.2 The options bar

A floating, non-activating night panel (dark gradient), left to right:

| Control | Behaviour |
|---|---|
| **● Record** | red, prominent, default button (Return) |
| **Format** MP4 \| GIF | segmented; tooltip "GIF: recorded as video, converted when you stop (no sound)" |
| **Mic** | first use asks for microphone permission; when on, a device picker appears ("Default" + devices). Denied: disabled, tooltip "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone." Disabled for GIF. |
| **System audio** | "Record the sound your Mac plays". Disabled for GIF. |
| **Cam** | first use asks for camera permission; shows the webcam bubble at once. A ⌄ menu sets Size (Small / Medium / Large) and Camera (when more than one). No camera: "No camera found."; denied: "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera." |
| **Keys** | needs Accessibility; without it, turning it on shows the system prompt. Tooltip without permission: "Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again." |
| **Clicks** | "Highlight mouse clicks"; no permission needed |
| **⚙** | Frame rate 30 / 60 fps, Quality Standard / High; with GIF also GIF width and GIF frame rate |
| **✕** | Cancel (Esc) |

- All choices persist (UserDefaults keys `recording.*`). Defaults: 30 fps, Standard, mic off, system audio off, clicks/keys/cam off, bubble Medium, MP4, GIF 720 px / 15 fps.
- The bar re-centres when it widens (e.g. the mic picker appears).
- What is actually recorded is `effectiveOptions`: mic off without permission, keys off without Accessibility, cam off without permission or camera, unknown device IDs → default, GIF → no audio.

### 1.3 While recording

- **Menu bar:** "● mm:ss" (h:mm:ss from one hour) in monospaced digits, red dot; "❙❙ " while paused (timer frozen); an hourglass while finishing.
- **The ● menu:** Pause / Resume, Stop (⇧⌘5), separator, Restart, Discard.
  - **Restart:** throws the take away and runs a new countdown.
  - **Discard:** throws it away, nothing is saved.
  - Both ask first when the recording is **longer than 10 s**: "Restart this recording?" / "Discard this recording?" with the action button and Cancel.
- **⇧⌘5** stops. **⌘Q** stops and saves first (and waits for a recording that is finishing).
- Paused time is cut out of the file.
- **Disk:** a recording needs **1 GB** free to start ("Not enough disk space" / "Free at least 1 GB to start a recording."); below **300 MB** (checked every 5 s) it stops and keeps what was recorded ("Recording stopped: disk almost full").
- **Failures** (stream died, writer failed): "Recording stopped" / "<error> What was recorded has been kept.", and the recording is finished normally.

### 1.4 Overlays (M4)

- **Clicks:** every left click on the recorded display gets an animated **yellow** ring, right clicks a **pink** one. Each ring grows from 14 to 28 pt (ease-out) and fades over 0.5 s; 3 pt stroke plus a 25 % fill. Clicks on Bugeye's own windows (bar, bubble) don't ring.
- **Keystrokes:** a dark rounded badge, centred, 40 pt above the bottom of the recorded area; 22 pt semibold white text on 75 % black, 10 pt corners.
  - Only **shortcuts** by default: a press counts as a shortcut when it uses **⌘ or ⌃**. ⇧+letter and ⌥+letter are typing (⌥ types `[ ] { } | ~` on AZERTY/German layouts), so they're hidden unless **Settings → Recording → "Show all keystrokes (not just shortcuts)"** is on.
  - Modifiers in the order ⌃ ⌥ ⇧ ⌘, space-separated: "⇧ ⌘ 3", "⌘ Z ×3".
  - The key is its **base character**: the number row is always its digit (⇧⌘3 shows "3", not "#"); a letter from a non-Latin layout shows the US letter of that key; Latin layouts keep their own letters (AZERTY ⌘A → "⌘ A"). Named keys: ↩ ⌤ ⇥ Space ⌫ ⌦ ⎋ ← → ↓ ↑ ↖ ↘ ⇞ ⇟ F1–F12.
  - The same label within 1.5 s shows "×N"; key auto-repeat isn't counted. Visible 1.5 s, the last 0.3 s fading.
- **Webcam bubble:** round, mirrored, 3 pt white border, shadow; Small 120 / Medium 180 / Large 240 pt. Starts bottom-right of the area, 24 pt in. Drag anywhere; on release it snaps to the nearest corner (centred along an axis where the area is too small). Double-click cycles the size, saved like a choice in the bar. Shown during set-up so it can be placed. A camera that can't be opened or is taken by another app turns Cam off: "Camera unavailable (in use by another app?)".
- The overlay window and the bubble **are** in the video; the border, bar, countdown, ● menu, Quick Access thumbnails, editors and every other Bugeye window are **not**, including windows opened mid-recording.

### 1.5 Window recording (M4)

- Records only that window plus Bugeye's overlays; windows in front of it are never captured. Menus or pop-ups the window opens may not show.
- The window is **followed** as it moves (10× a second); its **size is fixed at the start**, so a resize crops or shows background instead of distorting. Moved partly off the display, the frame stays on the display. Closed or minimised: the video shows nothing new.
- The border, the keystroke badge and the bubble's corner follow the window.

### 1.6 The result

- MP4: **H.264** by default (Settings → Recording → Video format: "H.264 (plays everywhere)" / "HEVC (smaller, full 5K/6K resolution)"; note under it: "H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304."). One video track, one mixed AAC audio track (mic + system), cursor visible, BT.709 colour tags.
- Named **`Recording YYYY-MM-DD at HH.MM.SS.mp4`** by the time the take **started** (` (2)` etc. on collision). Delivered like a capture: save folder `~/Pictures/Bugeye/` (or the temp folder when auto-save is off), clipboard file reference, Quick Access thumbnail with the first frame (a generic movie icon if the frame can't be read) and a "▶ mm:ss" badge.
- If there isn't room for the MP4 copy (movie size + 50 MB) or conversion fails, the original `.mov` is delivered with "Recording saved as a QuickTime movie" / "There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime." Quick Access Save keeps the `.mov` extension.
- No frame recorded: "Nothing was recorded" / "The recording stopped before the first frame."
- **GIF format:** no audio; the recorded movie is encoded straight to `Recording … .gif` with the remembered width/fps, and the movie is deleted. If the GIF fails, the movie is delivered instead: "Couldn't make the GIF" / "<error> The video was kept instead." (the user wants this fallback kept). Thumbnail badge "GIF"; its Quick Access button reads **Open** (default viewer).

### 1.7 Trim (M5)

- Quick Access **Trim** (or double-click) on a recording opens a player window "Trim — <name>" in AVKit's trim mode: in/out handles, **Trim** / **Cancel**.
- **Trim** saves a **new copy** (the original is untouched), frame-accurate, in the source's codec (HEVC stays HEVC). The window stays open with a spinner while it re-encodes, then closes; the copy is delivered like a capture (named by the current time, `.mov` if the source is `.mov`).
- Handles not moved, or a range under 0.1 s: nothing is saved. Cancel: a trim window closes.
- **Open Last Capture** on a recording opens plain playback (title = file name) with a **Trim** button in the title bar; Cancel there returns to playback.
- If the player isn't ready within 10 s: "Couldn't open this recording for trimming".

### 1.8 Export GIF (M5)

- Quick Access **⋯ → Export GIF…** (recordings only) opens a small floating night panel "Export GIF — <name>": **Width** 480 px / 720 px / Original, **Frame rate** 10 / 15 / 24 fps (yellow segmented pickers), progress bar, **Cancel**, **Export**.
- The GIF loops forever, keeps the aspect ratio, is never upscaled, and is delivered like a capture ("Recording <now>.gif"). The last width and fps are remembered (shared with the GIF recording format).
- Long clips are shrunk automatically so encoding can't exhaust memory.
- Cancel or closing the panel stops the export: no file, nothing on the clipboard. The panel stays visible when switching apps.

---

## 2. How it's built

### 2.1 Targets and files

| Target | File | Role |
|---|---|---|
| CSCore (Swift 6, pure) | `RecordingPhase.swift` | phase state machine and events |
| | `RecordingClock.swift` | pause-aware timeline |
| | `RecordingOptions.swift`, `RecordingQuality.swift` | options, persistence, bitrate |
| | `RecordingGeometry.swift` | `PixelSize`, `VideoCodec`, encoder-safe sizes, rect conversions |
| | `RecordingTimeFormat.swift`, `DiskGuard.swift`, `OptionsBarPlacement.swift`, `WindowFollow.swift` | |
| | `Keystrokes.swift`, `ClickRings.swift`, `BubbleLayout.swift` | overlay logic |
| | `GifPreset.swift`, `TrimRange.swift` | M5 logic |
| CSRecording (Swift 5) | `ScreenRecorder.swift` | `SCStream` → writer, window follow |
| | `RecordingWriter.swift` | `AVAssetWriter` .mov, one track per source |
| | `RecordingFinalizer.swift` | .mov → .mp4, video passthrough, audio mix |
| | `RecordingTrimmer.swift`, `GifEncoder.swift`, `RecordingThumbnail.swift`, `RecordingError.swift` | |
| App (Swift 5) | `Recording/RecordingCoordinator.swift` | the whole flow |
| | `Recording/RecordingOptionsModel.swift`, `RecordingOptionsBar.swift` | bar model and panel |
| | `Recording/AreaBorderWindow.swift`, `CountdownWindow.swift`, `RecordingOverlayWindow.swift`, `WebcamBubble.swift`, `InputMonitor.swift` | windows and monitors |
| | `Media/MediaWindows.swift`, `TrimWindowController.swift`, `GifExportPanel.swift` | trim and GIF UI |
| | `MenuBarController.showRecording`, `HotkeyRoute`, `AppDelegate.deliverMedia` | menu bar, routing, delivery |

CSRecording and the app are Swift 5 language mode because AVFoundation and ScreenCaptureKit callbacks aren't Sendable-clean.

### 2.2 Phase state machine

`RecordingPhase`: `idle → selecting → configuring → countingDown → recording ⇄ paused → finishing → idle`. `next(event) -> RecordingPhase?` returns nil for an event that means nothing in that phase; callers ignore it. That single rule stops stray hotkeys from breaking the flow.

| From | Event → To |
|---|---|
| idle | hotkey → selecting |
| selecting | selected → configuring; cancelled/hotkey → idle |
| configuring | record → countingDown; cancelled/hotkey → idle |
| countingDown | countdownFinished → recording; cancelled/hotkey → idle |
| recording | pause → paused; stop/hotkey → finishing; restart → countingDown; discard → idle |
| paused | resume → recording; stop/hotkey → finishing; restart → countingDown; discard → idle |
| finishing | finished → idle |

- `blocksScreenshots` = selecting, configuring, countingDown. `allowsRecordingHotkey(screenshotInProgress:)` = not (idle and a screenshot selection is up).
- `RecordingCoordinator.toggle()`: idle → begin selection; set-up phases → cancel; recording/paused → stop; finishing → nothing.

### 2.3 Session tokens

`RecordingCoordinator.session` is bumped when an attempt begins, is cancelled, restarted or discarded. Every async continuation (display freeze, selection result, `recorder.start`, `onFailure`, `onWindowMoved`) captures the token and does nothing if it's stale. `recorderStarted` cancels a recorder that started for an old session. `recorderFailedToStart` only tears down if its session is current. (Fix `4f506f8`.)

### 2.4 Selection

- `beginSelection` checks Screen Recording permission (`PermissionPrompt.showScreenRecordingMissing` otherwise), freezes every display with `ScreenCapturer.captureDisplay(_:excludingPID:)`, lists windows with `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`, and opens `AreaSelectionController(purpose: .recording, startInWindowMode: false, frozen:, windows:, ownPID:, lastArea:)`. Esc is registered as a temporary global hotkey while the overlay is up.
- Result `.area(displayID, rect)` (display-local points, top-left origin) also becomes `lastArea`; `.display(id)` → area nil; `.window(id)` → `ScreenRecorder.windowBounds(id)` → the display holding the window's centre and `WindowFollow.followedRect`.

### 2.5 Set-up windows

- `AreaBorderWindow`: borderless, `.statusBar` level, click-through, 3 pt outset; dashed white (6/4, 2 pt) while configuring, solid `systemRed` 2 pt while recording. For a whole display it's inset 3 pt so it stays on screen.
- `RecordingOptionsPanel`: `NSPanel` `[.nonactivatingPanel, .borderless]`, `.statusBar` level, `canBecomeKey = true`, `hidesOnDeactivate = false`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, hosting the SwiftUI bar. Esc via `keyDown` (53) **and** `cancelOperation(_:)`. `reposition()` re-fits to `fittingSize` and re-places with `OptionsBarPlacement.origin(barSize:selection:visibleFrame:gap: 12)`; called on every option change after SwiftUI lays out (`Task { @MainActor in … }`).
- `CountdownWindow`: 140 × 140 non-activating panel, night gradient, 28 pt corners, 72 pt bold digits in the accent colour; a 1 s `Timer`; Esc via `keyDown` and `cancelOperation`.

### 2.6 ScreenRecorder (ScreenCaptureKit)

```swift
struct RecordingRequest { displayID; area: CGRect?  // display-local points
  options: RecordingOptions; codec: VideoCodec; excludingPID: pid_t
  windowID: CGWindowID?; overlayWindowIDs: [CGWindowID] }
```

`start(_:)`:
1. `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`; `userDeclined` → `.permissionDenied`.
2. Overlay windows = content windows whose IDs are in `overlayWindowIDs` (`CGWindowID(window.windowNumber)` of the overlay window and the bubble). Missing ones are **logged** (they'd silently be absent from the video).
3. **Filter:**
   - window mode: `SCContentFilter(display:, including: [window] + overlays)`;
   - otherwise: `SCContentFilter(display:, excludingApplications: [ourApp], exceptingWindows: overlays)`. Excluding the *application* (not a snapshot of its windows) also excludes windows opened later (● menu, thumbnails, an editor);
   - fallback if our app isn't listed: exclude our windows by PID except the overlays.
4. Size: `scale = filter.pointPixelScale`; `area` clamped to whole display points (`clampedSourceRect`, ≥ 2 pt); `RecordingGeometry.outputSize(forPoints:scale:codec:)` = pixels, shrunk to the codec max keeping aspect (H.264 4096 × 2304, HEVC 8192 × 4320), rounded **down to even** numbers.
5. `SCStreamConfiguration`: `sourceRect = area`, `width/height`, `minimumFrameInterval = 1/fps`, `pixelFormat = 420YpCbCr8BiPlanarVideoRange`, `colorSpaceName = sRGB`, `colorMatrix = ITU_R_709_2`, `showsCursor = true`, `queueDepth = 6`, `capturesAudio = systemAudio`, `excludesCurrentProcessAudio = true`, `sampleRate = 48_000`, `channelCount = 2`, `captureMicrophone = true` + `microphoneCaptureDeviceID` when the mic is on (macOS 15+ API, so no separate `AVCaptureSession` for the mic).
6. Writer created, then stream outputs `.screen`, `.audio`, `.microphone` on **one serial queue** (`userInteractive`), then `startCapture()`. On failure the writer is cancelled and removed on the queue.
7. Window mode starts the **follow timer**.

- **Frames:** only samples whose `SCStreamFrameInfo.status == .complete` are written (SCK also sends idle/blank frames).
- **Follow timer:** a `DispatchSourceTimer` **on the sample queue**, every 0.1 s: reads the window's bounds (`CGWindowListCopyWindowInfo([.optionIncludingWindow], id)`), computes `WindowFollow.followedRect(windowBounds:size:displayBounds:)` (fixed size, clamped into the display, rounded), and if changed sets `config.sourceRect` and calls `stream.updateConfiguration`; tells the main queue via `onWindowMoved`.
- **Pause/resume** are stamped **on the sample queue** (`queue.async { writer.pause(at: now()) }`), so every frame already handled was captured before the pause point.
- **Stop:** `detachStream()` (cancels the follow timer and takes the stream, in one `queue.sync`) → `stopCapture()` → take the writer off the queue in one step (a late sample finds no writer and is dropped) → `writer.finish(at: now)`. **Cancel** does the same and deletes the file.
- **Failures:** `stream(_:didStopWithError:)` and writer errors go through `reportFailure`, which keeps the first one under a lock and calls `onFailure` once on main. `currentFailure()` lets the coordinator see a failure that happened before it reached `.recording`.
- `now` and `attach(_:)` / `handle(_:from:)` are injectable so tests feed synthetic samples without ScreenCaptureKit.

### 2.7 RecordingWriter (AVAssetWriter)

- Writes a **QuickTime `.mov`** in the temp folder (`~/Library/Caches/dev.msenechal.cleanshotcopy/Captures/Recording-<uuid>.mov`). `movieFragmentInterval = 2 s` so a crash leaves a playable file.
- Video input: H.264 or HEVC, explicit **BT.709 primaries, transfer function and matrix** (`AVVideoColorPropertiesKey`), `AVVideoAverageBitRateKey`, expected fps, max keyframe interval = 2 × fps, `expectsMediaDataInRealTime`.
- Bitrate = width × height × fps × **0.06** (Standard) or **0.12** (High) bits, clamped to 2–100 Mbit/s.
- **One audio input per source** (system, mic): AAC 48 kHz stereo, 128 kbit/s, stereo channel layout; mono mics are upmixed by the encoder.
- **Timeline starts at the first screen frame:** `startSession(atSourceTime: .zero)`; audio before it is dropped. Each sample's host time → `RecordingClock.outputTime` → retimed copy (`CMSampleBufferCreateCopyWithNewTiming`, timescale 1e9). Video frames that don't advance time are dropped. When an input isn't ready, the sample is dropped (real-time behaviour; tests set `waitsForEncoder` to wait instead).
- `finish(at:)`: no frame → cancel + `.noFrames`; writer not `.writing` → throw (calling `endSession` on a failed writer raises an Objective-C exception and crashes); else mark inputs finished, `endSession(atSourceTime: max(elapsed, lastVideoTime))`, `finishWriting()`.

### 2.8 RecordingClock

Maps host-clock seconds onto the output timeline with paused spans removed. `outputTime(for:)` returns nil (drop) before the start and for any sample **captured** inside a pause, even if it arrives after resume, so the timeline never goes backwards. `elapsed(at:)` drives the menu-bar timer and is frozen while paused.

### 2.9 Finishing: MP4 and audio mixing

`RecordingCoordinator.finishRecording` first stops the ticker and input monitor and **closes the overlay window and the bubble immediately** (not after a long export), then in a Task:

- GIF format → `gifOrMovie(from: mov, preset:)` (encode straight from the `.mov`; on failure deliver the `.mov`).
- MP4 → `RecordingFinalizer.finalizeOrKeep(mov, to: mp4, freeBytes:)`:
  - skip if `DiskGuard.canFinalize(movieBytes:freeBytes:)` is false (needs movie size + 50 MB);
  - `finalize`: `AVAssetReader` with a **passthrough** video output (`outputSettings: nil`) and an `AVAssetReaderAudioMixOutput` over all audio tracks (LPCM 48 kHz 16-bit stereo); `AVAssetWriter(.mp4)` with a video input using `sourceFormatHint` (no re-encode, keeps the transform) and an AAC 48 kHz stereo 160 kbit/s audio input;
  - both pumps run **concurrently** (`requestMediaDataWhenReady` on separate queues, `async let`): the writer interleaves tracks and stalls one input until the other catches up, so pumping them one after the other deadlocks;
  - success deletes the `.mov`; failure deletes the partial `.mp4` and keeps the `.mov`.
- The `defer` always sends `.finished`, tears down and runs a deferred quit, so the app always leaves "finishing".
- Provenance collected at the start of the take is written onto the file before delivery.

### 2.10 Delivery and thumbnails

`AppDelegate.deliverMedia(url, startedAt:)` → `OutputRouter.deliverFile(at:kind:date:)` (moves the file into the save folder or temp folder with `FileNamer`, `Recording` prefix; clipboard file reference; reads provenance back) → `coordinator.setLastItem`, `indexer.add` → Quick Access:
- recording: `RecordingThumbnail.firstFrame` (`AVAssetImageGenerator`, ≤ 960 px, 0.5 s tolerance after) or `NSWorkspace.shared.icon(for: .movie)`; badge "▶ " + duration;
- GIF: `GifEncoder.firstFrame` (ImageIO index 0); badge "GIF".

### 2.11 Menu-bar timer

A 0.5 s `Timer` added to `RunLoop.main` in **`.common`** modes (so it keeps ticking while the ● menu is open, which runs the event-tracking mode). Each tick calls `onPhaseChanged` (the menu bar re-reads `elapsed`); every 10th tick checks free disk space.

### 2.12 Overlays

- `RecordingOverlayWindow`: one borderless window per recording covering the target screen, `.screenSaver` level, `ignoresMouseEvents`, transparent. Its `OverlayView` holds `ClickRings` and `KeystrokeBadge` and animates with a 60 Hz `Timer` in `.common` modes that stops itself when nothing is visible. `close()` stops the timer; `deinit` invalidates it too (a scheduled timer is retained by the run loop after its view is gone).
- `InputMonitor`: `NSEvent.addGlobalMonitorForEvents` for `.leftMouseDown/.rightMouseDown` (no permission needed) and `.keyDown` (needs Accessibility), ignoring `isARepeat`. Global monitors don't see events in our own windows, which is why the bar and bubble don't ring.
- Key label: `KeystrokeFormatter.label(keyCode:characters:modifiers:showAllKeys:)` with `characters = event.characters(byApplyingModifiers: [])` (the unshifted character in the current layout); `baseKey` maps the number row to digits and non-Latin letters to the US letter of the key code (`usBase` table).
- `WebcamBubble`: `NSPanel` (non-activating, borderless, `.screenSaver`), an `AVCaptureSession` (preset `.high`) with `AVCaptureVideoPreviewLayer` (`resizeAspectFill`, mirrored: `automaticallyAdjustsVideoMirroring = false`, `isVideoMirrored = true`), layer corner radius = diameter/2. `startRunning`/`stopRunning` on its own queue. Observes `runtimeErrorNotification` and `wasInterruptedNotification` → `onUnavailable`. Cameras from `AVCaptureDevice.DiscoverySession([.builtInWideAngleCamera, .external, .continuityCamera])`.
- `BubbleChange.decide(current:webcam:cameraID:size:)` → none / create / remove / resize / **recreate** (a different camera needs a new session; the bubble keeps its corner). `BubbleLayout.moved` carries the bubble with a followed window.
- The overlay and bubble window IDs are passed to `ScreenRecorder` as `overlayWindowIDs`, so they are the exceptions to the app exclusion.

### 2.13 Trim

- `TrimWindowController`: `AVPlayerView` (floating controls); `beginTrimming` once `canBeginTrimming` (polled every 0.1 s, up to 10 s). On `.okButton` the range = `TrimRange(start: item.reversePlaybackEndTime, end: item.forwardPlaybackEndTime, duration:)` (invalid `CMTime` = handle not moved); `range.covers(duration)` → nothing to save.
- `TrimRange.init?` clamps to the clip and rejects < 0.1 s.
- `RecordingTrimmer.trim`: `AVAssetExportSession` with `AVAssetExportPresetHEVCHighestQuality` when the source's format subtype is HEVC, else `AVAssetExportPresetHighestQuality`; `timeRange` at timescale 600; `export(to:as:)` (`.mov` if the destination is `.mov`, else `.mp4`). Re-encoding makes cuts frame-accurate; a passthrough copy would start at the previous keyframe, up to 2 s early.
- The trimmed copy gets the source's provenance (`ProvenanceStore.copy`) and is delivered through `MediaWindows.onFinished`.
- `MediaWindows` keeps trim windows and GIF panels alive and tracks each item's **current** URL, so Trim and Export GIF follow a file moved by Quick Access Save.

### 2.14 GIF encoding

- `GifPreset`: width 480 / 720 / original, fps 10 / 15 / 24.
  - `outputSize(for:)`: scale down to the width, never up.
  - `pixelBudget = 150_000_000` total pixels across all frames (ImageIO keeps every frame until finalize, ~11 bytes per pixel, so ~1.6 GB worst case); `outputSize(for:duration:)` shrinks further by √(budget / total).
  - `frameTimes(duration:)` = 0, 1/fps, … strictly before the end.
  - `frameDelay(at:)`: GIF delays are whole centiseconds, so they are **spread** to keep the running total on the frame rate (15 fps: 7, 7, 6, …; 24 fps: 5, 4, 4, …).
- `GifEncoder.encode`: `AVAssetImageGenerator` (`appliesPreferredTrackTransform`, `maximumSize`, tolerance ± half a frame) iterated with `images(for:)`; `CGImageDestinationCreateWithURL(…, UTType.gif, count)`, loop count 0, per-frame `kCGImagePropertyGIFDelayTime` **and** `UnclampedDelayTime`. A frame that can't be decoded repeats the previous one. Cancellation (`Task.isCancelled`) deletes the file and throws `CancellationError`. Progress callback per frame.
- `GifExportModel` (`ObservableObject`) runs the export in a cancellable Task, saves the chosen preset into `RecordingOptionsStore`, posts progress on main, deletes the result if cancelled late. `MediaWindows` observes the panel's `willCloseNotification` to cancel and removes that observer when it fires.

---

## 3. Gotchas and bugs we hit

| Symptom | Root cause | Fix | Commit |
|---|---|---|---|
| Crash when stopping after a writer failure | `endSession` on a writer that isn't `.writing` raises an exception | Guard `finish` on `writer.status`; 2 s movie fragments | `096993b` |
| Recording lost when MP4 conversion couldn't run | The .mov was deleted / not delivered on failure or low disk | `finalizeOrKeep`: deliver the `.mov` with a notice | `096993b` |
| The ● menu and Quick Access thumbnails appeared at the end of videos | Windows were excluded as a snapshot at start; windows opened later weren't in it | `SCContentFilter(display:excludingApplications:exceptingWindows:)` excludes the whole app | `096993b` |
| ⇧⌘5 during a ⇧⌘4 selection opened a second overlay; ⌘Q right after Stop lost the file | No gating; quit didn't wait for "finishing" | `allowsRecordingHotkey`; `deferQuit` waits for `.finishing` | `096993b` |
| A failure reported before the phase reached `.recording` was missed | `onFailure` fired while still counting down | `currentFailure()` checked in `recorderStarted` | `096993b` |
| Frames from after the pause point appeared; content jumped back at resume | Pause was stamped on the main thread with the host clock while samples queued on the sample queue still arrived | Stamp pause/resume on the sample queue; clear the writer on the queue at stop/cancel | `4c428f8` |
| Pressing ⇧⌘5 quickly several times left a stray overlay, a leaked recorder, or tore down the new attempt | ⇧⌘5 during the display freeze did nothing; a stale `recorder.start` kept or failed onto the new attempt; an old take's `onFailure` could stop a restarted one | Session tokens on every async step | `4f506f8` |
| Menu-bar timer froze while the ● menu was open | `Timer.scheduledTimer` runs only in the default mode; menus run event tracking | Add the timer to `.common` modes | `1e641b5` |
| Esc on the options bar didn't cancel after clicking a toggle | A focused control sends `cancelOperation:` up the responder chain, not `keyDown` | Handle both; also re-centre the bar when it widens | `c70a01c` |
| Washed-out / inconsistent colours between QuickTime and browsers | No colour tags; players guessed | Tag BT.709 primaries/transfer/matrix in the writer; `colorMatrix` 709 in SCK | `8904487` |
| Keystroke badge showed "⇧ ⌘ #" for ⇧⌘3, Cyrillic letters for ⌘C on a Russian layout | Used `charactersIgnoringModifiers`, which still applies ⇧ for some keys and the active script | `characters(byApplyingModifiers: [])` + digit row + US letter for non-Latin | `fa03125` |
| AZERTY users' typed `[ ] { } \| ~` showed in videos | ⌥ was treated as a shortcut modifier | Only ⌘ or ⌃ make a shortcut | `50714c0` |
| Bubble didn't follow a recorded window; switching camera did nothing; camera light and overlays stayed on during a long export | No area update; same session kept; overlays closed only at teardown | `bubble.area` follows; `.recreate`; close overlays at Stop | `50714c0` |
| Double-click size not remembered; a busy camera left Cam on with no bubble | Size changed on the bubble only; no failure path | Cycle through the options model; `onUnavailable` turns Cam off with a notification | `1f40951` |
| Possible race / crash in window recording at stop | The follow timer ran on main and read `stream`/`config` while `stop()` (off-main) cleared them | Timer on the sample queue; `detachStream()` in one `queue.sync` | `226d9cd` |
| Overlay animation timer could outlive its view | Run loop retains scheduled timers | Invalidate in `deinit` (safety net) | `26b6264` |
| 15 fps GIFs played 10.5 s for a 10 s clip | Each delay rounded to 0.07 s | Spread centisecond delays | `208b5c8` |
| GIF recordings showed "Recording saved as a QuickTime movie" with low disk | GIF went through the MP4 step first | Encode the GIF straight from the `.mov` | `468cc2a` |
| Long "Original" GIF exports slowed the Mac to a crawl; Cancel still delivered; Trim/GIF failed after Quick Access Save moved the file | ImageIO holds all frames; no cancellation; stale URL | Pixel budget; cancellable task; `MediaWindows` tracks current URLs | `8896ece` |
| Trim window looked frozen during a long trim; a broken file showed nothing | No progress UI; `canBeginTrimming` never true | Spinner; 10 s timeout message; playback mode for Open Last Capture | `2ea77a5` |
| GIF panel vanished when switching apps; leaked its close observer | `hidesOnDeactivate` default; observer never removed | `hidesOnDeactivate = false`; remove the token on close | `5796535` |
| A test stalled the main queue for other parallel tests | It spun `RunLoop.main` synchronously to wait for the ticker | Don't spin the run loop in tests; wait asynchronously | `442baf2` |

Also:
- **MP4 conversion "hang on a failed track"** was a suspected bug, closed after a probe: the pump resumes when either `copyNextSampleBuffer()` returns nil or `append` fails, and marks its input finished, so the other pump can't wait forever. No timeout was added.
- **Smoke tests** (`CSC_INTEGRATION=1`: 2 s recording with video+audio, late windows excluded, overlays in / controls out, window in front ignored, window followed, transparent overlay, overlays in window mode) depend on what is on screen; when the screen is busy the overlay colour tests can fail. Rerun alone before calling a regression.
- `AVPlayerView.canBeginTrimming` stays false in the test process for a non-movie file, which made the "player can't open" test deterministic.

---

## 4. Known open issues

`docs/backlog.md` has no open item specific to recording, trim or GIF; M6 part 4 cleared them. Limitations by design or left as they are:

- Window recording: menus and pop-ups the window opens may not show (they are separate windows not in the include filter); the size is fixed at the start.
- Overlay windows missing from ScreenCaptureKit's list are only logged; they are silently absent from that video.
- Trim always re-encodes (slower, generational loss) to be frame-accurate.
- GIF encoding holds every frame in memory until finalize; long clips are shrunk rather than streamed.
- MP4 conversion has no timeout.
- Trimmed copies and exported GIFs are named by the time they were made, not the recording's start.
- The GIF-recording fallback (deliver the raw `.mov` when the GIF fails) is a user decision; keep it.

---

## 5. Do it better next time

### 5.1 Portable core vs macOS shell

| Portable core (Linux-tested) | macOS shell |
|---|---|
| `RecordingPhase`, session-token rules, the coordinator's decisions as a **pure reducer** (state + event → state + effects) | ScreenCaptureKit stream, `AVAssetWriter`, `AVAssetReader`, `AVAssetExportSession`, AVKit player |
| `RecordingClock`, `outputTime`, `elapsed`, retiming maths | `CMSampleBuffer` retiming, encoder settings |
| Sizes, bitrate, codec limits, `DiskGuard`, `OptionsBarPlacement`, `WindowFollow`, `BubbleLayout`, `BubbleChange` | Windows: bar, border, countdown, overlay, bubble; `NSEvent` monitors; camera session |
| `KeystrokeFormatter`, `KeystrokeBadge`, `ClickRings` (and their drawing as a display list) | Executing the overlay display list into the overlay view |
| `GifPreset` (sizes, budget, frame times, spread delays), `TrimRange` | Frame extraction, ImageIO GIF writing |
| A **GIF encoder core** taking `PixelBuffer` frames → GIF bytes (palette quantisation + LZW), streaming frame by frame | `FrameSource` port: decode frames from a movie |
| Option persistence (`KeyValueStore` port) | UserDefaults adapter |

Ports to define, each with a fake: `ScreenStream` (start/stop/pause, sample delivery with host times), `MovieWriter`, `MovieFinalizer`, `Trimmer`, `FrameSource`, `CameraPreview`, `InputEvents`, `PermissionStatus`, `DiskSpace`, `Clock`. The first build's injectable `now`, `attach`, `handle`, `waitsForEncoder`, `confirm`, `elapsedTime` and `encode` closures show where the seams belong.

### 5.2 Design choices to keep

- One serial sample queue owns the stream, the writer, pause stamps, the follow timer and teardown. Never touch those from main.
- Exclude the whole application with explicit exceptions for overlays, not a window snapshot.
- Overlays as real windows captured by SCK (WYSIWYG, no compositing step); controls excluded.
- Write a `.mov` with fragments during capture, convert at the end with video passthrough and one mixed audio track; keep the `.mov` if anything goes wrong.
- Explicit BT.709 tags; even dimensions within codec limits; complete-frame filter.
- Session tokens for every async continuation; `phase.next` returning nil for meaningless events.
- Timers that must tick during menus go in `.common` modes.
- Esc on panels through both `keyDown` and `cancelOperation:`.

### 5.3 Improvements

- **Make the coordinator a reducer in the core.** The 524-line `RecordingCoordinator` mixes decisions and AppKit. A pure `RecordingFlow` (phase, session, target, options, take) emitting effects (`showBar`, `startCountdown`, `startStream(request)`, `finish(format)`, `notify(...)`) can be tested exhaustively on Linux, including every "⇧⌘5 pressed at a bad moment" case that cost two review rounds.
- **Encode GIFs in the core and stream them:** write each frame as it is decoded instead of letting ImageIO hold them all; that removes the pixel-budget shrinking and lets long "Original" GIFs keep their size. Use a proper palette (median cut or octree) with optional dithering.
- **Stream audio mixing**: consider mixing at capture time into one track (or writing the MP4 directly with `AVAssetWriter` and a mixed audio input) to remove the post-stop conversion and its disk-space case. If keeping the two-step design, add a timeout and progress.
- **Window recording:** include the window's child windows (menus, sheets) by matching owner PID and layer at start and on each follow tick, or offer "record the area around the window" as the robust option.
- **Name trimmed copies and GIFs after the recording** (e.g. "Recording … (trimmed)") so they sort beside their source.
- **Smoke tests with fixtures:** drive ScreenCaptureKit against a dedicated test window with known content on a self-hosted Mac (see `13`), instead of whatever is on screen.
- **Permissions:** keep "toggle disabled with an explanation and recording proceeds without it" for mic, camera and Accessibility; model it in the core as `effectiveOptions(options, permissions, devices)` (already pure today) with tests.

### 5.4 Claude (optional, opt-in)

Recordings are the main input for the committed RD-08 bug report and the M13 video features (see `12` and `13`). Keep the recorder unaware of them: they consume the delivered file (or key frames from the `FrameSource` port), through the core's `LLMClient` port, with redaction applied first.
