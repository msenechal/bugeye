# 02 · Capture (M1) and Quick Access

Scope: full-screen, all-displays, area and window capture; recapture of the last area; the selection overlay; multi-display and scale handling; window captures with their shadow; output routing (clipboard, save folder, downscale, naming, temp folder); the Quick Access thumbnail stack (including M11's ⇧-click selection and Combine); `CaptureCoordinator`; and the stuck-overlay saga.

The selection overlay is shared by recording (⇧⌘5), scrolling capture (⇧⌘6) and Capture Text (⇧⌘7); their own flows are in files 04 and 05. Provenance chips, the sweep badge, Copy for AI and Find Similar appear on the thumbnail but are specified in files 06, 07 and 09.

Checked against the code on `feat/m11-collections` (771bcd1).

---

## 1. What it does (user-visible)

### 1.1 Capture modes

| Trigger | Result |
|---|---|
| ⇧⌘3, menu **Capture Fullscreen** | One PNG of the display under the mouse pointer |
| ⌥⇧⌘3 | One PNG per display, captured one after the other (each file named by its own capture time; same-second names get ` (2)`) |
| ⇧⌘4, menu **Capture Area** | Area selection overlay on every display |
| Menu **Capture Window** | The same overlay, already in window mode |
| ⇧⌘4, then Space | Window mode: hover highlights a window; click captures it with its shadow on a transparent background |
| ⇧⌘4, then Return (or keypad Enter) | Recaptures the last area (same display, same rect) from the new frozen frame. Beeps if there's no last area or its display is gone |

Bugeye's own windows (Quick Access thumbnails, panels) never appear in full-screen or area captures: they're excluded by process ID.

If Screen Recording isn't granted, any capture shows the "Screen Recording permission needed" alert (file 01 §2.8) instead of failing silently.

### 1.2 The selection overlay

- **Freeze.** All displays are captured first; each display then shows its own frozen image, so menus, tooltips and video stop moving while you select. The capture is cropped from this frozen frame: what you see is what you get.
- **Dim.** Black at 40 % over everything outside the selection.
- **Crosshair.** Two white lines at 60 % opacity, 1 pt wide, across the whole display.
- **Loupe.** A 120 pt circle magnifying a 15 × 15-pixel square of the frozen image without smoothing, with a white 2 pt ring and a red square on the pixel under the pointer. It sits 20 pt below-right of the pointer and flips to the other side near the right and bottom edges, always fully on screen.
- **Size readout.** `W × H` in points (rounded), monospaced 12 pt medium white, on a black 75 % rounded box, 8 pt right of and 24 pt below the selection's corner, kept on screen.
- **⇧ (Shift)** locks one axis: pressed mid-drag, it locks the axis that moved less since the press (`axisToLock`). The lock starts once the selection has a size and the pointer has moved more than 2 pt after the press.
- **⌥ (Option)** resizes from the centre (the anchor becomes the centre).
- **Space** toggles window mode (and back). The current drag is reset.
- **Esc** cancels. **Right-click** cancels (safety net). Esc is also a temporary global hotkey while the overlay is up (safety net).
- **Return / keypad Enter** recaptures the last area.
- A click without a drag, or a selection under 4 × 4 pt, does nothing for screenshots (the overlay stays). For recording, it records that whole display.
- A selection is limited to one display (each display has its own overlay window; a drag stays in the view where it started and is clipped to its bounds).
- The cursor is the crosshair cursor; crosshair and loupe show immediately at the pointer when the overlay opens, without waiting for a mouse move.
- **Hints** at the top of each display (none for screenshots):
  - recording: `Drag an area · Click to record this display · Space: pick a window · Esc to cancel`
  - scrolling: `Drag the area to capture while scrolling · Space: pick a window · Esc to cancel`
  - text: `Drag over the text to copy · Space: pick a window · Esc to cancel`

**Window mode:**
- The whole display is dimmed; the hovered window is redrawn undimmed from the frozen image, with a blue 20 % fill and a 3 pt `systemBlue` border.
- No crosshair or loupe.
- Hover picks the frontmost **normal** window (layer 0, alpha > 0, not Bugeye's) under the pointer, from the window list read when the hotkey was pressed.
- Click on nothing → beep, overlay stays.
- For recording and scrolling, clicking a window whose centre is off every display beeps and stays open (820d452).

### 1.3 Output

After each still capture, in this order (each step a setting):

1. **Save** to the save folder (default `~/Pictures/Bugeye/`, setting on by default). If the folder is unusable (deleted, unwritable, unplugged), the file goes to the temp folder and a notification says:
   - `Couldn't save to folder` / `<path> is unavailable. The capture is kept temporarily; use Save in Quick Access.`
2. **Copy** to the clipboard (on by default): PNG, the file URL, lazy TIFF and lazy HTML (file 01 §2.18). If even the temp write fails, the image still reaches the clipboard and `Capture failed` is posted.
3. **Show** the Quick Access thumbnail.

- **Format:** PNG at native resolution (Retina = 2 pixels per point).
- **Downscale Retina captures to 1×** (off by default): the image is scaled by 1/scale before encoding; the capture then counts as 1 pixel per point.
- **Names:** `Screenshot YYYY-MM-DD at HH.MM.SS.png` (local time, `en_US_POSIX`), `Recording … .mp4` / `.gif`, `Collection …`. A taken name gets ` (2)`, ` (3)`, … before the extension. Files are written with `.withoutOverwriting`.
- **When save-to-folder is off:** the file lives in `~/Library/Caches/dev.msenechal.cleanshotcopy/Captures/` until Quick Access Save moves it; files older than 24 h there are deleted at the next launch.

### 1.4 Quick Access

A stack of floating thumbnails, one per capture, newest at the bottom.

| Property | Value |
|---|---|
| Thumbnail size | 240 × 176 pt (image area 136 pt high, strip 40 pt) |
| Position | Bottom-left (default) or bottom-right of the visible frame of the display under the mouse at the latest capture; 16 pt margin, 10 pt gap |
| Stack | At most 5, and never more than fit the screen's visible height (4 on a ≈850 pt laptop screen). The oldest **non-hovered** thumbnail leaves first |
| Auto-dismiss | 5 s by default; Never, 5, 10, 30, 60 s. Checked every 0.5 s |
| Timer pauses | while hovered; while the capture is open in an editor; while any ⇧-click selection exists |
| Look | Night chrome: gradient panel, 10 pt corners, dark appearance |
| Appear / leave | Fade in 0.18 s; fade out 0.15 s; the stack slides to close gaps (0.18 s) |

**The thumbnail:**
- Image, aspect-fill, clipped.
- ✕ at top-left (yellow glyph on a dark circle) dismisses.
- Source chip at top (app icon + short label); click opens the source (file 06).
- Badge at bottom-right for media: `▶ mm:ss` (recordings), `GIF`.
- Sweep badge `⚠ N possible` in amber at the image's bottom edge; click opens the editor (file 07).
- When selected (⇧-click): a 2 pt accent border and a ✓ at top-right.

**Strip buttons:**

| Button | Screenshot | Recording | GIF |
|---|---|---|---|
| Copy | PNG + URL (the file's data) | file reference | file reference |
| Save / Save As… | `Save` while unsaved (moves into the save folder); `Save As…` once saved (save panel, writes a copy) | same | same |
| Primary (yellow) | **Edit** (editor) | **Trim** | **Open** |
| ⋯ menu | Copy Text, Copy for AI, Copy as Markdown, Open Source (or Open Source ▸ for several sources), Find Similar (disabled until indexed), Reveal in Finder, Delete | Open Source, Reveal in Finder, Export GIF…, Delete | Open Source, Reveal in Finder, Delete |

- The action you usually take for captures from that app gets a yellow ring on the strip (or on ⋯), and a `★ ` prefix in the menu (learned per app and kind, file 06).
- **Delete:** saved files go to the Trash; temp files are deleted.
- **Save As… copy** keeps the source and snapshot xattrs and gets a new capture ID (it's a new capture for the index).
- **Copy as Markdown** saves an unsaved capture to the folder first (so the link outlives the temp folder) and notifies `Markdown link copied` / `<file name>`.
- **Drag** the image to drop the file anywhere (Finder, Slack, browsers). After an editor ⌘S, the dragged file is the edited one; after Save, it's the moved file.
- **Double-click** = the primary action (editor / trim / open).
- **Esc** while hovering: clears the ⇧-click selection if there is one, else dismisses that thumbnail.
- **Hover** makes the thumbnail key (so it receives Esc) without activating Bugeye; when the pointer leaves, the keyboard goes back to the app you were typing in.
- While a capture is open in the editor its thumbnail stays (timer paused); after an editor Save, its preview refreshes.

**⇧-click selection and Combine (M11):**
- ⇧-click a screenshot thumbnail toggles it in the selection (recordings and GIFs can't be selected). Every timer pauses while anything is selected.
- With two or more selected, the most recently ⇧-clicked one still selected replaces its strip with a single yellow **Combine (N)** button. It creates a new collection from the selected captures, oldest first (stack order), then clears the selection.
- A plain click on any thumbnail, or Esc, clears the selection; every thumbnail then gets its full timeout again (except the hovered one and those being edited).
- Dismissing a selected thumbnail removes it from the selection.

---

## 2. How it's built

### 2.1 Types and files

| File | Type | Role |
|---|---|---|
| `CleanShotCopy/CaptureCoordinator.swift` | `CaptureCoordinator` (`@MainActor`) | Orchestrates every still capture: busy flag, permission, freeze, selection, capture, delivery, Quick Access, background attachments |
| `CleanShotCopy/Selection/AreaSelectionController.swift` | `AreaSelectionController`, `FrozenScreen`, `LastArea`, `SelectionPurpose`, `SelectionResult` | Overlay lifecycle and result |
| `CleanShotCopy/Selection/SelectionOverlayView.swift` | `SelectionOverlayView`, `CrosshairLine`, `LoupeView` | Drawing and mouse/keys |
| `CleanShotCopy/Selection/SelectionOverlayWindow.swift` | `SelectionOverlayWindow` | Borderless per-display window; `closeLeftovers()` |
| `CSCapture/ScreenCapturer.swift` | `ScreenCapturer`, `CaptureError` | ScreenCaptureKit stills, permission, error mapping |
| `CSCapture/WindowShadow.swift` | `WindowShadow` | Finds the window body in a capture; recaptures at full scale |
| `CSCore/ScreenGeometry.swift` | `ScreenGeometry` | Cocoa ↔ Quartz flips, view → display-local, point → pixel crop |
| `CSCore/SelectionGeometry.swift` | `SelectionGeometry`, `LockedAxis`, `LoupeSample` | Drag rect, axis lock, from-centre, capturable, loupe frame and sample |
| `CSCore/WindowHitTest.swift` | `WindowInfo`, `WindowHitTest` | Parse `CGWindowListCopyWindowInfo`; topmost window under a point |
| `CSCore/ImageCodec.swift` | `ImageCodec` | PNG encode/decode, downscale |
| `CSCore/FileNamer.swift` | `FileNamer` | Timestamped names with collision suffixes |
| `CSCore/OutputRouter.swift` | `OutputRouter`, `CaptureItem`, `ClipboardWriting`, `OutputResult`, `OutputWarning` | Save/copy/move/trash |
| `CSCore/CaptureKind.swift` | `CaptureKind` | `screenshot/recording/gif/collection` → prefix, extension |
| `CSCore/QuickAccessStack.swift` | `QuickAccessStack<Item>` | Bounded stack with "spared" item and screen-fit limit |
| `CSCore/DismissTimer.swift` | `DismissTimer` | Pausable countdown |
| `CSCore/QuickAccessSelection.swift` | `QuickAccessSelection` | ⇧-click selection, Combine host |
| `CSCore/TempJanitor.swift` | `TempJanitor` | 24 h purge |
| `CleanShotCopy/QuickAccess/QuickAccessController.swift` | `QuickAccessController` | Entries, rendering, layout, timer tick, actions |
| `CleanShotCopy/QuickAccess/QuickAccessPanel.swift` | `QuickAccessPanel` (`NSPanel`) | Non-activating floating panel |
| `CleanShotCopy/QuickAccess/ThumbnailView.swift` | `ThumbnailView`, `ThumbnailActions`, `SourceChip*` | SwiftUI view |
| `CleanShotCopy/NSScreen+Display.swift` | `displayID`, `underMouse`, `primaryHeight` | Screen helpers |

### 2.2 Coordinate systems (the main source of bugs to avoid)

| Space | Origin | Unit | Used by |
|---|---|---|---|
| Cocoa global | bottom-left of the **primary** (menu-bar) display, y up | points | `NSScreen.frame`, `NSEvent.mouseLocation`, window frames |
| Quartz global | top-left of the primary display, y down | points | `CGWindowListCopyWindowInfo` bounds, `CGDisplayBounds`, AX |
| View-local | bottom-left of one overlay view | points | mouse events in the overlay |
| Display-local top-left | top-left of one display | points | `LastArea.rect`, `SelectionResult.area.rect`, provenance |
| Image pixels | top-left of the frozen image | pixels | cropping |

Conversions (`ScreenGeometry`):
- Cocoa ↔ Quartz: `y' = primaryHeight − rect.maxY` (its own inverse). `primaryHeight = NSScreen.screens.first.frame.height`.
- View rect → display-local top-left: `y' = screenHeight − rect.maxY`.
- Display-local points → pixel crop: multiply by `scale`, `.integral` (rounded outward), intersect with the image bounds; nil when less than 1 × 1 px remains.

Displays left of or above the primary one have negative origins; the conversions above handle them (unit tests cover negative-origin and 1× cases).

### 2.3 Scale

- **`FrozenScreen.scale = image.width / screen.frame.width`**, derived from the image actually captured, not from `backingScaleFactor`. This stays right for scaled ("More Space") display modes and for mixed 2× + 1× setups.
- Full-screen captures use the same formula.
- `CaptureItem.pixelsPerPoint` records it (1 after downscale); later OCR, exact text and collections depend on it.

### 2.4 ScreenCaptureKit calls

**Display still** (`captureDisplay(_:excludingPID:)`):
1. `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`.
2. Find `SCDisplay` by `displayID`, else `CaptureError.displayNotFound`.
3. Excluded windows = `content.windows` whose `owningApplication.processID == getpid()`.
4. `SCContentFilter(display:excludingWindows:)`.
5. `SCStreamConfiguration`: `width/height = filter.contentRect.size × filter.pointPixelScale` (rounded), `showsCursor = false`, `captureResolution = .best`.
6. `SCScreenshotManager.captureImage(contentFilter:configuration:)`.

**Window still** (`captureWindow(_:)`):
1. `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)`; find `SCWindow` by ID else `.windowNotFound`.
2. `SCContentFilter(desktopIndependentWindow:)` → transparent background.
3. Config: `ignoreShadowsSingleWindow = false` (keep the shadow), `showsCursor = false`, `captureResolution = .best`.
4. Size through `WindowShadow.atFullScale` (§2.5).

**Errors:** `ScreenCapturer.map` turns `SCStreamErrorDomain` / `userDeclined` into `.permissionDenied` (→ the permission alert), passes `CaptureError` through, and wraps anything else as `.failed(localizedDescription)` (→ `Capture failed` notification).

**Permission:** `CGPreflightScreenCaptureAccess()` before every capture (`begin()`), `CGRequestScreenCaptureAccess()` to register and prompt.

### 2.5 Window captures at full scale (`WindowShadow`)

ScreenCaptureKit fits the window **and its shadow** into the pixel size you ask for. Asking for the window's own size (`contentRect × pointPixelScale`) therefore squeezes the window: with a shadow about 10 % of the window size on each side, the body comes out at ≈ 1/1.2 ≈ 0.83× (1.67 px per point on a 2× display). On the user's 1× external monitor this looked visibly soft.

Fix (c66c4cc):
1. Capture at `window size × scale`.
2. `WindowShadow.body(in:)` finds the window's own pixels by opacity: alpha ≥ 128 (the shadow stays well under half opacity; a translucent window body is above it). Each edge is measured along three rows or columns (¼, ½, ¾); they must agree within 2 px, otherwise (rounded corner, translucent toolbar) the result is nil.
3. `got = body.width / window.width`. If `got < scale × 0.99`, capture again at `size × scale / got`. Otherwise (or if no body is found) keep the first image.

Result: the window body is at the display's full scale and the shadow comes on top. Tested with a synthetic squeezed image and an integration test that opens a 400 × 300 window on every real display and checks the body within 2 px.

`WindowShadow.body` is also used by the M9 snapshot code to place a window's Accessibility frames inside the capture (no snapshot unless the edges are found exactly: 121c9d3).

### 2.6 `CaptureCoordinator` flows

State: `isCapturing` (busy flag), `selection` (the live `AreaSelectionController`), `lastArea`, `selectionWindows` (window list at hotkey time), `scrollSession`, `lastItem` (drives Open Last Capture), plus injected `sweep`, `indexer`, `snapshotter`, `collector`, `textCopier`.

`begin()`: returns false if busy; if Screen Recording is missing shows the alert and returns false; else sets `isCapturing = true`.

**Full screen** (`captureFullscreen(allDisplays:)`): screens = all, or `NSScreen.underMouse` (screen containing `NSEvent.mouseLocation`, else `main`). For each screen, sequentially: read windows for provenance, start the AX snapshot for that display's windows, `captureDisplay(excludingPID: getpid())`, `finish(image:scale:…)`. An error reports and stops the loop. `defer` clears the busy flag.

**Area / window / text / scrolling** (`select(purpose:startInWindowMode:completion:)`):
1. Remember `NSWorkspace.shared.frontmostApplication` (to give focus back).
2. In a `Task`: capture every display (`captureDisplay(excludingPID:)`) into `FrozenScreen`s, sequentially.
3. Read `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` and parse with `WindowHitTest.parse` (front-to-back order kept).
4. Build `AreaSelectionController`, hand it the Esc register/unregister closures, `NSApp.activate(ignoringOtherApps: true)`, `begin()`.
5. On completion: `selection = nil`, reactivate the previous app, then:

| Result | Screenshot (`handle`) |
|---|---|
| `.area(displayID, rect, image, scale)` | Store `lastArea`; `finish` with the **cropped frozen image** (no second capture), provenance and snapshot tasks; clear busy |
| `.window(id, scale)` | Start provenance and snapshot; in a `Task`, `capturer.captureWindow(id)` (a **live** capture, not the frozen one), `finish`; clear busy in `defer` |
| `.cancelled`, `.display` | Clear busy |

Text and scrolling handle the same results differently (files 05). For ⇧⌘7 the busy flag is released as soon as the pixels are in hand, so a ⇧⌘4 during OCR works (5655aba).

**`finish(image:scale:provenance:snapshot:)`:**
1. `router.settings = settingsStore.load()` (fresh settings each time).
2. Downscale if the setting is on and scale > 1 (`ImageCodec.downscaled(by: 1/scale)`, high interpolation, premultiplied RGBA in the image's colour space).
3. `ImageCodec.pngData` (`CGImageDestination`, `public.png`, no extra properties). Failure → `Capture failed` / `Could not encode PNG.`
4. `router.deliver(pngData:pixelsPerPoint:)` → warnings become the "Couldn't save to folder" notice.
5. `lastItem = result.item`; `quickAccess.show(item, thumbnail: output)`.
6. When the provenance task finishes → `attach(provenance, to:)`: through Quick Access if the thumbnail is still up (writes the xattr on the *current* file, which Save may have moved), else directly onto the file and `lastItem`.
7. When the AX snapshot finishes → `attach(snapshot, to:)`, unless an editor already saved over the capture (`savedByEditor`), whose file now holds the edit's snapshot (3281794).
8. `indexer.add(item, afterSweep:)`; `sweep.scan(...)` (the index reuses the sweep's OCR).

Provenance and the snapshot never delay the capture; they arrive later and are written onto whatever file the capture is now.

### 2.7 `AreaSelectionController`

- `init(purpose:startInWindowMode:frozen:windows:ownPID:lastArea:completion:)`.
- `begin()`: `SelectionOverlayWindow.closeLeftovers()`; one `SelectionOverlayWindow` + `SelectionOverlayView` per frozen screen, `owner = self`, `orderFrontRegardless()`; make the window under the mouse key and its view first responder; `registerEscape { cancel() }`; show the cursor on every view at the current mouse; log `begin`; update hover.
- `updateHover(globalCocoaPoint:)`: in window mode, convert to Quartz and `WindowHitTest.topmost(at:in:excludingPID:)`; redraw all overlays only if the hovered window changed.
- `clickInWindowMode()`: beep if nothing hovered; for recording/scrolling, beep if `RecordingCoordinator.targetForWindow` finds no display for the window's centre; else `.window(id, scale of the display holding its centre, fallback first frozen scale, fallback 2)`.
- `completeArea(viewRect:on:)` → display-local rect → `crop`.
- `recaptureLast()` → crop `lastArea.rect` from the frozen display with the same ID, or beep.
- `crop`: pixel rect from `ScreenGeometry.pixelRect`, `image.cropping(to:)`, `.area(...)`; beep if empty.
- `finish(_:)`: guarded by `finished`; `unregisterEscape()`; log; `orderOut` **and** `close` every overlay; `closeLeftovers()`; call the completion.
- `isActive` = `!finished`.

`lastArea` lives in the coordinator's memory only (lost at quit). Area screenshots, Capture Text and scrolling captures share it; recording keeps its own.

### 2.8 `SelectionOverlayWindow` and view

Window: borderless, `level = .screenSaver`, non-opaque, clear background, no shadow, accepts mouse-moved events, `isReleasedWhenClosed = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `canBecomeKey/Main = true`, frame = the screen's frame.

View:
- Layer-backed. Draws the frozen image, the dim (even-odd path around the selection), a 1 pt white border, the size label and the hint.
- **Crosshair and loupe are subviews** moved on mouse move (`CrosshairLine` = a filled layer; `LoupeView` redraws only its own 122 pt square). A mouse move never redraws the frozen screen (12b984a). Drag changes invalidate only the union of the old and new selection rects plus label (`invalidateSelection`). Tests read the accumulated `damage` rect to check this.
- Tracking area: `.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect`.
- `acceptsFirstMouse = true`, `acceptsFirstResponder = true`, crosshair cursor rect over the bounds.
- `mouseEntered`: if no button is pressed **and the controller is still active**, make this window key and the view first responder (so the display under the pointer receives keys).
- `mouseDown`: window mode → `clickInWindowMode()`; else anchor = point, reset Shift state, `fromCenter` from the event's flags.
- `mouseDragged`: update `current`, **re-read modifiers from the drag event** (`flagsChanged` only reaches the key overlay, which may be another display's), start the axis lock once moved > 2 pt from the Shift point.
- `mouseUp`: `isCapturable` (≥ 4 × 4 pt) → `completeArea`; else `clickedWithoutSelection` (recording → display).
- `rightMouseDown` → `cancel()`.
- `keyDown`: 53 Esc → cancel; 49 Space → toggle mode; 36 / 76 Return / keypad Enter → recapture last.
- `applyModifiers`: Shift only sets its start point once the selection has non-zero width and height (bec583b).

Loupe maths (`SelectionGeometry.loupeSample`): a fixed 15 × 15 pixel square around the pointer's pixel, **slid** inside the image at edges (never shrunk: a smaller crop stretched into the loupe distorted it), with the pointer's column/row inside it for the red marker.

### 2.9 `WindowHitTest`

- `parse` reads `kCGWindowNumber`, `kCGWindowOwnerPID`, `kCGWindowBounds` (required), `kCGWindowOwnerName`, `kCGWindowLayer`, `kCGWindowAlpha`, `kCGWindowName` (nil without Screen Recording or for untitled windows). Order is the window server's front-to-back.
- `topmost` = first window with `layer == 0`, `ownerPID != own`, `alpha > 0`, bounds containing the Quartz point.

### 2.10 `OutputRouter`

```swift
public static var defaultTempDirectory: URL   // ~/Library/Caches/dev.msenechal.cleanshotcopy/Captures/
func deliver(pngData: Data, kind: CaptureKind = .screenshot, pixelsPerPoint: CGFloat = 1) throws -> OutputResult
func deliverFile(at source: URL, kind: CaptureKind, pixelsPerPoint: CGFloat = 1, date: Date? = nil) throws -> OutputResult
func save(_ item: CaptureItem) throws -> CaptureItem   // temp → save folder; saved items unchanged
func trash(_ item: CaptureItem) throws                 // saved → Trash, temp → delete
```

- `deliver`: write first (save folder, falling back to temp with `.saveFolderUnavailable`), **then** copy, so the clipboard can carry the file URL. If even the temp write throws, copy the image anyway and rethrow.
- `deliverFile` (recordings, trimmed copies, GIFs): **moves** the finished file; `date` names it (a recording is named by its start time); clipboard gets a file reference; reads the provenance xattr already written on the file.
- `save` and `move` keep the source file's extension (a recording kept as `.mov` when MP4 conversion couldn't run stays `.mov`: a4ba107).
- Directories are created on demand (`withIntermediateDirectories: true`).
- `CaptureItem`: `id` (UUID), `fileURL`, `isSaved`, `kind`, `createdAt`, `pixelsPerPoint`, `provenance?`, `snapshot?`.

### 2.11 `FileNamer`

`DateFormatter` with `en_US_POSIX`, the current time zone, format `yyyy-MM-dd 'at' HH.mm.ss`; base = `"<prefix> <date>"`. `uniqueURL` loops ` (2)`, ` (3)`… until the path doesn't exist. Two captures in the same second (⌥⇧⌘3 on two displays) never overwrite each other.

### 2.12 Quick Access internals

**`QuickAccessStack<Item: Identifiable>`** (CSCore):
- `capacity` 5; `items` oldest first.
- `push(item, limit:, sparing:)` appends, then evicts from the oldest, skipping `spared` (the hovered ID) and never the new item, until `count ≤ min(capacity, limit)`. Returns the evicted items.
- `fitting(height:itemHeight:gap:margin:)` = `max(1, floor((height − 2·margin + gap) / (itemHeight + gap)))`.

**`DismissTimer`**: `remaining` + `runningSince`; `pause(at:)` banks the elapsed time; `resume(at:)`; `isExpired(at:)`; `restart(duration:at:)`. `duration == nil` never expires (Auto-dismiss Never).

**`QuickAccessSelection`**: ordered `ids`, `host` (last ⇧-clicked still selected), `combineHost` only when ≥ 2, `timersPaused` when non-empty, `ordered(byStack:)` for Combine.

**`QuickAccessController.show(item, thumbnail:, badge:)`:**
1. Duration from fresh settings (0 → nil).
2. New `QuickAccessPanel` (240 × 176), entry with a ~480 px-wide **preview** (`ImageCodec.downscaled`), not the full capture.
3. Pause the new timer if a selection exists.
4. `anchorScreen = NSScreen.underMouse`; `limit = fitting(visibleFrame.height, 176, gap 10, margin 16)`.
5. `stack.push(entry, limit:, sparing: hoveredID)`; evicted panels give focus back if key, then `orderOut`.
6. Render (SwiftUI `ThumbnailView` in an `NSHostingView`; re-renders replace `rootView`), alpha 0, layout, `orderFrontRegardless()`, fade in.
7. Start the 0.5 s `Timer` ticker (main run loop; `MainActor.assumeIsolated` in the block). The ticker stops when the stack is empty.

**Layout:** for `stack.items.reversed()` (newest first) at index i: `y = visible.minY + 16 + i·(176 + 10)`, `x = visible.minX + 16` or `visible.maxX − 16 − 240`. Every thumbnail moves to the latest anchor screen.

**`QuickAccessPanel`:** `NSPanel` with `[.nonactivatingPanel, .borderless]`, `level = .statusBar`, clear, shadow, not movable, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, dark appearance. `canBecomeKey = true`, `canBecomeMain = false`. Esc arrives either as `keyDown` keyCode 53 or as `cancelOperation(_:)` (from the hosted SwiftUI view); both call `onEscape` (d967d1f).

**Hover:** `onHover(true)` → set `hoveredID`, pause the timer, remember Bugeye's current key window (if Bugeye is active and it's not a thumbnail), `panel.makeKey()`. `onHover(false)` → resume unless editing or a selection exists, and if the panel was key, `returnKeyFocus()`: re-key the remembered Bugeye window if Bugeye is active, else `frontmostApplication.activate()`.

**Actions** go through `perform(_ action: QuickAction, on: id)`, which first records the action in `ActionHabitsStore` (per main-source app and kind), then dispatches. Closures capture only the entry's `id` and a fallback URL, never the entry (it owns the panel → retain cycle).

**Following the file:** `onItemChanged` fires on Save, provenance arrival and snapshot arrival; AppDelegate chains it to the coordinator (`lastItem`), editors, media windows and the indexer. `updatePreview` refreshes the image after an editor save; `setEditing` pauses/resumes; `dismiss(fileURL:)` lets Duplicates remove a trashed capture's thumbnail.

**Save As…:** `NSSavePanel` with the current file name and its content type; `saveCopy(of:to:)` removes any existing file at the destination, copies, copies the provenance and snapshot xattrs explicitly (a plain copy can drop them), assigns a new capture ID xattr, and reports the copy through `onSavedCopy` (indexed as a new capture).

**Thumbnail gestures** (SwiftUI): `.onTapGesture(count: 2)` → primary action; `.simultaneousGesture(TapGesture())` → ⇧ held (`NSEvent.modifierFlags`) toggles selection, else clears it; `.onDrag { NSItemProvider(contentsOf: currentFileURL) }`.

---

## 3. Gotchas and bugs we hit

### 3.1 The stuck selection overlay (M1 → M6 part 4 → M9)

**Symptom.** Reported once in M1 and again later: after a capture, the dimmed frozen overlay stayed on every screen. It ignored Esc and clicks, covered every app, and the only way out was `pkill -9`.

**First theory (M1 backlog).** The overlay never became key, so Esc never reached it, and a click without a drag is "too small" so it stays open. Proposed fix: rework it as a non-activating panel.

**M6 part 4 (23896ed): safety nets only** (the user's call; no panel rework):
- `rightMouseDown` cancels, even when the overlay isn't key.
- While any overlay is up, Esc is a temporary global Carbon hotkey (ID 103) that cancels it, unregistered in `finish`. It has its own ID so it never clobbers the scrolling session's Esc/Return (100–102).
- Applies to every purpose (screenshot, recording, scrolling, text) through `registerSelectionEscape` closures from AppDelegate.

**Real root cause (M9, 272ee65).** A **late `mouseEntered` event** arrived at an overlay view after its selection had finished. The view called `window.makeKeyAndOrderFront`, which brought the finished overlay window back on screen. Its controller was gone (and its Esc hotkey unregistered), so nothing could close it: it covered every screen and ignored clicks and Esc. `finish` had only called `orderOut`, so the windows still existed and could be re-ordered.

**Fix:**
- `mouseEntered` returns early unless `controller?.isActive == true`.
- `finish` calls `orderOut` **and** `close` on every overlay.
- Each `SelectionOverlayWindow` has a weak `owner`. `SelectionOverlayWindow.closeLeftovers()` closes every overlay window whose owner is missing or finished (and drops its content view); it runs at every selection's `begin` and at every `finish`.
- The lifecycle is logged (subsystem `dev.msenechal.bugeye`, category `selection`): `begin …`, `finish …`, and an error `closing a leftover overlay <n>` if one was ever visible.

If it recurs: run `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'` **before** killing the app. `lldb` can't attach to the installed, self-signed app.

Tests: `aFinishedSelectionsOverlayIsNotBroughtBackByTheMouseEntering`, `leftoverOverlaysAreClosedWhenASelectionBeginsOrEnds`, `escapeHotkeyIsHeldWhileTheOverlayIsUpAndCancels`, `escapeHotkeyIsReleasedWhenAnAreaIsChosen`, `rightClickCancelsTheSelection`.

### 3.2 Other bugs

| Symptom | Root cause | Fix |
|---|---|---|
| Window captures soft, especially on a 1× monitor (≈0.83×) | ScreenCaptureKit fits window **plus shadow** into the requested size | Measure the body by opacity, recapture larger (`WindowShadow.atFullScale`, c66c4cc) |
| Holding Shift before dragging locked the selection at zero size | The Shift start point was set before the drag had a size | Start the lock only once width and height are > 0 (bec583b) |
| Shift/Option stopped working when a drag crossed onto another display | `flagsChanged` goes to the key overlay, which may be another display's | Re-read modifiers from each `mouseDragged` event; `mouseEntered` doesn't steal key while a button is pressed (bec583b) |
| Overlay lagged on 5K/6K and multi-display setups | Every mouse move redrew the whole frozen screen | Crosshair and loupe as moved subviews; selection changes invalidate only old ∪ new rects (12b984a) |
| Crosshair and loupe missing until the first mouse move | Drawn only on `mouseMoved` | `showCursor(atScreenPoint:)` at `begin` (12b984a) |
| Loupe distorted at screen edges | A smaller crop near the edge was stretched to fill the loupe | Slide a fixed-size sample inside the image; clamp the loupe frame on screen (12b984a) |
| Clicking a mostly off-screen window to record cancelled the overlay | No display for the window's centre → result treated as cancel | Beep and keep the overlay open (820d452) |
| A ⇧⌘4 pressed while ⇧⌘7's OCR ran was dropped | Busy flag released only when OCR finished | Release when the pixels are in hand (5655aba) |
| Memory grew with every thumbnail; evicted panels never freed | Retain cycle panel → hosting view → action closure → entry → panel; and each entry held the full-resolution capture | Closures capture the ID only; keep a ≈480 px preview (4229429). Leak test `evictedQuickAccessPanelIsDeallocated` |
| Typing went into a hovered thumbnail instead of the user's app | Hover makes the panel key | Give focus back on hover-out/dismiss: previous Bugeye key window, or the frontmost app (4229429, a77bc5a) |
| Hovered thumbnail evicted by a new capture | Stack evicted strictly oldest-first | `push(…, sparing: hoveredID)` (c9fe666) |
| Thumbnails off screen on a laptop | Fixed capacity of 5 | Limit to what fits the visible height (c9fe666) |
| Esc on a thumbnail left a gap in the stack | Esc arrived as `cancelOperation:` from the SwiftUI view; NSPanel's default handling skipped the stack | Override `cancelOperation` to call `onEscape` (d967d1f) |
| Quick Access Save renamed a `.mov` to `.mp4` | `save` used the kind's extension | Keep the source extension (a4ba107) |
| Open Last Capture enabled for a deleted file | Enabled state set at capture time | Checked in `menuNeedsUpdate` (60d29d1) |
| Late source/snapshot record lost after Quick Access Save moved the file | Written to the original path | Write through Quick Access onto the entry's current file; coordinator fallback otherwise |
| A late snapshot overwrote an editor's saved snapshot | Snapshot attach didn't know about the save | `savedByEditor` set; skip (3281794) |
| "Couldn't save to folder" banner invisible right after ⇧⌘4 | Notifications suppressed while Bugeye is frontmost | `UNUserNotificationCenterDelegate.willPresent` (4229429, file 01) |
| Slow copy of large captures | Eager TIFF | Lazy TIFF provider (2adb4dd) |

---

## 4. Known open issues (from `docs/backlog.md`)

- A new capture pushes the hovered thumbnail up one slot, so until the mouse moves the pointer sits over the new one, whose timer runs while the hovered one stays paused. On a screen that fits one thumbnail, a hovered one plus the new one exceed the limit.
- `AreaSelectionController` has no `deinit` safety net: dropping a selection without `finish` would leave the global Esc registered. Unreachable today.
- `SourceChip` looks the app icon up with LaunchServices on every render (`ThumbnailView.swift`); compute it once.
- The ✓ on a selected Quick Access thumbnail can sit over the source chip.
- A late source record can be lost when the editor is open but the thumbnail is gone: `CaptureCoordinator.attach`'s fallback never tells the editors, so the next ⌘S drops the xattr. Fix: call `quickAccess.onItemChanged?(current)` there.
- A very tall scrolling capture is rarely swept before its thumbnail's 5 s timeout, and the scan keeps running after the thumbnail goes.
- Every indexed file re-renders every Quick Access thumbnail (`refreshThumbnails`).
- A window capture's edge search (`PendingSnapshot.windowCapture`) draws the whole image on the main actor before `finish`: tens of ms before the thumbnail on a 2× window.

Not in the backlog but true of the code:
- The freeze captures displays **one after another**, and fetches `SCShareableContent` once per display. On several large displays the overlay appears noticeably later.
- ⌥⇧⌘3 also captures displays sequentially, so its files can carry different seconds.
- `lastArea` is lost at quit.
- Temp captures are only purged at launch.

---

## 5. Do it better next time

1. **Model the overlay lifecycle as a state machine with one owner.** States: `idle → frozen → selecting(mode) → finished`. Windows belong to the state; leaving `selecting` closes them, and no event handler may re-show a window unless the state says so. Write it so the stuck-overlay bug can't be expressed, and test it without AppKit.
2. **Close windows, don't just hide them.** `orderOut` leaves a window that any `makeKeyAndOrderFront` can bring back. Close on finish, and keep a leftover sweep at start and end as a second line of defence.
3. **Log every overlay begin/finish from day one** (it was added only after the bug hunt).
4. **Freeze all displays concurrently** (`withThrowingTaskGroup`) and fetch `SCShareableContent` once per freeze. Same for ⌥⇧⌘3.
5. **Make coordinates explicit types** (`CocoaPoint`, `QuartzRect`, `DisplayLocalRect`, `PixelRect`) so a wrong flip doesn't compile. Derive scale from the captured image, as now.
6. **Request window captures at full scale from the start**: know that ScreenCaptureKit fits window + shadow into the requested size. Either compute the shadow inset up front or keep the measure-and-recapture approach (one extra capture only when needed).
7. **Quick Access as a pure view model**: the stack, timers, hover, selection, eviction and focus-return rules are already mostly pure; move the rest (`returnKeyFocus` decision, `escape` behaviour, layout frames) into the core and keep the panel a dumb renderer.
8. **Never capture the entry in a closure** that the entry's own view holds; pass IDs. Add a leak test for every panel type from the first commit.
9. **One event bus for "capture changed"** (moved, saved, provenance, snapshot, edited, deleted) instead of chained `onItemChanged` closures, so late arrivals reach every listener (fixes the open "late record lost" item by construction).
10. **Persist `lastArea`** per display if Return-to-recapture matters across launches; purge temp files periodically.

### 5.1 Portable core vs macOS shell (see `13-rebuild-strategy-agentic-ci-and-claude.md`)

| Portable core (Linux-testable) | macOS shell |
|---|---|
| `ScreenGeometry`, `SelectionGeometry` (axis lock, from-centre, capturable, loupe frame and sample) on Foundation's `CGRect/CGPoint` | Overlay `NSWindow`/`NSView`, tracking areas, cursor, drawing |
| Selection **state machine**: modes, key handling (Esc, Space, Return), modifier rules, result types, overlay ownership and leftover rules, Esc-hotkey lifetime | Carbon Esc hotkey adapter; `NSEvent` → core events |
| `WindowHitTest` (given parsed `WindowInfo`s) | `CGWindowListCopyWindowInfo` reader |
| `WindowShadow.body` and `atFullScale` on a `PixelBuffer` alpha channel, with the capture as an injected closure | ScreenCaptureKit adapter (`ScreenSource` port): display and window stills, own-PID exclusion, error mapping |
| Crop maths and downscale on `PixelBuffer` | PNG encode/decode (ImageIO), `CGImage` ↔ `PixelBuffer` |
| `FileNamer`, `OutputRouter` (behind `FileSystem` and `ClipboardWriter` ports), `TempJanitor`, `CaptureItem` | `NSPasteboard` adapter, Trash (`FileManager.trashItem`) |
| `CaptureCoordinator` flow logic: busy flag, ordering (save → copy → show → attach later), late-arrival rules (`savedByEditor`, current file), warnings → notice texts | Permission checks, `NSWorkspace` app reactivation |
| Quick Access view model: `QuickAccessStack`, `DismissTimer`, `QuickAccessSelection`, hover/edit/selection timer rules, eviction with a spared item, screen-fit limit, layout frames, button sets per kind, menu titles with ★, Combine | `NSPanel` + SwiftUI thumbnail view, animations, drag provider, `NSSavePanel`, focus return |

Tests for the core run on Linux with fakes for screens, windows, files and clipboard; the overlay's look, the loupe and real window captures are checked on the macOS tiers (hosted runner for AppKit view-model wiring, the self-hosted Mac for real ScreenCaptureKit and a fixture window of known size for the full-scale check).
