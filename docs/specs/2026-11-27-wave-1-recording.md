# Wave 1: Recording core

**Status:** approved 28 Nov 2026 · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → Mac batch → manual pass

Recording rebuilds the first build's screen recorder (`design/04` §1.1–1.6): ⇧⌘5, area, display and window targets, the options bar, the countdown, MP4 with microphone and system audio, click rings, the keystroke badge, the webcam bubble, the ● menu, and delivery to Quick Access. It also records an **event timeline** next to every recording, silently, for the motion engine of Wave 3 (`design/14` §2). It runs as one of the parallel Wave 1 sessions (`design/14` R1) on Wave 0's skeleton. What it needs from shared code lands first, in the Wave 1 contracts PR (`docs/specs/2026-11-27-wave-1-contracts.md`; §3 here lists what it uses).

## 1. Decisions

From the brainstorm (your answers):

| # | Question | Decision |
|---|---|---|
| B1 | Behaviour | **Exactly as `design/04` describes recording itself**: start flows (area, window, display, last area), MP4, microphone and system audio, click rings, keystroke badge, webcam bubble, options bar, countdown, ● menu, Stop, Restart, Discard, permissions, disk guard, naming, Quick Access hand-off. Plus the `design/04` §5 "do it better" items that concern recording: the coordinator as a pure reducer in the core, timeouts and progress on MP4 conversion, child windows in window recordings, fixture-driven smoke checks, `effectiveOptions` as a tested pure function. Trim, GIF (recording format and export) and captions are later epics; this spec leaves room (V9). |
| B2 | Event timeline | **Recorded silently next to each recording, used only by later features** (auto-zoom, captions, guide video). Timestamped clicks, cursor path, scrolls, window focus changes, the Accessibility element under each click (role, title, frame; never a value or typed text; nothing from secure fields), and keys as shortcuts only (modifier combos and non-text keys), never typed characters. Nothing about it is visible in Wave 1. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| V1 | **`RecordingFlow` in `RecordingCore` is the single owner of a recording**: a pure reducer, state + event → state + effects, with a session id on every async result (§6). The shell executes effects and translates callbacks into events, nothing else. | `design/04` §5.3. The first build's 524-line coordinator cost two review rounds on "⇧⌘5 at a bad moment". [Low] |
| V2 | **The recording overlay is Capture's overlay, reached through the contract's `AreaSelector`** (contracts §4.1.8, K15; Capture §6.1). Recording passes a `SelectionRequest` whose fields carry everything recording-specific (hint text, click-selects-display, window-centre rule, its own last area) as data; Capture's flow implements those rows generically and returns a `SelectionResult`. Recording never edits a capture-owned file. | One overlay owner keeps the stuck-overlay fixes in one place (`design/11` §6). Recording-specific behaviour as data means Capture's code knows no recording. [Medium: Capture's Wave 1 scope grows by the rows in its §6.1; if Capture slips, Recording's last PR waits for it.] |
| V3 | **The element under a click comes from the existing `AXReader.element(at:)`**, which the contracts PR moves unchanged into `Sources/BugeyeCore/Ports/Accessibility/`, Recording-owned in Wave 1 (contracts K3). This epic adds `subrole` and `isSecure` to `AXElementInfo` (§3.1) and a minimal macOS adapter that answers only point queries (`elements(inWindowOf:)` throws `unsupported`). One lookup in flight, 250 ms timeout, off the main actor. The Wave 2 AX epic absorbs the adapter. | The port already exists. A point query is all the timeline needs. [Low: the Wave 2 epic replaces one file.] |
| V4 | **Typed text can't be represented in the timeline.** `TimelineKey`'s only initializer rejects any press that isn't a shortcut or a non-text key; `TimelineElement`'s initializer has no text parameter and returns nil for secure fields. Decoding re-runs the same initializers. A Linux test types a known password and sentence through the whole recorder and greps the written bytes (§7.4). The overlay's "Show all keystrokes" never reaches the timeline. | `design/11` §6: "data the user typed must never leak into output". A rule in the type can't be forgotten by a later caller. [Low] |
| V5 | **The timeline is stored by capture identity, not beside the `.mp4`**: `~/Library/Application Support/dev.msenechal.bugeye/Timelines/<CaptureID>.timeline.jsonl` (under the contract's `CaptureFolders.applicationSupport`), versioned JSON Lines (§7). It is deleted when a `deleted` event for that capture reaches the bus. | A sidecar beside the file would need Quick Access's Save, Move and Delete to know about it (cross-epic coupling), would clutter `~/Pictures/Bugeye`, and would travel with the movie when you drag the folder somewhere. The `CaptureID` xattr already follows the file. [Low: if you want a visible sidecar, it's one path function. Orphans: a recording deleted in Finder leaves its timeline; the Wave 2 index can sweep them.] |
| V6 | **Timeline clock = video time.** `t` is integer milliseconds on the output timeline: 0 is the first video frame, paused spans are removed, input captured during a pause or before the first frame is dropped. The same `RecordingClock` maps both samples and input. Cursor sampled at 30 Hz, only when it moved ≥ 0.5 pt. Size cap 64 MiB (§7.3). | Zoom and captions are planned against frames; one clock means no drift maths later. 30 Hz ≈ 5 MB per hour of motion. [Low] |
| V7 | **Recording's macOS code lives in `Sources/BugeyeApp/Recording/`**, including its adapters (stream + writer, finalizer, camera, input monitor, devices, disk). Only two adapters go to `MacAdapters`, in Recording-owned folders: the AX point reader (`Accessibility/`) and `MediaPermissions` (`Permissions/`), whose ports are `BugeyeCore` ports (Recording-owned in Wave 1, contracts K3). The overlay window draws through the Editor's display-list executor (`MacAdapters/DisplayList/`, contracts K10); it never has its own. Recording-only interfaces are internal protocols of the shell with fakes for macOS tests; the core has no recording ports at all, because the reducer only emits effects. | `MacAdapters` depends on `BugeyeCore` only (Wave 0 P14), but the writer needs `RecordingClock` and `RecordingGeometry` from `RecordingCore`. [Low: Wave 4's guide reuses recording through the shell.] |
| V8 | **Keep the two-step `.mov` → `.mp4` design**, with a deadline (60 s + half the duration) and progress in the ● menu. A missed deadline or failure delivers the `.mov`. Mixing at capture time is not done. | Fragmented `.mov` survives a crash; SCK delivers mic and system audio as separate streams with separate clocks. `design/04` §5.3 allows keeping it "with a timeout and progress". [Low] |
| V9 | **No Format control in Wave 1.** The bar has no MP4/GIF segment and the ⚙ menu has no GIF rows. `recording.format`, `recording.gifWidth`, `recording.gifFps` are reserved keys. The Wave 2 Trim + GIF epic adds the segment between Record and Mic. | GIF is a later epic (B1). [Low] |
| V10 | **Window recordings include the window's child windows**: windows of the same process at layer > 0 (menus, pop-ups, sheets) whose frame intersects the followed rect, re-evaluated on each follow tick with `updateContentFilter`. | `design/04` §5.3. Menus were the main known gap (§4). [Low: if a filter update drops more than 2 consecutive frames (V23), drop back to the window alone.] |
| V11 | **The stream starts during the countdown**, frames discarded until the countdown ends; the take begins at the next complete frame after it. Permission and stream failures surface during the countdown. | Hides SCK's start latency; the recording starts on "1" running out, not a beat later. Mic indicator lights 3 s early. [Low] |
| V12 | **Recordings follow the Capture pane's "Copy to clipboard" and "Save to folder"** (read through the contract's `OutputSettings`). "Downscale" doesn't apply. The clipboard gets the file reference only. | "Delivered like a capture" (`design/04` §1.6). One pane, no duplicate toggles. [Low] |
| V13 | **Accessibility gates keys and elements, nothing else.** Keys (badge and timeline) and element lookups need it; clicks, cursor, scrolls and focus need no permission. Input Monitoring is not requested. With Accessibility granted, the timeline records shortcuts even when the Keys toggle is off. A hidden key `recording.timeline` (default true) turns the timeline off. | Global key monitors are covered by Accessibility. The timeline is invisible, so it shouldn't depend on a visible toggle. [Low: confirmed in the Mac batch.] |
| V14 | **Window titles are never recorded** (focus events carry bundle id, app name, window id and frame). Element titles are kept, trimmed to 120 characters. | Titles carry document names, mail subjects and URLs; captions need button names, not window names. [Low] |
| V15 | **A take left behind by a crash is recovered at launch**: a `.mov` in the in-progress folder with no live take is delivered as a `.mov` named by its creation time, with a notice (§5.7). | The 2 s fragments exist to make that file playable; without recovery it rots in Caches. [Low] |
| V16 | **Testing split** (§9): the reducer, clock, geometry, overlay logic, timeline and privacy filter on Linux; windows, the writer and finalizer with synthetic samples, and the status item on hosted macOS CI; real ScreenCaptureKit, audio, camera, overlays in the video and permissions in the Mac batch and your manual pass. `needs-mac-check` goes on this epic's wiring PR and on later PRs that change the wired feature, not before (V19, contracts §9). | Hosted runners can't grant Screen Recording, microphone or camera (`design/14` R8, R9). [Low] |
| V17 | **New strings the docs don't give**, settled in §5: start failure, delivery failure, the disk-stop body, Restart/Discard informative text, finishing progress, recovery, tooltips for the bar's toggles when available, status-item accessibility labels. | `design/11` §7. [Low] |
| V18 | **Reconciled with the Wave 1 contracts spec** (27 Nov 2026). §3 is now a list of what this epic uses from it, plus the shapes it owns. Changed: the writer's `adopt` is the contract's `CaptureFileWriter.move(_:into:named:identity:)`, which adds ` (2)` itself; `CaptureFileNamer.name` has no `attempt`; Recording's `TerminationCoordinator` is the contract's `TerminationGate.addFinish`; the router is `ActionRouter`; wiring is `RecordingWiring.modules` + `install`; the Settings pane goes through `settingsPanes`. Moved out of the contracts PR into Recording-owned folders: `MediaPermissions`, the `AXElementInfo` fields, `MediaTime`, the timeline schema. New: Recording sets the thumbnail's `▶` badge as a `mediaBadge` decoration (contracts K12, §6 item 1), and its overlay uses the Editor's executor. No settled string changed. | One contract for five parallel epics. [Low] |

Rulings added after the Wave 1 spec review (28 Nov 2026), one per finding (cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| V19 | **Wave 1 sequencing** (contracts §9). Branches are `feat/wave1-recording-<slice>`, fix and stacked PRs included; the ledger is `docs/ledgers/wave-1-recording.md`, with backlog items under `Backlog:`. The wiring PR merges after Capture's and Quick Access's; the overlay PR after the Editor's executor PR. `needs-mac-check` goes on the wiring PR and on later PRs that change the wired feature; its batch first runs the stream, camera and microphone adapter tests hosted CI can't. The wiring PR's description ends with a `CLAUDE.md changes` block; Recording never edits `CLAUDE.md` or `docs/backlog.md`. | Wave 1 spec review, findings 2, 3, 5, 7 and 30: the batch checks a Quick Access thumbnail, and nothing is reachable before the wiring PR. [Low] |
| V20 | **An area result is stored as is.** The selector's `.area` carries a `StoredArea` with the display's size (contracts K29), so Recording reads no screen itself. | Wave 1 spec review, finding 13. [Low] |
| V21 | **`starting` holds `recording`, not `recordingSetup`** (contracts K32). The countdown's end switches the activity, so screenshots work from then on, as `design/04` §1.1 says; `starting`'s failure and cancel paths end `recording`. | Wave 1 spec review, finding 20: the contract's table and §6 item 3 disagreed on `starting`; this keeps the documented boundary. [Low] |
| V22 | **The countdown panel takes Esc itself:** it can become key, is made key without activating Bugeye, and handles `keyDown` 53 and `cancelOperation(_:)`. | Wave 1 spec review, finding 28: the bar closes at Record, so Esc could reach the frontmost app. `design/04` §2.5's `CountdownWindow` took Esc through both; making it key, like the options bar, is what lets it. [Low] |
| V23 | **V10's fallback threshold:** a filter update that drops more than 2 consecutive frames. | Wave 1 spec review, finding 29: "stutters" had no number. [Low] |
| V24 | **`NoFreeName` in the save folder counts as an unusable folder** at delivery, as in Capture §5.4; the writer's errors in `<error>` notices are settled text (contracts K30). | Wave 1 spec review, finding 15. [Low] |

## 2. Scope

In scope:
1. Nothing shared: what Recording uses from other epics and the shell comes from the Wave 1 contracts PR (§3); the ports only Recording uses are in its own folders (§3.1).
2. ⇧⌘5 and the menu item Record Screen; selection through Capture's overlay (area, display, window, last area); the options bar; the 3 · 2 · 1 countdown; ● menu with Pause, Resume, Stop, Restart, Discard; ⌘Q waits for a recording.
3. Recording: ScreenCaptureKit stream, `.mov` writer, MP4 conversion with one mixed audio track, H.264 / HEVC, window following, disk guard, failure handling, crash recovery.
4. Overlays: click rings, keystroke badge, webcam bubble.
5. Delivery: naming, save or temp folder, clipboard, the thumbnail's `▶ mm:ss` badge (a `mediaBadge` decoration), `created` on the bus with a first-frame preview and the duration.
6. The event timeline (§7).
7. The Recording settings pane; microphone, camera and Accessibility permission handling in the bar.

Out of scope: trim, GIF recording and export (Wave 2); captions, auto-zoom, compositor (Wave 3); Record Guide (Wave 4); recording provenance (`design/06`, Wave 2); Quick Access's thumbnail and buttons (Quick Access draws them; Recording only supplies the badge's text as a decoration, contracts K12); the Settings Setup section (Capture C14); Open Last Capture playback.

## 3. Uses from the contracts

Everything in this list is in `docs/specs/2026-11-27-wave-1-contracts.md` and lands in the Wave 1 contracts PR, which merges before any epic starts. Recording never edits a contract file; after the merge it writes only the folders that spec's §3 gives it. Section numbers below are the contracts spec's.

- **Bus and items** (§4.1.1): `CaptureItem` with `duration` (seconds; nil for stills) and `CaptureKind.recording`, whose `fileExtension` (`mp4`) is only the default: the extension of `fileURL` is authoritative, so a `.mov` fallback stays `.mov` through Quick Access's Save. Recording publishes `CaptureEvent(change: .created, item:, preview:, origin: "recording")`, `pixelsPerPoint` = the stream's pixel scale, `preview` = the first frame at most `CaptureEvent.previewMaxWidth` (480) px wide through `PixelBufferImages.preview` (nil if it can't be read). It subscribes for `deleted` of `.recording` items to delete their timeline (V5). No new `CaptureChange`.
- **Delivery** (§4.1.2–4.1.4): `CaptureFileWriter.move(take, into: folder, named: name, identity: .new(id))`, which never replaces a file and adds ` (2)` itself, copying across volumes when needed; `CaptureFileNamer.name(kind: .recording, date:, fileExtension:)`; `CaptureFolders.temp`, `.recordingsInProgress` and `.applicationSupport`; `OutputSettings` (V12); `OutputStrings` (the `Couldn't save to folder` notice).
- **Decoration** (§4.2.3): before publishing `created`, `thumbnailDecorations.set([.mediaBadge(text: "▶ " + MediaTime.text(seconds: duration))], for: id, from: "recording")` (K12).
- **Selection and gating** (§4.1.8): `AreaSelector` (through `AppContext.areaSelector`, Capture's implementation once its last PR lands), `SelectionPurpose`, `SelectionRequest`, `SelectionResult`, `StoredArea` (the `recording.lastArea` JSON), `FakeAreaSelector`; `ScreenActivity` (`recordingSetup`, `recording`, `allows(.startRecording)`). Capture's side of the selector is Capture §6.1.
- **Permission** (§4.1.5, §4.5): `ScreenCapturePermission.preflight()` and `FakeScreenCapturePermission`; Capture's Screen Recording alert through `AppContext.screenRecordingAlert.show()`.
- **Drawing** (§4.1.5, §4.1.7, §4.4): the display list (`fillPath`, `strokePath`, `textRun`, `VectorPath.ellipse(in:)`, `roundedRect`), `TextMeasuring` + `FakeTextMeasurer` + `CoreTextMeasurer` for the keystroke badge; the executor is the Editor's (`MacAdapters/DisplayList/`, contracts K10).
- **Shell** (§4.2, §4.5): `HotkeySpec.title`, `MenuItemSpec.hotkeyID`, `HotkeyBindings.current` (the ● menu's `Stop` shows the current ⇧⌘5 binding); `ActionRouter` (`onMenuItem` for Record Screen and every override-menu entry, `onHotkey` for `recording.toggle`); `StatusItemOverride` and `AppContext.statusItem.setOverride(_:owner: "recording")`; `TerminationGate.addFinish` (its participant sends `quitRequested` and returns on `allowQuit`; editors are asked first, K11); `NightChrome` (options bar, countdown); `RecordingWiring` (`modules`, `install`, `onLaunch` for crash recovery); `settingsPanes` for the Recording pane; `Notifier`, `ClipboardWriter` and their adapters.
- **Resources** (§4.6): `NSMicrophoneUsageDescription` = `Bugeye records your microphone only when you turn on Mic for a recording.` and `NSCameraUsageDescription` = `Bugeye shows your camera only when you turn on Cam for a recording.`; the fixture app's `Password` field and `Play Click` button.

### 3.1 Shapes Recording owns in shared targets

Single-epic ports live in folders this epic owns (contracts K3, §4.1.9). Each change after the contracts PR is a ruling in this epic's ledger, not a contract amendment.

```swift
// Sources/BugeyeCore/Ports/Accessibility/AXReader.swift (moved there unchanged by the contracts PR).
// AXElementInfo gains two fields; old call sites still compile.
public struct AXElementInfo: Hashable, Sendable {
    public var role: String
    public var subrole: String?            // new: "AXSecureTextField", "AXSearchField", …
    public var title: String?
    public var text: String?
    public var frame: Rect2D
    public var isTextEntry: Bool
    public var isSecure: Bool              // new: a secure field; forces title and text to nil
    public init(role: String, subrole: String? = nil, title: String?, text: String?, frame: Rect2D,
                isTextEntry: Bool, isSecure: Bool = false)
}

public protocol AXReader: Sendable {
    /// `point` and the returned `frame` are Quartz global points (top-left of the primary display).
    /// Returns nil when nothing is there or Accessibility isn't granted. Reads AXRole, AXSubrole,
    /// AXTitle (else AXDescription); never AXValue, AXSelectedText or AXPlaceholderValue for text entry.
    func element(at point: Point2D) async throws -> AXElementInfo?
    func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo]
}

// Sources/BugeyeCore/Ports/Recording/MediaPermissions.swift
public enum MediaPermission: String, Hashable, Sendable, CaseIterable { case microphone, camera, accessibility }
public enum PermissionState: String, Hashable, Sendable { case granted, denied, notDetermined }

public protocol MediaPermissions: Sendable {
    func state(_ permission: MediaPermission) -> PermissionState
    /// Shows the system prompt where macOS has one (microphone, camera: AVCaptureDevice.requestAccess;
    /// accessibility: AXIsProcessTrustedWithOptions with prompt) and returns the state afterwards.
    /// Accessibility returns its current state at once; the user grants it later in System Settings.
    func request(_ permission: MediaPermission) async -> PermissionState
}

// RecordingCore: one formatter for the ● timer and the ▶ badge.
public enum MediaTime {
    /// "00:07", "12:34", "1:02:03" (h:mm:ss from one hour). Truncates to whole seconds.
    public static func text(seconds: Double) -> String
}
```

- Rule test: an `AXElementInfo` with `isSecure: true` has nil `title` and `text`. Adapters: `Sources/Mac/MacAdapters/Accessibility/AXPointReader.swift` (V3) and `Sources/Mac/MacAdapters/Permissions/SystemMediaPermissions.swift`. Fakes: `FakeMediaPermissions` (`Sources/BugeyeTestSupport/Recording/`) and `FakeAXReader` with scripted delays (`Sources/BugeyeTestSupport/Accessibility/`).
- No Input Monitoring, no entitlements (the app isn't sandboxed or hardened-runtime signed).
- **The timeline schema** (`Sources/BugeyeCore/Timeline/EventTimeline.swift`, Recording-owned): the Codable line types of §7, `TimelineKey`, `TimelineElement`, `TimelineModifier`, and `EventTimeline.url(for: CaptureID, home: String) -> URL` under `CaptureFolders.applicationSupport`. It is in `BugeyeCore` because `MotionCore` (Wave 3) and `GuideCore` (Wave 4) read it and area cores can't depend on `RecordingCore` (Wave 0 P14); no other Wave 1 epic reads it, so it isn't contract.
- **Registrations**, through `RecordingModule` (in `RecordingCore`) and `RecordingWiring`: menu item `recording.record` `Record Screen`, slot `.record` order 0, `hotkeyID: "recording.toggle"` so it shows the current binding (order 10 stays free for Record Guide); `HotkeySpec(id: "recording.toggle", title: "Record Screen", defaultKey: ⇧⌘5, settingKey: "recording.hotkey.toggle")`, which also puts it in Capture's Shortcuts pane, its registrar and its macOS-conflict check (entry 184); settings section `recording` `Recording`, order 30. The status-item badge is drawn by the shell from the override (contracts §4.5); the ticker runs in `.common` modes.

## 4. Settings

Pane `Recording` (module `recording`, order 30):
- `Video format`: `H.264 (plays everywhere)` / `HEVC (smaller, full 5K/6K resolution)`. Note: `H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304.`
- `Show all keystrokes (not just shortcuts)`. Note: `Off: only presses with ⌘ or ⌃ appear, so what you type (including ⌥ symbols) stays private.`

| Key | Type | Default |
|---|---|---|
| `recording.fps` | Int (30, 60) | 30 |
| `recording.quality` | String (`standard`, `high`) | `standard` |
| `recording.mic` / `.systemAudio` / `.clicks` / `.keys` / `.camera` | Bool | false |
| `recording.micDevice` / `.cameraDevice` | String (device unique id; empty = default) | empty |
| `recording.bubbleSize` | String (`small`, `medium`, `large`) | `medium` |
| `recording.codec` | String (`h264`, `hevc`) | `h264` |
| `recording.showAllKeys` | Bool | false |
| `recording.lastArea` | String (`StoredArea` JSON) | empty |
| `recording.hotkey.toggle` | String | `⇧⌘5` |
| `recording.timeline` | Bool, hidden (V13) | true |
| `recording.format`, `.gifWidth`, `.gifFps` | reserved for Wave 2 (V9) | |

Invalid stored values fall back to defaults. Settings are read fresh when the bar opens and written on every change (only the changed key).

## 5. Behaviour

### 5.1 Starting

1. **⇧⌘5** or **Record Screen**. Ignored (logged `busy`) when `ScreenActivity` refuses `.startRecording`. Without Screen Recording (`ScreenCapturePermission.preflight`): Capture's alert (`screenRecordingAlert.show()`), nothing else.
2. Recording calls `select` with: purpose `.recording`, hint `Drag an area · Click to record this display · Space: pick a window · Esc to cancel` (`design/02` §1.2), `clickSelectsDisplay` and `windowNeedsDisplayCentre` true, `lastArea` = `recording.lastArea`. So: drag an area, click for the whole display, Return for the last recording area, Space for window mode, Esc / right-click / ⇧⌘5 to cancel.
3. An area result (dragged or Return) is a `StoredArea` (contracts K29), stored as is as `recording.lastArea` (V20). A window result becomes the display holding its centre, with its frame followed (§5.5).
4. A **border** marks the target: 2 pt white dashed (6 on, 4 off) while configuring, solid `systemRed` 2 pt while recording, 3 pt outside the area (inset 3 pt for a whole display). Borderless, click-through, `.statusBar` level, never in the video.
5. The **options bar** opens under the selection, 12 pt away; above it if it doesn't fit; inside the bottom edge for a whole display; re-placed whenever its width changes (`OptionsBarPlacement`).
6. **Record** (or Return): checks disk space, then a **3 · 2 · 1** countdown centred in the area, one second per digit: a 140 × 140 pt non-activating panel, night gradient, 28 pt corners, 72 pt bold digits in the accent colour. Esc or ⇧⌘5 cancel during the bar and the countdown. The countdown panel has `canBecomeKey = true`, is made key when shown (without activating Bugeye) and takes Esc through both `keyDown` (53) and `cancelOperation(_:)`, as `design/04` §2.5's `CountdownWindow` did (V22). The stream starts with the countdown (V11).
7. Recording begins at the first complete frame after the countdown: the border turns red, the status item shows `● 00:00`.

### 5.2 The options bar

A floating night panel (dark gradient): `NSPanel` `[.nonactivatingPanel, .borderless]`, `.statusBar` level, `canBecomeKey`, `hidesOnDeactivate = false`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`. Esc through both `keyDown` (53) and `cancelOperation(_:)`. Left to right:

| Control | Label | Tooltip (when available) | When unavailable |
|---|---|---|---|
| Record | `● Record`, red, default button | `Start recording (Return)` | |
| Mic | `Mic`; when on, a picker `Default` + device names | `Record your voice` | Denied: disabled, `Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.` First use asks for permission. |
| System audio | `System audio` | `Record the sound your Mac plays` | |
| Cam | `Cam` + a ⌄ menu: `Size` ▸ `Small` / `Medium` / `Large`; `Camera` ▸ names (only with more than one) | `Show your camera in a bubble` | No camera: disabled, `No camera found.` Denied: disabled, `Camera access is off. Turn it on in System Settings → Privacy & Security → Camera.` First use asks; the bubble appears at once. |
| Keys | `Keys` | `Show the shortcuts you press` | Without Accessibility, turning it on shows the system prompt; tooltip `Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again.` |
| Clicks | `Clicks` | `Highlight mouse clicks` | |
| ⚙ | menu: `Frame rate` ▸ `30 fps` / `60 fps`; `Quality` ▸ `Standard` / `High` | `Recording options` | |
| ✕ | | `Cancel (Esc)` | |

What is recorded is `effectiveOptions(options, permissions, devices)`: mic off without permission, keys off without Accessibility, cam off without permission or camera, an unknown device id → default.

### 5.3 While recording

- **Status item:** `● mm:ss` (`MediaTime`), red dot, monospaced digits; `❙❙ mm:ss` while paused, timer frozen; the hourglass while finishing. Accessibility labels: `Recording, <elapsed>`, `Recording paused, <elapsed>`, `Finishing recording`. Updated every 0.5 s by a timer in `.common` modes.
- **● menu:** `Pause` / `Resume`, `Stop` (shows ⇧⌘5), separator, `Restart`, `Discard`. While finishing: one disabled entry `Finishing… <n> %` (`Finishing…` until progress is known).
- **Restart** throws the take away and runs a new countdown; **Discard** throws it away and saves nothing. When the recording is longer than 10 s, both ask first (alert, Bugeye activated):
  - `Restart this recording?` / `What you've recorded so far will be thrown away.` / buttons `Restart`, `Cancel`.
  - `Discard this recording?` / `Nothing will be saved.` / buttons `Discard`, `Cancel`.
- **⇧⌘5** stops. **⌘Q** stops and saves first, and waits for a recording that is finishing.
- Paused time is cut from the file and the timeline.
- **Disk:** starting needs 1 GB free on the in-progress folder's volume; below 300 MB (checked every 5 s) the recording stops and keeps what was recorded.
- During set-up (selecting to the end of the countdown), screenshots are refused; during a recording ⇧⌘3/⇧⌘4 still work (`ScreenActivity`, contracts §4.1.8).

### 5.4 Overlays

- **Clicks:** each left click on the recorded display gets an animated yellow ring, right clicks a pink one: 14 → 28 pt, ease-out, fading over 0.5 s, 3 pt stroke and 25 % fill. Clicks on Bugeye's own windows don't ring.
- **Keystrokes:** a badge centred 40 pt above the bottom of the recorded area: 22 pt semibold white on 75 % black, 10 pt corners. Shortcuts only by default (⌘ or ⌃); everything with "Show all keystrokes". Modifiers in order ⌃ ⌥ ⇧ ⌘, space-separated (`⇧ ⌘ 3`, `⌘ Z ×3`). The key is its base character: the number row is its digit, non-Latin letters show the US letter of the key, Latin layouts keep their letters. Named keys: `↩ ⌤ ⇥ Space ⌫ ⌦ ⎋ ← → ↓ ↑ ↖ ↘ ⇞ ⇟ F1`–`F12`. The same label within 1.5 s shows `×N`; auto-repeat isn't counted. Visible 1.5 s, the last 0.3 s fading.
- **Webcam bubble:** round, mirrored, 3 pt white border, shadow; Small 120, Medium 180, Large 240 pt. Starts bottom-right of the area, 24 pt in. Drag anywhere; on release it snaps to the nearest corner (centred on an axis where the area is too small). Double-click cycles the size and saves it. Shown during set-up. A changed camera recreates the session; the bubble keeps its corner.
- The overlay window (rings, badge) and the bubble **are** in the video; the border, bar, countdown, ● menu, alerts, Quick Access and every other Bugeye window, including ones opened mid-recording, are **not** (the app is excluded with the overlay and bubble as exceptions). An exception window missing from SCK's list is logged.

### 5.5 Window recording

Records the window, its child windows (V10) and Bugeye's overlays; windows in front are never captured. The source rect follows the window 10 times a second at its starting size (a resize crops or shows background), clamped into the display. Closed or minimised: no new frames. Border, badge and bubble follow.

### 5.6 The result

- `.mov` in `~/Library/Caches/dev.msenechal.bugeye/Recordings/Take-<uuid>.mov`, 2 s fragments, H.264 or HEVC with BT.709 tags, one AAC track per audio source; then converted to `.mp4` (video passthrough, one mixed AAC 48 kHz stereo 160 kbit/s track), with the V8 deadline. Codec limits, even dimensions, bitrate (`w × h × fps × 0.06` Standard, `0.12` High, clamped 2–100 Mbit/s) as `design/04` §2.6–2.7.
- **Name** `Recording YYYY-MM-DD at HH.MM.SS.mp4` from the first frame's time (`CaptureFileNamer`), ` (2)` etc. on a clash (added by `CaptureFileWriter.move`). `createdAt` is the same moment.
- **Delivery**, in order: `CaptureFileWriter.move` into the save folder (or the temp folder when "Save to folder" is off, or with Capture's `Couldn't save to folder` notice, `OutputStrings`, when the folder is unusable: missing, unwritable, or `NoFreeName` there, V24) with a new `CaptureID`; the file reference on the clipboard if "Copy to clipboard" is on; the timeline moved to its store under that id; the `▶` badge decoration set; `created` published (§3).

### 5.7 Notices

Through `Notifier`, title / body:

| Case | Title | Body |
|---|---|---|
| Less than 1 GB free at Record (the bar stays) | `Not enough disk space` | `Free at least 1 GB to start a recording.` |
| Below 300 MB while recording | `Recording stopped: disk almost full` | `What was recorded has been kept.` |
| Stream or writer failed while recording | `Recording stopped` | `<error> What was recorded has been kept.` |
| Stream failed before the first frame (not a permission error) | `Couldn't start recording` | `<error>` |
| Conversion skipped (movie size + 50 MB not free), failed or timed out | `Recording saved as a QuickTime movie` | `There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime.` |
| No frame recorded | `Nothing was recorded` | `The recording stopped before the first frame.` |
| Camera can't open or was taken | `Camera unavailable (in use by another app?)` | `Cam has been turned off.` |
| Even the temp folder refused the file | `Couldn't save the recording` | `It is still in <path>.` (`~/…` form; the take is not deleted) |
| A crashed take found at launch (V15) | `Recovered a recording` | `Bugeye quit while recording. What was recorded has been kept.` |

`<error>` is the error's `localizedDescription`, ending with a full stop. A permission error (`userDeclined`) shows Capture's Screen Recording alert instead.

## 6. The recording state machine

`RecordingFlow` in `RecordingCore`: pure, no AppKit, tested on Linux. Every async event carries the `SessionID` that asked for it; `next` returns no transition for an event that means nothing in the current state, and the shell ignores it.

**States:** `idle` · `selecting(s)` · `configuring(s, target, options)` · `countingDown(s, target, options, remaining ∈ {3, 2, 1}, recorderReady: Bool)` · `starting(s, target, options)` · `recording(s, take)` · `paused(s, take)` · `finishing(s, step ∈ {stopping, converting, delivering}, notice?)`. Flags beside the state: `quitPending`, `confirming: (s, restart | discard)?`. `target` is `area(display, rect)`, `display(display)` or `window(id, display, frame)`.

**Events:** `toggle(screenPermitted, activityAllows)` (⇧⌘5, Record Screen, Stop) · `selected(s, SelectionResult)` · `option(s, change)` · `permissionAnswered(s, permission, state)` · `record(s, freeBytes)` · `cancel(s)` (✕, Esc) · `countdownTick(s)` · `recorderReady(s)` · `recorderFailed(s, error)` · `takeStarted(s, hostTime, date)` · `pause(s)` · `resume(s)` · `restart(s)` · `discard(s)` · `confirmed(s, kind)` / `declined(s, kind)` · `tick(s, hostNow)` · `diskChecked(s, freeBytes)` · `cameraUnavailable(s)` · `targetGone(s)` · `stopped(s, .movie(url, duration) | .noFrames)` · `converted(s, url, isMov)` · `delivered(s, CaptureItem?)` · `quitRequested`.

**Effects:** `selection(request)` · `cancelSelection` · `activity(begin | end, kind)` · `showBorder(target, dashed | recording)` · `closeBorder` · `showBar(options, effective)` · `updateBar` · `closeBar` · `bubble(BubbleChange)` · `countdown(digit)` · `closeCountdown` · `prepareRecorder(s, request)` · `beginTake(s)` · `pauseRecorder(s)` · `resumeRecorder(s)` · `stopRecorder(s)` · `cancelRecorder(s)` (deletes the `.mov`) · `overlays(start | stop, clicks, keys)` · `inputMonitor(start | stop)` · `timeline(start(header) | finish | discard)` · `ticker(start | stop)` · `statusItem(StatusItemOverride?)` · `confirm(s, kind)` · `convert(s, url, deadline)` · `deliver(s, url, date, duration)` · `persist(key, value)` · `storeLastArea` · `requestPermission(kind)` · `notify(title, body)` · `screenPermissionAlert` · `diskCheck` · `allowQuit` · `log(category, message)`.

| From | Event (guard) | To | Effects |
|---|---|---|---|
| idle | `toggle`, activity refuses | idle | `log(busy)` |
| idle | `toggle`, not permitted | idle | `screenPermissionAlert` |
| idle | `toggle` | selecting(s+1) | `activity(begin, recordingSetup)`, `selection`, `log(begin)` |
| selecting | `selected(cancelled \| busy)` | idle | `activity(end, recordingSetup)` |
| selecting | `selected(area \| display \| window)` | configuring | `storeLastArea` (area only), `showBorder(dashed)`, `showBar`, `bubble` if cam on |
| selecting | `toggle` | idle | `cancelSelection`, `activity(end, recordingSetup)` |
| configuring | `option` | configuring | `persist`, `updateBar`, `bubble`, `requestPermission` on a first use |
| configuring | `record`, free < 1 GB | configuring | `notify(Not enough disk space)` |
| configuring | `record` | countingDown(3, false) | `closeBar`, `countdown(3)`, `prepareRecorder` (from effective options) |
| configuring | `cancel`, `toggle`, `targetGone` | idle | *teardown* |
| countingDown | `countdownTick`, remaining > 1 | countingDown(−1) | `countdown(n)` |
| countingDown | `recorderReady` | same, ready | none |
| countingDown | `countdownTick`, last, ready | recording | *countdown ends*, *go live* |
| countingDown | `countdownTick`, last, not ready | starting | *countdown ends* |
| starting | `recorderReady` | recording | *go live* |
| countingDown, starting | `recorderFailed(userDeclined)` | idle | `cancelRecorder`, *teardown*, `screenPermissionAlert` |
| countingDown, starting | `recorderFailed(other)` | idle | `cancelRecorder`, *teardown*, `notify(Couldn't start recording)` |
| countingDown, starting | `cancel`, `toggle`, `targetGone` | idle | `cancelRecorder`, *teardown* |
| recording | `pause` | paused | `pauseRecorder`, `statusItem(paused)` |
| paused | `resume` | recording | `resumeRecorder`, `statusItem(recording)` |
| recording, paused | `tick` | same | `statusItem(elapsed)`; every 10th tick `diskCheck` |
| recording, paused | `restart` / `discard`, elapsed > 10 s | same | `confirm(s, kind)` |
| recording, paused | `restart` (or `confirmed(restart)`) | countingDown(s+1, 3, false) | *wind down*, `cancelRecorder(s)`, `timeline(discard)`, `showBorder(dashed)`, `activity(end, recording)`, `activity(begin, recordingSetup)`, `countdown(3)`, `prepareRecorder(s+1)` |
| recording, paused | `discard` (or `confirmed(discard)`) | idle | *wind down*, `cancelRecorder`, `timeline(discard)`, `closeBorder`, `activity(end, recording)` |
| recording, paused | `toggle` | finishing(stopping) | *wind down*, `closeBorder`, `stopRecorder` |
| recording, paused | `recorderFailed`, `diskChecked` < 300 MB | finishing(stopping, notice) | same as `toggle` |
| recording, paused | `cameraUnavailable` | same | `bubble(remove)`, `persist(camera, false)`, `notify(Camera unavailable …)` |
| finishing(stopping) | `stopped(movie)` | finishing(converting) | `timeline(finish)`, `convert(deadline)` |
| finishing(stopping) | `stopped(noFrames)` | idle | `timeline(discard)`, `notify(Nothing was recorded)`, *done* |
| finishing(converting) | `converted` | finishing(delivering) | `deliver`; `notify(QuickTime movie)` if `.mov` |
| finishing(delivering) | `delivered` | idle | the pending notice, *done* |
| idle | `quitRequested` | idle | `allowQuit` |
| selecting … starting | `quitRequested` | idle | as `cancel`, then `allowQuit` |
| recording, paused | `quitRequested` | finishing, `quitPending` | as `toggle` |
| finishing | `quitRequested` | same, `quitPending` | none |
| any | event with another session | same | none, except `recorderReady` → `cancelRecorder(that session)` |
| any | `confirmed` / `declined` not matching `confirming` | same | none |

*Countdown ends* (V21): `closeCountdown`, `activity(end, recordingSetup)`, `activity(begin, recording)`. *Go live*: `beginTake`, `showBorder(recording)`, `overlays(start)` if clicks or keys, `inputMonitor(start)`, `timeline(start)` unless `recording.timeline` is off, `ticker(start)`, `statusItem(● 00:00)`. *Wind down*: `ticker(stop)`, `inputMonitor(stop)`, `overlays(stop)`, `bubble(remove)`, `statusItem(finishing)` when stopping. *Teardown*: `closeBar`, `closeCountdown`, `closeBorder`, `bubble(remove)`, then `activity(end, recordingSetup)` from selecting, configuring or countingDown, or `activity(end, recording)` from starting (V21). *Done*: `statusItem(nil)`, `activity(end, recording)`, `allowQuit` if `quitPending`, `log(finish)`. `takeStarted` sets the take's clock origin; elapsed is `RecordingClock.elapsed(at: hostNow)`.

**Invariants** (each a test driving random event sequences, plus named regressions):
- R1. Every `toggle` that leaves `idle` returns to `idle` exactly once, on every failure path.
- R2. `recordingSetup` is held exactly in selecting … countingDown, `recording` exactly in starting … finishing (V21); each `begin` has one `end`.
- R3. At most one live recorder: each `prepareRecorder(s)` is followed by exactly one of `stopRecorder(s)` or `cancelRecorder(s)`, including a recorder that becomes ready for a stale session.
- R4. Bar only in configuring; countdown only in countingDown; border from configuring to the start of finishing (also across Restart); overlay window, bubble and input monitor closed on entering finishing, before `convert`.
- R5. The status override is set exactly in recording, paused and finishing, and cleared on reaching idle.
- R6. Every `timeline(start)` ends in exactly one `finish` or `discard`; a discarded take's timeline is never delivered.
- R7. After `quitRequested`, `allowQuit` is emitted exactly once, and in finishing only after `delivered`.
- R8. `prepareRecorder` uses `effectiveOptions`, never raw options.
- R9. Stale-session events produce no effect but R3's cancel.

Regression tests by name (`design/04` §3): `rapidTogglesLeaveNoStrayRecorder`, `aStaleFailureCannotStopARestartedTake`, `aFailureDuringTheCountdownIsNotMissed`, `quitWaitsForAFinishingRecording`, `recordingHotkeyIsIgnoredDuringAScreenshotSelection`, `overlaysCloseAtStopNotAfterConversion`, `toggleDuringSelectionCancelsIt`.

## 7. The event timeline

### 7.1 Location and life

- While recording: `~/Library/Caches/dev.msenechal.bugeye/Recordings/Take-<uuid>.timeline.jsonl`, beside the take's `.mov`.
- At delivery: moved to `~/Library/Application Support/dev.msenechal.bugeye/Timelines/<CaptureID>.timeline.jsonl` (V5). Restart, Discard, "Nothing was recorded": deleted. A `.mov` fallback keeps its timeline. A recovered take (V15) brings its timeline, without an `end` line.
- Written by `TimelineRecorder` (an actor in `RecordingCore`): lines buffered and appended every second off the main actor, `fsync` at `finish`.

### 7.2 Format: versioned JSON Lines

One JSON object per line, UTF-8, `\n`-terminated, keys in the order shown. Readers skip unknown kinds and unknown keys, refuse a `version` they don't know, and drop a partial last line. Line 1 is the header; then events; the last line is `end`.

```jsonc
{"format":"dev.msenechal.bugeye.timeline","version":1,"take":"<uuid>","startedAt":"2026-11-27T14:03:12.481Z",
 "target":{"kind":"area","display":69734272,"scale":2,"window":null,"area":{"x":120,"y":80,"w":1280,"h":720}},
 "video":{"w":2560,"h":1440,"fps":30},"cursorHz":30,"has":{"keys":true,"elements":true}}
{"t":0,"k":"move","x":402.5,"y":311}
{"t":1450,"k":"down","id":1,"b":"l","x":640,"y":42,"n":1}
{"t":1532,"k":"up","id":1,"b":"l","x":640,"y":42}
{"t":1450,"k":"element","click":1,"role":"AXButton","subrole":null,"title":"Save","frame":{"x":610,"y":30,"w":60,"h":24}}
{"t":2210,"k":"element","click":2,"status":"withheld"}
{"t":3020,"k":"scroll","x":700,"y":400,"dx":0,"dy":-84}
{"t":4100,"k":"key","key":"S","mods":["cmd"]}
{"t":5003,"k":"focus","app":"com.apple.Safari","name":"Safari","window":4211,"frame":{"x":0,"y":-25,"w":1280,"h":800}}
{"t":6000,"k":"area","x":140,"y":80,"w":1280,"h":720}
{"t":7311,"k":"pause"}
{"t":7311,"k":"resume"}
{"t":9020,"k":"trunc","reason":"cursor"}
{"t":12840,"k":"end","events":412}
```

- **`t`**: integer milliseconds of video time (V6). Non-decreasing in file order, except `element` lines, which carry their click's `t` and are written when the lookup returns.
- **Coordinates**: points, one decimal, top-left origin, relative to the recorded area's top-left at that moment; they may fall outside it. The header's `area` (and `area` lines, when a followed window moves) are Quartz global points. `startedAt` is the first frame's wall clock (UTC, ms).
- **`move`**: sampled at 30 Hz, written only when the cursor moved ≥ 0.5 pt since the last line.
- **`down` / `up`**: `b` = `l`, `r` or `o` (other); `n` = click count; `id` pairs them and links `element`.
- **`element`**: either role, subrole, title (≤ 120 characters, `…` when cut), frame; or `status`: `withheld` (secure field), `none` (nothing there or no Accessibility), `timeout` (over 250 ms), `skipped` (a lookup was already in flight). Never a value or static text (V4).
- **`scroll`**: deltas in points, summed over at most 100 ms, at the position of the last event.
- **`key`**: §7.4. Auto-repeat is never written.
- **`focus`**: on app activation, and when the frontmost window of the active app changes (checked twice a second): bundle id, app name, window id, frame. No window title (V14).
- **`pause` / `resume`**: same `t`, marking a cut.
- **`trunc`**: §7.3. **`end`**: duration in ms and the number of event lines.
- Header `has.keys` / `has.elements` are false without Accessibility, so readers can tell "no shortcuts" from "not watched".

### 7.3 Size limits

At 48 MiB `move` lines stop (`trunc` `cursor`); at 64 MiB every event line stops (`trunc` `size`). 4 KiB is reserved so `end` is always written. No limit on recording length; 30 Hz motion is about 5 MB an hour.

### 7.4 Keys and privacy

`TimelineKey(key:modifiers:)` exists only when one of these holds:
- the key is a character (A–Z, 0–9, or one of ``` ` - = [ ] \ ; ' , . / ```, as its base character by the overlay's rules) **and** the modifiers include ⌘ or ⌃;
- the key is named: `Return`, `Enter`, `Tab`, `Delete`, `ForwardDelete`, `Escape`, `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown`, `F1`–`F12`, with any modifiers;
- the key is `Space` with ⌘ or ⌃.

`mods` are `ctrl`, `opt`, `shift`, `cmd`, in that order. ⇧- and ⌥-letters are typing and never recorded, whatever "Show all keystrokes" says.

`TimelineElement(info:origin:)` takes role, subrole, title and frame from `AXElementInfo`, ignores `text`, and returns nil for `isSecure` (written as `withheld`).

The privacy test (Linux, through `TimelineRecorder` and the writer, reading the file back as bytes): type `hunter2` into a secure element, `Correct Horse Battery!` into a text field with ⇧ and ⌥ variants, and ⌘S, ⌃C, ⇧⌘3, ↩ and ←, with `showAllKeys` on. The file contains `"key":"S"`, `"key":"C"`, `"key":"3"`, `Return` and `Left` and no other key lines; none of `hunter2`, `Correct`, `Horse`, `Battery`; an `element` line for the secure click with `withheld` and no title; and decoding a hand-written line `{"k":"key","key":"h","mods":[]}` drops it. A random-press property test checks the rule above for every written key.

## 8. Architecture

| Target | Platform | Recording's content |
|---|---|---|
| `BugeyeCore` | portable | Only its own folders (§3.1): `Ports/Accessibility/` (`AXElementInfo` fields), `Ports/Recording/` (`MediaPermissions`), `Timeline/` (`EventTimeline` schema). Everything else it uses is contract (§3) |
| `BugeyeFeatures` | portable | None: `StatusItemOverride`, `ActionRouter`, `TerminationGate` are contract |
| `BugeyeTestSupport` | portable | `Recording/`: `FakeMediaPermissions`; `Accessibility/`: `FakeAXReader` gains scripted delays. `FakeAreaSelector`, `FakeScreenCapturePermission`, `FakeTextMeasurer` are contract |
| `RecordingCore` | portable | `RecordingModule`; `MediaTime`; `RecordingFlow` (§6); `RecordingTarget`; `RecordingOptions`, `RecordingSettings`, `effectiveOptions`; `RecordingClock`; `RecordingGeometry` (output size, codec limits, even sizes, bitrate); `DiskGuard`; `OptionsBarPlacement`; `WindowFollow` and `ChildWindowFilter`; `BubbleLayout`, `BubbleChange`; `KeystrokeFormatter` (with the US base table), `KeystrokeBadge`, `ClickRings`, each drawing as a display list; `TimelineRecorder`, `TimelineWriter`, `TimelineStore` (move by `CaptureID`, delete on `deleted`); `TakeRecovery` (decides what a leftover take is); `RecordingStrings` |
| `MacAdapters` | macOS | `AXPointReader` (V3), `SystemMediaPermissions` |
| `BugeyeApp` | macOS | `Recording/`: `RecordingController` (executes effects, feeds events, owns sessions); `StreamRecorder` (SCK stream + `AVAssetWriter`, one serial sample queue, complete-frame filter, follow timer and child windows, pause stamps, failure latch, injectable `now` / sample entry); `MovieConverter` (passthrough + audio mix, concurrent pumps, deadline, progress); `FirstFrame`; `InputMonitor` (global monitors for mouse down/up, scroll, key down; 30 Hz cursor sampler; focus watcher); `BorderWindow`, `OptionsPanel` (SwiftUI), `CountdownPanel`, `OverlayWindow` (draws the display list through the Editor's executor, 60 Hz timer in `.common` modes, invalidated on close and deinit), `WebcamBubble`; `CaptureDevices`; `DiskSpace`; the Recording pane. `Wiring/RecordingWiring.swift` |

Main thread: only `RecordingFlow`, the windows and the bus. The stream, writer, converter, AX lookups, disk checks and timeline writes run off it.

**Logging** (`os.Logger`, subsystem `dev.msenechal.bugeye`). Never logged: key labels, element titles, window titles, device names.

| Category | Messages |
|---|---|
| `recording` | `begin <session>` · `busy: dropped toggle` · `target <area\|display\|window> on display <id>` · `stream <w>x<h> <fps> fps <codec> mic=<bool> system=<bool>` · `exception window <n> missing from the stream` · `first frame` · `pause` / `resume` · `stop <reason>` · `converted in <ms> ms` / `kept mov: <reason>` · `delivered <file name> <duration> s` · `failed: <error>` · `disk <free MB> MB` · `recovered <file name>` · `finish <session>` |
| `timeline` | `start <take>` · `finish <events> events <bytes> bytes` · `truncated <reason>` · `element lookup <ms> ms <status>` · `discarded <take>` |

## 9. Done when

1. The Wave 1 contracts PR has merged before this epic's first PR (it tests `ScreenActivity`, `CaptureFileWriter.move` including a clash and a failed cross-volume copy, `CaptureFileNamer`), and the session has checked §3's names against it. Branches: `feat/wave1-recording-<slice>` (fix and stacked PRs included); ledger `docs/ledgers/wave-1-recording.md`. Sequencing, merge order and Mac checks: contracts §9 (V19).
2. On every PR of the epic, marked ready for review (R10: drafts get no CI; the session's own `make test-core` is the check), `linux` and `macos` are green and `claude-review` has posted. Pushes are batched.
   - **Linux** covers §6 with R1–R9 and the named regressions; the `AXElementInfo` secure rule; `MediaTime`; the timeline schema's decoding and refusals; `effectiveOptions`; the clock (pause, samples captured in a pause, before the first frame); geometry, codec limits, bitrate; disk thresholds; bar placement; window follow and child windows; bubble layout and change; keystroke labels on US, AZERTY, German and Russian tables; ring and badge display lists (golden JSON); the timeline writer (every kind, sampling, coalescing, caps, `end` after a cap, crash-truncated reading); the §7.4 privacy test; take recovery; every string in §4–§5, character for character.
   - **macOS CI** covers the panel, border, countdown, overlay and bubble window properties; Esc through `keyDown` and `cancelOperation` after clicking a toggle; the status item's badge, labels and its ticker running while the menu is open; `StreamRecorder` with synthetic sample buffers (retiming, pause, dropped non-advancing frames, a failed writer's `finish` not raising, `noFrames`); `MovieConverter` on a generated `.mov` with two audio tracks (one AAC track out, video untouched, BT.709 kept, the deadline delivering the `.mov`); `FirstFrame`; the Recording pane; `NSEvent` → timeline input translation. One experiment: a 1 s `SCStream` recording, reported as skipped if the runner has no Screen Recording.
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. The Mac batch (`needs-mac-check` on the wiring PR, once Capture's and Quick Access's wiring PRs are on `main`, contracts §9) passes, driven by the fixture app and the debug channel (a `recording.state` command, contracts K23), after the stream, camera and microphone adapter tests hosted CI can't run:
   1. Area, display and window recordings on the Retina display and the 1× external, H.264 and HEVC: sizes, BT.709 tags, plays in QuickTime and Safari.
   2. Mic + system audio: one mixed track, in sync with a click sound from the fixture (within one frame).
   3. Overlays: rings, badge and bubble in the video; border, bar, countdown, ● menu and a Quick Access thumbnail opened mid-recording absent.
   4. Window recording: the fixture window moved and a menu opened during it; the window followed, the menu visible (V10).
   5. Timeline: clicks on the fixture's buttons give `element` lines with their titles; typing in the fixture's text field and a secure field writes no key or text; `t` of a click matches the frame where the ring appears within 50 ms.
   6. Permissions after `tccutil reset Microphone|Camera|Accessibility dev.msenechal.bugeye`: prompts on first use, disabled toggles with their tooltips after denial; global key monitoring works with Accessibility alone (V13).
   7. Kill Bugeye mid-recording, relaunch: the take is recovered (V15).
5. Your manual pass, `docs/checklists/wave-1-recording.md` (`design/11` §5 format): Before you start (quit the old app; Screen Recording granted; turn off macOS's ⇧⌘5) · Shortcuts table · How to check (`ls ~/Pictures/Bugeye`, `ls ~/Library/Caches/dev.msenechal.bugeye/Recordings`, `ls ~/Library/Application\ Support/dev.msenechal.bugeye/Timelines`, `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`) · A. Start: drag, click a display, Return, Space and a window, cancel each way · B. Bar: every toggle, devices, ⚙, placement, Esc · C. Countdown and cancelling it · D. Recording: timer, Pause, Resume, Stop, ⇧⌘5, ⌘Q while finishing · E. Restart and Discard, under and over 10 s · F. Overlays: rings, badge with "Show all keystrokes" off and on, bubble drag, snap, sizes, camera switch · G. Window recording · H. Result: names, save off, clipboard paste into Finder and Slack, `.mov` fallback (fill the disk), Quick Access thumbnail · I. Gating: ⇧⌘4 during set-up and during a recording · J. Recording pane.
6. You say "all good", and the last PR, which adds `RecordingModule` to `RecordingWiring.modules` and fills `RecordingWiring.install`, merges after Capture's and Quick Access's wiring PRs are on `main` (contracts §9), its description ending with a `CLAUDE.md changes` block. The overlay PR merges after the Editor's executor PR (contracts K10).
