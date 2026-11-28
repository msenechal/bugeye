# Wave 1 Capture ledger

Plan: `docs/plans/2026-11-28-wave-1-capture.md` · Spec: `docs/specs/2026-11-27-wave-1-capture.md` · Branches: `feat/wave1-capture-<slice>`

Trust this file and `git log` over memory.

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 8aef1be | draft PR #6 (`feat/wave1-capture-core`) |
| 2 | done | c899f0d | fakes' self-tests seen failing on the missing port names |
| 3 | done | d49a562 | |
| 4 | done | 0f21bd7 | |
| 5–6 | done | e1c55e8 | one test had a wrong expected display (its window centre was on the other display); test fixed |
| 7 | done | 1a3777d | 46 flow tests; the invariant checker was seen failing on two deliberate mutations (Esc not released on leave; `frozen` ignoring its session) before being kept |
| fix pass | done | 1290530 | PR #6 ready; linux https://github.com/msenechal/bugeye/actions/runs/46122731068 and macos https://github.com/msenechal/bugeye/actions/runs/46122731100 green; claude-review: "No findings." |
| 8–11 | done | b61184c | slice 2 (`feat/wave1-capture-controller`) |
| 12 | done | 0018f34 | see ruling on test order |
| 13 | done | 2e4ea30 | see ruling on test order |
| 14–15 | done | 12a155e | slice 3 (`feat/wave1-capture-mac`), not compiled here; manual macOS run https://github.com/msenechal/bugeye/actions/runs/46124357539 built and passed every test first time |

## Rulings

Plan rulings P1–P11 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: `ScreenSource` keeps `displays()` beside the new `freeze(displays:)` and `captureWindow(_:pixelSize:)` (C8): full screen needs the display under the pointer before it freezes. `ScreenSourceError` is the port's error type (`permissionDenied`, `displayNotFound`, `windowNotFound`, `failed(String)`); the adapter maps ScreenCaptureKit errors into it. (cost if wrong: none.)
- Ruling: `CaptureStrings` starts in slice 1 with the six `Capture failed` texts, because `CaptureFlow` posts them; slice 2 adds the rest. (cost if wrong: none.)
- Ruling: in window mode every display's overlay gets the hovered window's rect in its own display-local space (the view clips it), and redraws all displays when the hovered window changes, so a window spanning two displays is highlighted on both. (cost if wrong: none.)
- Ruling: a freeze that answers no frames counts as `displayNotFound` (`Capture failed` / `The display was disconnected.`); a selector request then answers `.cancelled`. (cost if wrong: low; unreachable with a connected display.)
- Ruling: a click on a window whose centre is on no display, for a selector request without `windowNeedsDisplayCentre`, answers `.window` with the clicked display. (cost if wrong: low; Recording always sets the flag.)

Final review of PR #6 (fresh reviewer, 28 Nov 2026): 0 Critical, 3 Important, 6 Minor. Fix pass:

- Ruling (review I1, Important): `finishing` records what it waits for (`.window(scale:)` then `.delivery`). `windowCaptured` / `windowCaptureFailed` are accepted only while a window capture is awaited and `delivered` only while a delivery runs, so a stray or duplicate result can't deliver twice or drop to `idle` mid-delivery. The invariant checker now fails on a second `deliver` in a session. Tests failed first. (cost if wrong: none.)
- Ruling (review I2, Important): every file of one full-screen press takes the earliest frame time (C10), so concurrent freezes stamped a few ms apart still share a name and get ` (2)` in display order. Test with differing frame times failed first. (cost if wrong: none.)
- Ruling (review I3, Important): `FakeScreenSource.hold()` / `release()` / `waitingCount` gate freezes and window captures, so slice 2 tests a cancel while one is in flight. Self-tests failed first (missing names). (cost if wrong: none.)
- Ruling (review M4): the pointer's display is found with closed edges (`CocoaRect.containsClosed`), since `NSEvent.mouseLocation` reports `y == maxY` on a display's top row. Test failed first. (cost if wrong: none.)
- Ruling (review M5, M6): `FlowEvent.mouseDragged` documents that its point is in the drag's starting view; `ScreenSource.displays()` documents that the adapter reads `NSScreen` (no shareable-content fetch) and that `SCDisplay.frame` is Quartz. (cost if wrong: none.)
- Ruling (review M7): `displaysChanged` while freezing is accepted as is: C16 covers the selection, and the selection that follows cancels on the next change; a display that vanished between freeze and crop posts `The display was disconnected.` (cost if wrong: low; a stale frame for one selection.)
- Ruling (review M8): a flow test drives the ⇧ lock through `mouseDragged` modifiers; the three write-failure strings are tested character for character in slice 2's `CaptureStringsTests`. (cost if wrong: none.)
- Ruling (review M9): the selector serves purposes other than `.screenshot` (the `AreaSelector` doc says they never deliver); a `.screenshot` request through `select` behaves like the others and only returns its result. No caller does this. (cost if wrong: low.)

