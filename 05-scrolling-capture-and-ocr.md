# 05 · Scrolling capture (M6 part 2) and Capture Text / OCR (M6 part 3)

This file covers two features that shipped together in M6:

- **Scrolling capture** (⇧⌘6): stitch a page taller than the screen into one PNG.
- **Capture Text / OCR** (⇧⌘7, plus Copy Text on existing captures): put the text you see on the clipboard.

It also covers the word-level OCR reader (`TextRecognizer.readMap`), added in M8, because every later text feature (find, sensitive-data sweep, search index, exact text, Copy for AI) is built on it.

The code is the source of truth. Where the shipped code differs from the M6 specs, this file describes the code and says so.

Primary sources:
- specs: `docs/superpowers/specs/2026-10-20-scrolling-capture-design.md` and `2026-10-21-ocr-design.md`
- plans: `docs/superpowers/plans/2026-10-20-m6b-scrolling-capture.md` and `2026-10-21-m6c-ocr.md`
- checklists: `docs/manual-checklist-m6-scrolling.md` and `docs/manual-checklist-m6-ocr.md`, every line ticked by the user

---

## Part A — Scrolling capture

### A1. What it does

**Starting it**
- Press ⇧⌘6, or choose the menu-bar item **Capture Scrolling Area** (shown with ⇧⌘6).
- The normal area-selection overlay opens (purpose `.scrolling`). Its hint reads exactly:
  `Drag the area to capture while scrolling · Space: pick a window · Esc to cancel`
- **Drag** to pick an area.
- **Space, then click a window** to use that window's frame. The frame is clipped to the display that holds the window's centre. If the centre is on no display, the click beeps and the overlay stays open.
- **Esc** cancels. Nothing appears.

**While it runs**
- The app that was in front before ⇧⌘6 is re-activated, so it keeps the keyboard. Space, PageDown and the arrow keys still scroll it.
- A dashed white border stays around the area. It is the same click-through, scroll-through window that recording uses (`AreaBorderWindow`).
- A "night" bar appears, centred horizontally, 24 pt above the bottom of the visible frame of the screen that holds the area. Left to right it holds:
  - a 22×32 pt thumbnail of the **latest rows**, at full width
  - the counter, e.g. `6,420 / 30,000 px`. The thousands separator is always a comma, whatever the locale.
  - the **Auto-scroll** toggle
  - **Cancel**
  - **Done ⏎** (the primary button)
- The first frame is captured straight away.

**Counter states** (`ScrollCaptureBarModel.counterText`)

| State | Text | Colour |
|---|---|---|
| Normal | `6,420 / 30,000 px` | secondary text |
| A frame had no overlap with the last kept frame | `Lost track: scroll back a little` | accent (yellow) |
| Cap reached | `Max length reached` | accent (yellow) |

**Scrolling by hand**
- Scroll at any speed.
- **Scrolling up** adds nothing. Capture resumes exactly where it stopped once the content comes back past the furthest point reached.
- **A jump of more than a screen** (no overlap) skips the frame and shows the lost-track text. The text clears as soon as a frame matches again.

**Auto-scroll**
- Needs Accessibility. Without it, clicking the toggle shows the macOS Accessibility prompt. The button's tooltip changes to: `Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again.` Manual scrolling keeps working.
- The normal tooltip is: `Bugeye scrolls for you. Scroll or move the mouse in the area to take over.`
- Button titles: `Auto-scroll` (off), `Auto-scrolling` (running, accent fill), `Resume` (paused).
- **It pauses** when the user scrolls, moves the mouse inside the area, or clicks the toggle.
- **It finishes by itself** after 1 s with no new rows (the end of the page), or at the cap. Finishing **ends the capture and delivers it**, with no Done click needed. This was a plan ruling: the spec said "hands-free".

**Finishing**
- **Return, keypad Enter or Done** composes the image and delivers it through the normal screenshot path:
  - a PNG named like any screenshot
  - the clipboard and save-folder settings apply
  - the "downscale to 1×" setting applies
  - it opens in Quick Access, and from there the editor
  - the source record (M7) is attached
- **Done after only the first frame** gives the same result as an area screenshot.
- **Done before the first frame arrives** (within about 200 ms of selecting) delivers nothing. It shows the notification `Nothing was captured` / `Done was pressed before the first frame arrived. Try again.`
- **Esc or Cancel** throws everything away. Esc works even while the browser is in front.
- **Quitting Bugeye** during a capture is the same as Cancel (`AppDelegate` calls `coordinator.cancelScrolling()`).

**The cap**
- Settings → section **Scrolling capture** → `Maximum height: 30,000 px`. It's a stepper from 10,000 to 60,000 in steps of 5,000. The default is 30,000.
- Stored as `AppSettings.scrollMaxHeight` under the UserDefaults key `scrollMaxHeight`. It is clamped on read.
- The **effective cap** is `min(setting, 150_000_000 / areaPixelWidth)`. 150 Mpx is the same pixel budget as GIF export. The counter shows the effective cap.
- At the cap the last slice is trimmed, so the image is **exactly** the cap tall. Later frames are ignored.

**Busy rules**
- While a session runs, ⇧⌘3/4/5/6/7 are ignored. This goes through `CaptureCoordinator.isCapturing` and `HotkeyRoute.of(..., scrolling:)`.
- A scrolling capture records provenance (M7), but **no Accessibility snapshot** (M9 skips scrolling captures).