Slice 2:

- Ruling: `CaptureController`'s and `ShortcutsModel`'s tests were written right after their code, not run red first (a background build held the package). Each was then checked against deliberate mutations: the controller suite fails when the screenshot activity isn't released (5 issues); the Shortcuts suite fails when a cleared binding reports unregistered or duplicates are accepted. (cost if wrong: low; the mutation checks show the tests can fail.)
- Ruling: the save folder is never created at capture time. A missing folder counts as unusable (temp + `Couldn't save to folder`), because creating it could put it on the boot volume under an unplugged disk's mount point; the shell already creates it at launch and when it's chosen. The temp folder is created on demand. (cost if wrong: low; a folder deleted while Bugeye runs gives the notice until the next launch or choice.)
- Ruling: `FakeCaptureShell` lives in `Tests/CaptureCoreTests/Support/`, not `BugeyeTestSupport`, because `CaptureShell` is a `CaptureCore` protocol and `BugeyeTestSupport` sees only `BugeyeCore` (K18). (cost if wrong: none.)
- Ruling: `CaptureController.waitUntil(_:)` and `settle()` are public, for tests and the debug channel; the selector tests had polled with `Task.yield()`, which starved the controller's own work under full-suite load (a run hung for 15 min). `FakeScreenSource` builds its frames row by row: `PixelBuffer(fill:)` took seconds for a 2880 × 1800 frame in a debug build. (cost if wrong: none.)
- Ruling: settings are snapshotted at the request (Capture §5.7 "read fresh at each request") and used by that capture's delivery; the save folder is read at delivery. (cost if wrong: none.)
- Ruling: an unreadable `com.apple.symbolichotkeys` counts as every screenshot entry missing (so on, with its default key), which is macOS's own state on a fresh account. (cost if wrong: low; at worst a false conflict notice.)
- Ruling: the Shortcuts model's launch notices come in the order macOS conflicts, then taken keys; a typed combo that registers but is taken stays stored with the taken message (§5.6: "A binding that fails to register stays stored"). (cost if wrong: none.)

Final review of PR #20 (slice 2, fresh reviewer): 0 Critical, 2 Important, 7 Minor. Fix pass:

- Ruling (review I1, Important): a freeze that finishes after its session ended (a selector cancelled mid-freeze) returns before storing frames, so no native frame outlives its session. Test failed first (`heldFrameSessions`). (cost if wrong: none.)
- Ruling (review I2, Important): `ShortcutsModel.registerAll` releases every row before registering any, so Restore Defaults can swap keys between rows; `FakeHotkeyRegistrar` now refuses a key another id holds, as Carbon does. Tests failed first. (cost if wrong: none.)
- Ruling (review M1): with the folder unusable and the temp write failing too, only `Capture failed` is posted and nothing logs `kept in temp`. Test failed first. (cost if wrong: none.)
- Ruling (review M2–M7): finished tasks leave `inFlight`; the frame crop runs off the main actor in `prepare`; a refused Esc logs `escape taken`; `HotkeyRegistrar` documents that callers record outcomes (C27); the area test asserts close before reactivate; `waitUntil` documents that it sees only the next entry into a phase. (cost if wrong: none.)

- Ruling (claude-review on PR #20, Minor): each queued event carries the settings read at its request, so a request made while effects run (queued) keeps its own snapshot instead of reloading at delivery. Test failed first. PR #20's linux and macos were green before this commit. (cost if wrong: none.)

- Ruling (claude-review on PR #20, Important): a window-capture result checks that its session is still live and finishing before storing the image, as the freeze does. The path is unreachable today (nothing ends `finishing` while a window capture is awaited), so no test can fail first; the tests now assert no window image or frame is held after a window capture succeeds or fails. (cost if wrong: none.)

Slice 3 (macOS adapters):

- Ruling: `displays()` reads `NSScreen` (number, Cocoa frame, backing scale); the flow still takes each frame's scale from its image. Window captures keep ScreenCaptureKit's default background and child-window settings; transparency and sheets are checked in the Mac batch (§9.4.2). (cost if wrong: low.)
- Ruling: hotkey letters register at their US (ANSI) key positions, as the first build did; the defaults are digits, which sit at the same positions on every layout. Backlog item below. (cost if wrong: low; a letter binding on AZERTY lands on another key.)

Final review of PR #21 (slice 3, fresh reviewer): 0 Critical, 1 Important, 8 Minor. Fix pass:

- Ruling (review I1, Important): a real `CarbonHotkeyRegistrar` test registers an unlikely combo, re-registers the same id (release first), checks another id can't take a key this process holds until it's released, and unregisters. (cost if wrong: none; if Carbon allows in-process duplicates the test says so and the fake changes with it.)
- Ruling (review M2): the Carbon callback holds a retained `Relay` that points back weakly, so a press after a registrar is released finds nil instead of a dangling pointer; `installStatus` records `InstallEventHandler`'s status. (cost if wrong: none; a few bytes per registrar.)
- Ruling (review M3, M7): `ScreenCaptureKitSource.targets` skips a display ScreenCaptureKit lists before `NSScreen` knows it (just plugged in) instead of failing the whole freeze; asked-for ids must exist. It and `pixelSize` are pure and tested. (cost if wrong: none.)
- Ruling (review M4, M6, M8, M9): `CFPreferencesAppSynchronize` before reading `com.apple.symbolichotkeys`; the live window-list test that couldn't fail is gone; `Unchecked` is private to the source file; downscale keeps alpha (tested). M5 (layouts) is the backlog item below. (cost if wrong: none.)

Slice 4 (app layer), final review of PR #27 (fresh reviewer): 1 Critical, 3 Important, 5 Minor. Fix pass:

- Ruling (review C1, Critical): the Shortcuts field takes the key from the key code (US positions, as the registrar uses), not `charactersIgnoringModifiers`, which keeps ⇧ (⇧⌘4 arrived as "$" and was refused as invalid, so no default could be typed back). The test now sends what AppKit sends ("#", "$"); it failed first. (cost if wrong: none.)
- Ruling (review I2, Important): while a row records, every global hotkey is released (Carbon takes a registered key before the field sees it); a combo, Esc, Delete, losing focus or closing the pane registers them again. Releasing isn't reported to `HotkeyStatus`. Tests failed first. (cost if wrong: low; the status menu keeps showing keys for the few seconds a row records.)
- Ruling (review I3, I4): crosshair and loupe show only on the overlay under the pointer and hide on `mouseExited`; the overlay view takes every click inside it (the crosshair lines and loupe never hit-test), so `acceptsFirstMouse` is the overlay's. Tests failed first. (cost if wrong: none.)
- Ruling (review M5–M9): a held Space or Return doesn't repeat and stray keys don't beep; recording ends when the field resigns or the pane disappears, and `performKeyEquivalent` takes a combo only while the field is first responder; `ShortcutsPaneModel` sets (not chains) a weak `onChange`; a view draws only for the live session, so a leftover's `mouseEntered` guard holds; the view removes only its own tracking area. (cost if wrong: none.)

- Ruling (claude-review on PR #27, Minor): only bare Esc and Delete cancel or clear while recording; with a modifier they're typed combos, which the model refuses as invalid. Carried in the next push, as the review rules ask. (cost if wrong: none.)

- Ruling (claude-review on PR #28, unverified concern): a field that resigns after another row started recording no longer stops the new recording; `stopRecording(id)` ends only that row's recording (nil, from the pane closing, ends any). Test failed first. (cost if wrong: none.)

## Waiting on user

## Backlog:

- Hotkey letters use US key positions (`kVK_ANSI_*`); resolve them through the current keyboard layout (`UCKeyTranslate`) so a letter binding works on AZERTY (slice 3 review M5).