**Errors**

| Situation | Behaviour |
|---|---|
| No Screen Recording permission | The usual permission prompt (`PermissionPrompt.showScreenRecordingMissing`) |
| Stream fails to start | Notification `Couldn't start scrolling capture`, with the mapped error. The session ends. |
| Stream stops mid-capture (display unplugged, permission revoked) | What was stitched is delivered, plus `Scrolling capture stopped early` / `<error> What was captured has been kept.` With nothing stitched: `Scrolling capture failed`. |
| The window under the area moves | The area is a fixed screen rectangle. Capture carries on with whatever is there. |

**Not supported (by design):** horizontal scrolling, stitching in both directions, scroll-event deltas as hints, content hidden behind other windows.

### A2. How it's built

#### Files

| Layer | File | Role |
|---|---|---|
| CSCore (pure) | `ScrollStitcher.swift` | `StitchResult`, `GrayFrame`, `ScrollStitcher`: matching, bands, slices, cap, compose |
| CSCore | `AutoScrollPolicy.swift` | state machine: idle / running / paused / finished |
| CSCore | `ScrollCap.swift` | range, step, default, pixel budget, `effective(...)` |
| CSCore | `ShortcutConflicts.swift` | `.touchBar = 181` (⇧⌘6 "Save picture of the Touch Bar as a file") |
| CSCapture | `ScrollFrameSource.swift` | `ScrollFrameSourcing` protocol + an `SCStream` of the area |
| App | `ScrollCapture/ScrollCaptureSession.swift` | `ScrollTarget`, `ScrollCaptureSession` (owns one capture, ends exactly once) |
| App | `ScrollCapture/StitchWorker.swift` | runs the stitcher on its own serial queue, drops frames under load |
| App | `ScrollCapture/AutoScroller.swift` | posts `CGEvent` scroll events and watches for the user taking over |
| App | `ScrollCapture/ScrollCaptureBar.swift` | `ScrollCaptureBarModel`, the SwiftUI bar, `ScrollCaptureBarPanel` |
| App | `CaptureCoordinator.captureScrolling()` / `scrollingSelected(...)` | selection → target → cap → session → `finish(image:scale:provenance:)` |
| App | `HotkeyManager` | `.scrolling` on ⇧⌘6 (`kVK_ANSI_6`, cmd+shift); session keys Esc / Return / keypad Enter |

#### Data flow

```
⇧⌘6 → CaptureCoordinator.captureScrolling()
  begin() (busy guard + Screen Recording check)
  select(purpose: .scrolling)  — freezes every screen, snapshots the window list
  → SelectionResult .area(displayID, rect, …) | .window(id, …)
  scrollingSelected: re-activate previous app; build ScrollTarget(displayID, area in display-local pts, screen)
                     start provenance collection (area ranked, or window share 1)
                     cap = ScrollCap.effective(maxHeight: settings, areaPixelWidth: area.width × backingScale)
  ScrollCaptureSession(target, maxHeight: cap, source: ScrollFrameSource(), autoScroller: AutoScroller(), hooks)
  session.start():
     AreaBorderWindow + ScrollCaptureBarPanel
     register global Esc/Return/Enter (Carbon hotkeys)
     source.onFrame → StitchWorker.consume → (stitch queue) ScrollStitcher.consume → main: apply(update)
     0.25 s Timer (common modes) → tick(): policy timers, auto-reverse
     Task { source.start(displayID, area, excludingPID: getpid()) }
  Done → worker.finish() → hooks.deliver(image, screen scale) → coordinator.finish(image:scale:provenance:)
```

#### `ScrollFrameSource` (CSCapture)

- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, then the display with the matching `displayID`.
- **The filter excludes Bugeye's whole application:** `SCContentFilter(display:excludingApplications: [app], exceptingWindows: [])`. Excluding the app, not a window list, also covers windows opened later (Quick Access, alerts). If the app can't be found, it falls back to excluding its current windows.
- **Configuration:**
  - `sourceRect = area`, in display-local points with a top-left origin
  - `width` / `height` = area × `filter.pointPixelScale`, so the frames are at native resolution
  - `minimumFrameInterval = 1/15 s`
  - `pixelFormat = kCVPixelFormatType_32BGRA`
  - `showsCursor = false`
  - `queueDepth = 4`
  - `colorSpaceName` is **left at its default** (the display's own space; see the bug list)
- **Frame filter:** only samples whose `SCStreamFrameInfo.status` is `.complete`. ScreenCaptureKit also sends idle frames with no pixels when nothing changed.
- **Each frame is deep-copied** out of the ScreenCaptureKit buffer pool. It goes through `VTCreateCGImageFromCVPixelBuffer`, then is drawn into a new `CGContext` (premultipliedLast) in the frame's own RGB colour space. Holding a pool buffer would starve the stream.
- `didStopWithError` is reported once (guarded by a lock), on the main queue, after `ScreenCapturer.map(error)`.

#### `ScrollStitcher` (CSCore): the algorithm

The stitcher is Bugeye's own row matching. It doesn't use Vision (`VNTranslationalImageRegistrationRequest`) or scroll-event deltas. The user chose this.

**API**
```swift
public enum StitchResult: Equatable, Sendable {
    case appended(rows: Int), noMovement, behind(rows: Int), lostTrack, capReached
}
public final class ScrollStitcher {
    public init(maxHeight: Int)
    public private(set) var height: Int
    public private(set) var isCapped: Bool
    public func consume(_ frame: CGImage) -> StitchResult
    public func finish() -> CGImage?
    public func latestRows(width: Int, height: Int) -> CGImage?   // bar thumbnail
    public static func colorSpace(of: CGImage) -> CGColorSpace
}
```
`behind(rows:)` is not in the spec. The final review added it (see the bug list).

**Constants (as shipped)**

| Constant | Value | Meaning |
|---|---|---|
| `GrayFrame.maxColumns` | 512 | Frames are reduced to grey, full height, at most 512 columns wide, for matching only |
| `GrayFrame.flatRange` | 6 | A row whose darkest and lightest sampled pixels are within 6 levels is "flat" (blank) |
| `rowTolerance` | 2.0 | Two rows "line up" when their mean absolute difference is ≤ 2 grey levels |
| `acceptShare` | 0.75 | A shift is accepted when ≥ 75 % of the compared non-flat rows line up |
| `ambiguityShare` | 0.02 | A rival shift more than 2 rows away scoring within 0.02 of the best makes it ambiguous |
| `minComparedRows` | 8 | Fewer compared rows means the shift isn't scored |
| `minMovingColumns` | 16 | Fewer moving columns means matching uses every column |
| `maxBandShare` | 0.4 | Sticky header + footer together may cover at most 40 % of the frame |
| "no movement" | mean diff ≤ 0.5 | A whole frame this close to the reference is `noMovement` |
| moving-column noise | > 4 | A column "moves" if any pixel differs by more than 4 (±2 noise on two frames stays ≤ 4) |

**`consume(frame)` step by step**
1. If capped, return `.capReached`.
2. Make a `GrayFrame` and a deep copy of the frame. If either fails, return `.lostTrack`.
3. **First frame:** keep it as `first` and as the reference. Height = the frame's height. If that alone is at or above `maxHeight`, the stitcher is capped. Return `.appended(rows: h)`.
4. **Size changed** since the reference: `.lostTrack`.
5. **Mean difference ≤ 0.5** against the reference: `.noMovement`.
6. **Moving columns:** columns where some pixel changed by more than 4 between the frames. A static sidebar (Slack's) is left out. With fewer than 16 moving columns, all columns are used.
7. **Sticky bands** (`bands`): count the leading rows that are identical at the same position in both frames, then the trailing rows, over the moving columns. If they add up to more than 40 % of the height, there are no bands for this pair.
   - **Bands only ever grow.** The stitcher tries two options in order: (a) this pair's bands combined with the known ones (`max(header, new)` / `max(footer, new)`), then (b) the known bands alone.
8. **`bestShift`** over the rows between the bands (`top..<bottom`):
   - `region = bottom − top`; `maxShift = region − max(8, region/5)`. So at least 20 % of the region (or 8 rows) must overlap.
   - **Cheap pass:** for every `d` in `−maxShift...maxShift`, compare per-row **sums** over the chosen columns, skipping pairs where both rows are flat. Score = the share of rows whose sums agree within `rowTolerance × columns`.
   - Take the **top 6** shifts by score, plus the previous shift (`hint`) if it was scored.
   - **Verify** each candidate pixel by pixel (`matchShare`): the share of non-flat rows whose mean absolute difference is ≤ 2.
   - **Accept** the best if its share is ≥ 0.75.
   - **Ambiguity:** if another verified shift more than 2 rows away scores within 0.02 of the best (repeated content), prefer whichever is within 2 rows of `hint`. Otherwise the result is nil, which means lost track.
9. Interpret the shift:
   - `0` → `.noMovement`
   - `< 0` → `.behind(rows: −shift)`. The user scrolled up past the last kept frame.
   - `> 0` → append (next step)
   - nil in every option → `.lostTrack`
10. **Append:**
    - Store the bands.
    - On the first match, `headRows = bottom`: the first frame down to its footer becomes the top of the image.
    - **A footer that grew** since the last match means the rows it now covers were the bar, not content, so trim them off the body (`trimBody`).
    - `rows = shift`. If `head + slices + rows + footer ≥ maxHeight`, set `rows = maxHeight − body`, mark capped, and set `dropFooter`, because the footer would no longer join the trimmed content.
    - Deep-copy rows `bottom − shift ..< bottom` of the new frame as a slice.
    - The new frame becomes the reference (`lastShift`, `lastBottom`).
    - `height = headRows + slicedRows + (dropFooter ? 0 : footerRows)`.

**Why "match against the last kept frame":** the reference only moves when rows are appended. So scrolling up gives `behind` or `noMovement`, and scrolling back down resumes with no duplicated rows.

**`finish()` / `compose(scale:)`**
- Pieces from top to bottom:
  - the first frame's top `headRows`
  - every slice
  - the footer from the **latest** reference frame (rows `lastBottom..<h`), unless `dropFooter`
- They're drawn into one `CGContext`:
  - RGBA premultipliedLast
  - in the first frame's colour space
  - interpolation `.none` at scale 1
- A single frame returns that frame unchanged.
- `latestRows(width:height:)` composes at `scale = min(1, width / frameWidth)` with `.medium` interpolation, then crops the bottom `height` rows. The bar shows this.

**Memory:** every kept slice is a deep copy (`copyRows` draws a crop into a new context). A `CGImage.cropping` result shares the parent's buffer and would keep every whole frame alive. A test (`stitcherKeepsCopiesNotViews`) overwrites the source buffer and checks the result.

#### `StitchWorker` (app)

- One serial queue (`dev.msenechal.cleanshotcopy.stitch`, `.userInitiated`).
- **At most 2 frames wait.** Extra frames are dropped; the next frame shows the same content further along.
- **The bar preview** is computed at most every 0.25 s, at 44×64 px (22×32 pt at 2×), and only when the result is not `noMovement` or `lostTrack`.
- Updates (`StitchUpdate(result, height, preview)`) go to the main queue.
- `close()` sets `closed` with `queue.sync`. Later and already-queued frames are then ignored. `finish()` is `queue.sync`.

#### `AutoScrollPolicy` (CSCore)

- `State`: `idle`, `running`, `paused`, `finished`. `stillTimeout = 1.0 s`.
- `toggle(at:)`: idle or paused → running (resets the still timer); running → paused; finished → no change.
- `userInput()`: running → paused.
- `observe(result, at:)`: `.appended` resets the still timer; `.capReached` while running → finished. Nothing else changes the state.
- `tick(at:)`: running and no progress for ≥ 1 s → finished.
- `restartStillTimer(at:)`: the session calls it when the content is coming back down (`behind` shrinking) and after a reversal.

#### `ScrollCaptureSession` (app)

- `Hooks` are injected for tests: `deliver`, `onEnd`, `notify`, `permissionMissing`, `now`, `isAccessibilityTrusted`, `promptAccessibility`, `registerKeys`, `unregisterKeys`.
- **It ends exactly once on every path:** Done, Cancel, auto finish, start failure, stream failure. `end()`:
  - invalidates the ticker
  - stops the auto-scroller
  - unregisters the keys
  - closes the worker
  - stops the stream (async)
  - **closes** (not just hides) the border and the bar

  Then `onEnd` clears `scrollSession` and the busy flag. A session that never ended would leave the coordinator "busy" until relaunch.
- **A start that finishes after Cancel:** `source.start` awaits ScreenCaptureKit. If `ended` is already true when it returns, the session calls `source.stop()` straight away.
- **`apply(update)`:**
  - updates the height and preview
  - `lostTrack` sets the lost-track text
  - `appended` clears it and marks auto progress
  - `behind(rows)` that shrinks while auto-scrolling counts as progress and restarts the still timer
  - `capReached` sets the cap state
- **`sync()`** brings the auto-scroller and the model in line with the policy. `finished` → stop, then `done()`.
- **Auto-reverse:** `autoReverseAfter = 0.5 s`. If auto-scroll has run 0.5 s since its **latest** start or resume with no progress, it reverses direction once (`autoScroller.reverse()`). This guards against macOS applying "natural scrolling" to posted events, which the plan couldn't verify.

#### `AutoScroller` (app)

- Posts `CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: direction × 12, ...)` every 0.03 s, to `.cghidEventTap`. The direction starts at −1: a negative wheel delta moves the content up, which scrolls down.
- **Own-event marker:** each event's `.eventSourceUserData` is set to `0x42554745` ("BUGE"). The global monitor ignores events that carry it. Without this, auto-scroll would pause itself at once.
- **User takeover:** `NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .mouseMoved])`:
  - any scroll that isn't Bugeye's → `onUserInput`
  - a mouse move inside the area → `onUserInput`
- **Pointer placement:** scroll events go to the window under the pointer. If the pointer isn't inside the area, or is on the bar, it is warped with `CGWarpMouseCursorPosition` (Quartz coordinates: `y = primaryHeight − cocoaY`):
  - to the area's centre
  - or, when the bar covers the centre, to the middle of the larger strip of the area above or below the bar

  This is `AutoScroller.pointerTarget(area:avoiding:mouse:)`.
- Needs Accessibility (`AXIsProcessTrusted`) to post events.

#### The bar panel

- `ScrollCaptureBarPanel: NSPanel` with `[.nonactivatingPanel, .borderless]`, `level = .statusBar`, `hidesOnDeactivate = false`, and collection behaviour `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`.
- **`canBecomeKey` returns false.** The bar never takes the keyboard from the app being scrolled.
- SwiftUI content uses `NightButtonStyle` / `NightToggleStyle` / `.nightPanel(cornerRadius: 12)`.
- The model is an `ObservableObject` with `@Published`. SwiftUI's `@State` macros don't compile with the Command Line Tools only.

#### Global Esc / Return during a session (`HotkeyManager`)

- While a session runs, Esc (`kVK_Escape`), Return and keypad Enter are registered as **Carbon global hotkeys** (`RegisterEventHotKey`). They work while the browser is in front, which the bar can't do, because it never becomes key.
- **They step aside** whenever a Bugeye window is key while Bugeye is active, or a modal is up (`sessionKeysAllowed(keyWindow:modalWindow:)` requires both to be nil). The rule is re-evaluated on every key/active notification, one runloop turn later, because the key window only settles after the notification.
- Side effect: while registered, those keys are swallowed system-wide. Return doesn't reach the browser during a session.

#### Shortcut conflict

- `SystemScreenshotShortcut.touchBar = 181` is ⇧⌘6, "Save picture of the Touch Bar as a file".
- A Mac's `com.apple.symbolichotkeys` has **no entry 181** until the user changes it. A missing entry counts as "on" only on a Touch Bar Mac. `ShortcutConflicts.touchBarModels` lists the MacBook Pro models with a Touch Bar (2016–2022), checked against `hw.model`.

### A3. Gotchas and bugs we hit

| Symptom | Root cause | Fix | Commit |
|---|---|---|---|
| A page whose sticky bar appears part-way through (GitHub's header after the first scroll) lost track or stitched badly | Bands were found once, from the first differing pair; matching used the mean difference, so a few unmatched rows (the bar) spoiled a good shift | Bands are re-detected every frame and only grow; shifts are accepted by the **share** of rows that match (≥ 75 %), not the mean; the body is trimmed when a footer appears | `4eaa071` (review C1) |
| Slack in window mode (with a static sidebar) didn't match | The static sidebar columns dominated the row signatures | Columns that never change are left out of matching (`movingColumns`) | `4eaa071` (I4) |
| Auto-scroll with an area reaching the screen bottom scrolled the bar, not the page | The pointer sat over Bugeye's bar, so posted wheel events went to the bar | Warp the pointer into the area, off the bar (`pointerTarget`) | `4eaa071` (C2) |
| After scrolling up and then pressing Auto-scroll, it reversed direction or stopped early | Coming back down produced `noMovement`, which counted as "stuck" | The stitcher reports `.behind(rows:)`; shrinking `behind` counts as progress and restarts the still timer | `4eaa071` (I1) |
| Cancel during stream start left a stream running | `startCapture` completed after the session had ended | After `start` returns, stop if `ended` | `4eaa071` (I3) |
| The hint "Scroll slower" was misleading | The real fix is to scroll back | The text became `Lost track: scroll back a little` | `4eaa071` (I2) |
| Session windows hung around after the end | They were ordered out, not closed | `end()` closes the border and the bar | `4eaa071` |
| Pausing before any progress and resuming later could reverse a correct direction | The reverse timer counted from the first start | It counts from the latest start or resume (`autoStartedAt`) | `202c187` |
| Done within about 200 ms of selecting gave nothing, silently | No frame had arrived yet | `Nothing was captured` notification | `202c187` |
| Clicking the bar took Space / PageDown / the arrows from the scrolled app | The panel could become key | `canBecomeKey = false`; Esc/Return go through global session keys | `7fd2f40` |
| The bar thumbnail was a sliver for tall captures | The whole capture was shrunk into 22×32 pt | Show the latest rows at full width (`latestRows`) | `7fd2f40` |
| Colours differed slightly from an area screenshot on P3 displays | Frames were captured and composed in sRGB | Leave `colorSpaceName` at its default (the display's space); copies and composition use the frame's own RGB space (`colorSpace(of:)`) | `c9bdcea` |
| Touch Bar Macs never warned about ⇧⌘6 | No entry 181 exists until changed, and missing was treated as off | Missing counts as on only for Touch Bar models | `23dce4c` |
| Return answered Bugeye's own alert (e.g. the unsaved-editor prompt on quit) by ending the session, or the reverse | Global Return/Esc caught every keypress | Session keys unregister while a Bugeye window is key or a modal is up | `4546416` |
| Posted scroll direction and marker had no test | — | A unit test checks the event's delta sign and the marker | `91def95` |
| Stitch-worker tests timed out in the full suite | The parallel suite saturates the main queue | Tests wait up to 10 s for main-queue delivery | `aa53e85` |

**Design pitfalls the plan flagged (and the code guards):**
- **Holding ScreenCaptureKit buffers or crops by reference** starves the stream or keeps gigabytes alive. Deep-copy everything you keep.
- **Your own posted events reach your own global monitor.** Mark them (`eventSourceUserData`) and filter them out.
- **Natural scrolling and posted events:** the direction is unverified, so auto-reverse once after 0.5 s with no progress.
- **The session must end exactly once on every path,** or the busy flag sticks until relaunch.
- **Content under a banner that appears mid-capture is lost** (a cookie notice, a bottom bar) while the banner covers it. The README documents this: close the banner before starting.

### A4. Known open issues

From `docs/backlog.md` and memory:
- A scrolling capture started while a Bugeye window (an editor) is key never registers the global Esc/Return. The session keys step aside for any Bugeye key window.
- The `make smoke` test `scrollingAWindowStitchesTheWholeDocument` depends on what's on screen and can come out short. It's a known flake, not a regression.
- The stitch-worker tests wait on the main queue. The backlog suggests injecting the worker's delivery queue.
- `doneDeliversTheStitchedImageAtScreenScaleAndEndsOnce` can fail on a Mac with a 2× and a 1× display. It reads `NSScreen.main`, which follows the key window. Compare against the session's scale instead.
- **Find and sweep (M8) on tall captures:** a ~16-strip OCR on a very tall scrolling capture rarely finishes before the 5 s thumbnail timeout, and the scan keeps running after the thumbnail goes. Each settled edit renders the full image twice on the main thread (about 0.35 s and 1.4 GB transient at 60,000 px).

### A5. Do it better next time

- **Write the algorithm spec from the shipped code.** The spec's "mean ≤ 2 and beats the second best" rule failed on real pages. Share-of-rows (≥ 75 %), growing bands, moving columns and `behind` are what work.
- **Build a frame-replay harness early.** Record real frame sequences (GitHub PR, Slack with sidebar, terminal, a page with a late sticky header and a cookie banner) to disk. Replay them through `ScrollStitcher` in unit tests. Most stitching bugs were found by hand on real pages.
- **Make the stitch worker's delivery queue injectable** from the start. Main-queue waits made the tests flaky.
- **Handle banners that appear mid-capture:** detect a footer band that appears and keep the rows it newly covers from the previous frame, instead of losing them.
- **Show a "stitch seam" debug overlay** (a hidden setting) that draws the slice boundaries. It makes doubled or missing rows obvious.
- **Session keys:** instead of global Carbon hotkeys that swallow Return everywhere, consider a `CGEventTap` limited to the session that passes everything else through. Or keep the hotkeys but also handle the "editor already key" case.
- **Compute the effective cap from the display scale at the frame's actual size,** not from `NSScreen.backingScaleFactor`, and pass the session's scale to tests.
- **Prefer `SCScreenshotManager` / `SCStream` `.complete` frames, as done.** Keep the copy-out-of-pool step.
- **Auto-scroll direction:** read `com.apple.swipescrolldirection` to choose the initial direction, and keep the reverse-once fallback.

**Portable core vs macOS shell** (see `13-rebuild-strategy-agentic-ci-and-claude.md`):

| Portable core (Linux-testable) | macOS shell |
|---|---|
| `ScrollStitcher` on `PixelBuffer` (grey frames, moving columns, bands, `bestShift`, slices as copied buffers, compose into one `PixelBuffer`). It only needs a byte buffer; drop `CGContext` from it. | `ScrollFrameSource` (`SCStream`, `.complete` frames, copy out of the pool into a `PixelBuffer`), behind the `ScreenSource` port |
| `AutoScrollPolicy`, `ScrollCap`, the session state machine (ends exactly once, start-after-cancel, auto-reverse timer, `behind` progress), the bar model's texts (`counterText`, `grouped`, `autoTitle`) | `AutoScroller` (`CGEvent` posting, the marker, global monitors, pointer warp) behind a `ScrollPoster` port with a fake |
| The pointer-target maths (`pointerTarget`), the stitch worker's drop-when-2-waiting rule with an injected queue | The border window, `ScrollCaptureBarPanel`, session hotkeys |
| Frame-replay tests: recorded real sequences stored as PNG fixtures, decoded once into `PixelBuffer`s | `make smoke`-style tests that scroll a real window, on the macOS CI tier only |

Keep the colour space as metadata on the `PixelBuffer`, so the shell can tag the PNG with the display's space (the P3 bug).

---

## Part B — Capture Text / OCR

### B1. What it does

**Capture Text (⇧⌘7, or the menu-bar item "Capture Text", shown with ⇧⌘7)**
1. The selection overlay opens with purpose `.text`. Its hint reads exactly: `Drag over the text to copy · Space: pick a window · Esc to cancel`
   - Drag for an area. The image is the one the overlay froze, so nothing new is captured.
   - Space, then click, for a window (`ScreenCapturer.captureWindow`).
   - Esc cancels. The clipboard is unchanged and no notification appears.
2. **Nothing is saved, and Quick Access doesn't open.** No provenance is recorded.
3. **The busy flag is released** as soon as the pixels are in hand, so ⇧⌘4 during the reading works (`5655aba`).
4. Recognition usually takes under a second.
5. **Text found:** it goes to the clipboard as plain text. Notification title `Text copied`. The body is the summary, e.g. `error: cannot find 'foo' in scope (12 lines)`.
   - From M9 on, the summary may end with ` · exact text from Terminal` (or "A and B", or "A and others").
6. **No text:** notification title `No text found in the selection`, body `The clipboard wasn't changed.` The clipboard is untouched.
7. **Recognition throws:** `Couldn't read text`, with the error's description. The clipboard is untouched.
8. Ignored while another capture, a scrolling capture, a recording or the ⇧⌘5 set-up is running (`ecf91b9`).
9. Needs Screen Recording, through the usual prompt.

**Copy Text on an existing screenshot**
- **Quick Access:** ⋯ → `Copy Text`. It's offered only for `.screenshot` items (scrolling captures are screenshots too), never for recordings or GIFs. It reads the item's file off the main thread. A missing or unreadable file gives `Couldn't read text` / `<name> is missing or unreadable.`
- **Editor:** a `Copy Text` toolbar button (tooltip `Copy Text (⇧⌘C)`) and Edit → Copy Text, ⇧⌘C. It reads the **flattened render**: crop, annotations, blur and pixelate. A blurred secret therefore stays hidden.
- Outside ⇧⌘7, the no-text title is `No text found in the image` (`4afff01`).

**Line layout (what lands on the clipboard)**
- One line per screen line. Paragraphs are not joined, so code and logs keep their shape.
- Fragments on the same line are joined with one space, left to right.
- **Indentation is rebuilt** from each line's left edge (`9d6a5b7`). Python tracebacks and nested code keep their indent.
- **Code characters are exact:** `foo(bar)` stays `foo(bar)`. Accents (French) are read correctly.
- Recognition is on the device. No network, and no language setting: Vision detects the language.

### B2. How it's built

#### Files

| Layer | File | Role |
|---|---|---|
| CSCore | `TextLayout.swift` | `TextFragment`; `TextLayout.lines`, `sameLine`, `indentation`, `summary` |
| CSCore | `TextMap.swift` | `TextWord`, `TextLine`, `TextMap`; strips (4,000 px, 200 px overlap), `mapped`, `merged` (M8) |
| CSCapture | `TextRecognizer.swift` | `TextRecognizing` protocol; Vision `RecognizeTextRequest`; `recognize` (fragments) and `readMap` (word boxes) |
| App | `TextCapture/TextCopier.swift` | recognise → lay out → clipboard → notification, shared by ⇧⌘7, Quick Access and the editor; also Copy for AI |
| App | `CaptureCoordinator.captureText()` / `textSelected(...)` | selection → image → `TextCopier.copyText(...)` |
| App | `Editor/EditorWindowController.copyTextRendered()` | renders the edit, then `EditorTextReader.readText` → `ExactText.merge` → clipboard |
| App | `QuickAccessController.perform(.copyText, ...)` → `onCopyText` → `TextCopier.copyText(fromFile:)` | |
| CSCore | `OutputRouter.swift` `ClipboardWriting.writeText(_:)` | `PasteboardClipboard.writeText` clears the pasteboard and sets `.string` |

#### Vision request (`TextRecognizer`)

```swift
var request = RecognizeTextRequest()          // the macOS 15+ Swift Vision API, not VNRecognizeTextRequest
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.automaticallyDetectsLanguage = true
let observations = try await request.perform(on: cgImage)
// each observation: topCandidates(1).first?.string, boundingBox (normalised, origin bottom-left)
```
- **Why language correction is off:** a probe during planning showed it turning `foo(bar)` into `foo (bar)`. With it off, code comes out exactly and French accents are still read correctly.
- **Why not VisionKit `ImageAnalyzer`:** Bugeye lays the lines out itself, and Vision returns boxes it can use for find, redaction and exact-text merging. (VisionKit's `ImageAnalysisOverlayView` is used separately, for Live Text selection in the editor.)
- **Coordinate conversion:** `pixelRect(r, in: size) = (r.minX·W, (1 − r.maxY)·H, r.width·W, r.height·H)`. That is top-left origin, in the image's pixels. Every box in Bugeye is in image pixels with the origin at the top left.

#### `TextLayout.lines(_ fragments) -> String?`

1. Trim each fragment and drop empty ones.
2. Sort by `(minY, minX)`.
3. **Group into lines.** A fragment joins the current line when its vertical overlap with that line's **first** fragment is ≥ 50 % of the smaller height (`sameLine`).
   - The spec said "the line's span (the union)". That merged a big number beside a two-line caption into one line, so the code compares with the first fragment instead (`9d6a5b7`).
4. Sort each line by `minX`, and join with one space.
5. **Indent** (`indentation`): the character width is the **narrowest** line's average (sum of box widths ÷ character count). Each line gets `round((left − leftmost) / charWidth)` leading spaces.
6. Join with `\n`. If nothing is left, return nil.

#### `TextLayout.summary(_ text)`
- The first line, trimmed of spaces, cut at 60 characters plus `…`.
- With more than one line, ` (N lines)` is added.
- `ExactText.summary(text, exactApps:)` (M9) wraps it and appends the exact-text sources.

#### 1× screens: enlarge 2×
- Small text on a non-Retina display is unreliable. When `pixelsPerPoint < 2`, the image is enlarged 2× before recognition (`TextCopier.forRecognition`, `ImageCodec.downscaled(image, by: 2)`; a factor of 2 enlarges).
- The resulting boxes are scaled back into the original image's pixels before they meet anything else (snapshot, layout).
- **Every entry point passes the capture's real scale:** ⇧⌘7 passes the selection's scale; Quick Access passes `item.pixelsPerPoint`; the editor passes `document.pixelsPerPoint` (`c597d68` fixed the editor, which used to assume 2).

#### Word-level reading: `readMap` (added in M8, used by M8–M11)

```swift
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> [TextFragment]
    func readMap(_ image: CGImage, pixelsPerPoint: CGFloat) async throws -> TextMap
}
```
- A default `readMap` builds one word per fragment, so fakes that only implement `recognize` keep working. **Tests never run Vision.** They use `FakeTextReader` and similar fakes; real Vision runs only in `CSC_INTEGRATION=1` smoke tests.
- **Scale:** `scale(forPixelsPerPoint:)` returns 2 below 2 px/pt, else 1.
- **Strips:** `TextMap.strips(height:)` returns one strip up to 4,000 px. Above that, 4,000 px strips that overlap by 200 px. This stops Vision from internally shrinking a tall scrolling capture and losing small text.
- **Each strip:**
  - is cropped
  - is enlarged if needed
  - is read with `RecognizeTextRequest`
  - gets per-word boxes from `candidate.boundingBox(for: wordRange)`, with words split on whitespace (`TextLine.wordRanges`)
  - has its boxes mapped back (`mapped(scale:offsetY:)`)
- **Merging** (`TextMap.merged`):
  - a line entirely inside an overlap is kept only from the strip above
  - a line that the strip above cut at its bottom edge gives way to the whole line from the strip below
  - the integration test `aTallImageReadsEachOverlapLineOnce` checks an 8,200 px image
- `Task.checkCancellation()` runs between strips.

#### How Capture Text uses it (after M9)
- `TextCopier.copyText(from:pixelsPerPoint:waitingFor:)` starts OCR (`readMap`) and, in parallel, waits **at most 1 s** for the Accessibility snapshot (`ProvenanceCollector.within`). It then calls `ExactText.merge(snapshot, map:)`. Exact text is covered in the M9 findings file.
- With no snapshot, the result is the same as `TextLayout.lines` over the OCR lines.
- Two readings can overlap (⇧⌘7 twice). Each writes the clipboard, and the last to finish wins.

### B3. Gotchas and bugs we hit

| Symptom | Root cause | Fix | Commit |
|---|---|---|---|
| `foo(bar)` came out as `foo (bar)` | Vision's language correction | `usesLanguageCorrection = false` (decided at planning, pinned by an integration test with code and French) | plan `24e8d61`, `aced7e7` |
| A big number beside a two-line caption became one line | Line span grew with each fragment (union) | Compare each fragment with the line's **first** fragment | `9d6a5b7` |
| Python tracebacks and nested code came out flush left | No indentation rebuilt | Leading spaces from left edges in units of the narrowest line's character width | `9d6a5b7` |
| "No text found in the selection" appeared from Quick Access and the editor, where nothing was selected | One message for every origin | `Origin.selection` vs `.image`: "…in the image" outside ⇧⌘7 | `4afff01` |
| Quick Access Copy Text hitched on large captures | PNG read and decoded on the main thread | Read and decode in `Task.detached` | `4afff01` |
| Small text on 1× screens was misread | No upscaling before recognition | Enlarge 2× below 2 px/pt | `4afff01`; editor in `c597d68` |
| ⇧⌘4 pressed while Vision was still reading a ⇧⌘7 capture was dropped | The busy flag was held during recognition | Release it once the pixels are in hand | `5655aba` |
| ⇧⌘7 opened a selection during an active recording | Not routed through the recording-phase check | `HotkeyRoute` ignores it while recording; ⇧⌘7 is listed in the "shortcuts still on" notice | `ecf91b9` |
| Tall scrolling captures lost small text in OCR | Vision downsamples very large inputs | 4,000 px strips with a 200 px overlap and merge rules | `5341dd4`, `987200c` |

### B4. Known open issues

- **Indentation uses the narrowest line's character width.** A line of narrow glyphs (`|`, `l`, `...`) inflates every other line's indent. A median would be steadier.
- **`readMap` cuts strips before the 2× enlargement**, so a 1× strip reaches Vision at 8,000 px. It should cut at `4000 / scale` rows. `TextCopier` avoids this by enlarging first and passing `pixelsPerPoint: 2`, but the editor and sweep paths call `readMap` with the real scale.
- **Every editor save re-reads the image** (one extra OCR per save), even with no changes. If the editor's render fails, find stays on "Reading…" (M8).
- **Columns and tables** are not preserved beyond single spaces. This is by design (out of scope).

### B5. Do it better next time

- **One text pipeline from day one.** Build `readMap` (lines + word boxes + strips + 2× for 1×) first, and derive Capture Text from it. M6's fragment-only `recognize` was superseded by M8's word map and M9's exact text, which left two code paths.
- **Do the 2× enlargement in exactly one place** (inside the recogniser, strip-aware). Callers then always pass the capture's real `pixelsPerPoint`.
- **Use a robust character width** (the median of per-line averages, or the monospaced width when Vision reports one) for indentation.
- **Keep the probe tests:** a CoreText-drawn image with `let x = foo(bar)` and an accented French sentence, plus an 8,200 px strip test. They caught the real Vision behaviours.
- **Cache the OCR result per file** (keyed by the capture ID and modification date). Quick Access Copy Text, Copy for AI, the sweep and the indexer then read each image once.
- **Consider returning an `ExactTextResult`-shaped value from one service** used by ⇧⌘7, Copy Text, Copy for AI and the editor, so the four entry points can't drift (they drifted on 1× handling and the no-text wording).
- **OCR stays local** (Vision on the device), even when AI features are added. Never send the image to the Claude API just to read text.

**Portable core vs macOS shell:**

| Portable core (Linux-testable) | macOS shell |
|---|---|
| `TextFragment`, `TextWord`, `TextLine`, `TextMap` (with plain `Rect` structs instead of `CGRect`), `TextLayout.lines` / `indentation` / `summary`, strip planning (`strips`), `mapped`, `merged`, the 2× decision (`scale(forPixelsPerPoint:)`) | The Vision adapter behind the `TextReader` port: `RecognizeTextRequest` with the three settings, per-word boxes, the bottom-left → top-left conversion, the strip crop and the 2× enlargement |
| The copier's logic as a use case: read → merge → write text or not → notification title and body (`Text copied`, `No text found in the selection` / `…in the image`, `Couldn't read text`) against `ClipboardWriter` and notifier fakes | `NSPasteboard`, notifications, the selection overlay, window capture |
| Fixtures: a stored `TextMap` per recorded image, so layout and merge tests run on Linux without Vision | The integration tests that draw text with CoreText and run real Vision (`CSC_INTEGRATION=1`), macOS tier only |
