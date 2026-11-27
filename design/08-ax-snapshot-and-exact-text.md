# 08: Accessibility snapshot and exact text (M9)

At capture, Bugeye reads the Accessibility (AX) tree of the windows under the capture and keeps what it saw with the file. This **UI snapshot** holds:
- the visible text lines, verbatim;
- the UI element frames;
- the regions those lines cover.

M9 uses it two ways:
- **Exact text:** Capture Text (⇧⌘7), Quick Access Copy Text, the editor's ⇧⌘C and Copy for AI take the app's real text where Accessibility had it, and OCR everywhere else.
- **Snap to UI:** editor shapes snap to captured buttons, fields and text lines. The snapping UX is in `03-editor.md`; this file covers the data that feeds it.

Sources: spec `docs/superpowers/specs/2026-10-23-ax-snapshot-design.md`, plan `docs/superpowers/plans/2026-10-23-m9-exact-text-snap.md`, checklist `docs/manual-checklist-m9-exact-text-snap.md` (sections A–E, all passed), merge `a36419d` (2026-10-26).

---

## 1. What it does

### 1.1 The user's goals

- **Apps that matter:** Terminal, iTerm, VS Code, Cursor, and Arc and Chrome pages.
- **Captures:** area, window and full screen, plus Capture Text.
- **Not captured:** scrolling captures (the content moves) and recordings.
- **Merging:** region by region: exact text where AX covers the area, OCR for the rest, in one reading order.
- **Success means:**
  - a Terminal stack trace pastes character for character, indentation included;
  - VS Code and Cursor code is exact from their **second** capture (the first switches their tree on);
  - Arc and Chrome text reads naturally, with no OCR slips;
  - one click with the rectangle tool frames a captured button;
  - without the permission, or for an app with no tree, everything behaves exactly as before M9.

### 1.2 Who uses the snapshot

| Consumer | Snapshot source | Waits? |
|---|---|---|
| Capture Text ⇧⌘7 | the pending read | OCR runs in parallel; the snapshot gets **at most 1 s**, then OCR alone |
| Quick Access Copy Text | `item.snapshot ?? UISnapshotStore.read(from: fileURL)` | no |
| Copy for AI ("Text:" block) | same | no |
| Editor ⇧⌘C, editor Copy for AI | the snapshot transformed by the edit (`ExactText.edited`) | no |
| Editor snapping | the snapshot's elements and lines (document pixels) | a late snapshot updates the targets |
| M10 index | Copy Text's merge (`b72108e`) | see `09-…` |

### 1.3 The notification

- **Title:** `Text copied` (or `Copied for AI`).
- **Body:** `TextLayout.summary(text)`, then a suffix when at least one exact line was used:
  - one app: ` · exact text from Terminal`;
  - two apps: ` · exact text from A and B`;
  - three or more: ` · exact text from A and others`.
- **Example:** `Traceback (most recent call last): (12 lines) · exact text from Terminal`.
- **Without exact lines:** the plain summary.
- **No text at all:**
  - from a selection: "No text found in the selection";
  - from an image: "No text found in the image";
  - in both cases the body is "The clipboard wasn't changed."

### 1.4 Settings

**Settings → Text & snapping** (`TextSnapSettings`, all on by default):

| Toggle | Key in UserDefaults |
|---|---|
| Read exact text with Accessibility | `textSnap.exactText` |
| Turn on Accessibility in Electron apps and Chromium browsers (VS Code, Cursor, Arc, Chrome) | `textSnap.enableInElectron` |
| Snap annotations to UI elements | `textSnap.snap` |

- The Electron toggle carries the note "Those apps do a little more work while it's on." It is greyed out while exact text is off.
- Each key is read with a default, so older settings files load.
- **Edit → Snap to Elements** in the editor is the same setting. Toggling it updates every open editor and Settings.
- **Settings → Setup**, the Accessibility row:
  - allowed: "Accessibility allowed (keystrokes, auto-scroll and exact text)";
  - not allowed: "Accessibility (optional: keystrokes, auto-scroll and exact text)".

### 1.5 Privacy promises

- **Only what is inside the capture is stored,** never the rest of a window's text.
- **Secure text fields** (subrole `AXSecureTextField`) are never read. Their frame is still a snap target.
- **Only what is drawn:**
  - a text area's visible range;
  - rows whose middle is inside the capture;
  - characters cut at the capture's left and right edges.

---

## 2. How it's built

### 2.1 Files

| Target | File | Role |
|---|---|---|
| CSCore | `UISnapshot.swift` | `UISnapshot`, `SnapshotLine`, `SnapshotElement`; JSON encode/decode |
| CSCore | `UISnapshotStore.swift` | xattr `dev.msenechal.bugeye.uisnapshot` |
| CSCore | `SnapshotGeometry.swift` | Raw AX windows (global points) → image pixels, occlusion, clipping |
| CSCore | `ExactText.swift` | `merge`, `agreeing`, `edited`, `exported`, `summary` |
| CSCore | `TextSnapSettings.swift`, `AppSettings.swift` | Settings |
| CSCore | `TextLayout.swift` (M6) | Row grouping, indentation, summary; reused by the merge |
| CSCapture | `RectangleDetector.swift` | Vision fallback snap targets |
| CSCapture | `WindowShadow.swift` | `body(in:)`: the window's own pixels inside a window capture |
| CSEditor | `Snapper.swift` | Pure snapping rules (`SnapTargets`, `SnapLine`) |
| App | `Snapshot/AXTreeReading.swift` | Protocol over every AX call (faked in tests) |
| App | `Snapshot/LiveAXTree.swift` | Real AX calls, 0.25 s timeout per element |
| App | `Snapshot/AXSnapshotter.swift` | The tree walk |
| App | `Snapshot/PendingSnapshot.swift` | A read in flight; maps to the delivered image; window-capture placement |
| App | `TextCapture/TextCopier.swift` | OCR, merge, clipboard, notification |
| App | `CaptureCoordinator.swift` | Starts reads, attaches results, `savedByEditor` |
| App | `Editor/EditorWindowController.swift`, `Editor/EditorSnapTargets.swift` | Edit-aware snapshot, saves, snap targets |

### 2.2 Data model and storage format

```swift
public struct UISnapshot: Codable, Sendable, Equatable {
    var lines: [SnapshotLine]        // exact text, reading order
    var elements: [SnapshotElement]  // snap targets
    var covered: [CGRect]            // where OCR is replaced by exact text
    var apps: [String]               // owner names of windows that gave text, front first
    var isEmpty: Bool                // lines and elements both empty → never stored
}
public struct SnapshotLine: Codable { var text: String; var box: CGRect; var monospaced: Bool }
public struct SnapshotElement: Codable { var role: String; var box: CGRect }   // "AXButton", …
```

- **Boxes:** every box is in the capture's **image pixels, top-left origin**, clipped to the image.
- **Storage:**
  - the xattr `dev.msenechal.bugeye.uisnapshot` holds compact `JSONEncoder` output;
  - Apple encodes `CGRect` as `[[x,y],[w,h]]`; verified with a one-line script;
  - the xattr helpers are shared with M7 (`ProvenanceStore.setAttribute`, `attribute`, `removeAttribute`).
- **Writes and reads:**
  - writing an empty snapshot **removes** the attribute, so a rewrite never leaves a stale one;
  - corrupt JSON decodes to nil, which behaves as no snapshot;
  - a file system without xattrs makes writes no-ops.
- **Copy-back:** atomic writes drop xattrs, so every rewrite must copy the snapshot back.
  - Quick Access Save As uses `UISnapshotStore.copy(from:to:)`.
  - Editor saves write `exportedSnapshot` (§2.8).
  - Trim and GIF export carry none: recordings have no snapshot.

### 2.3 When a read starts (`CaptureCoordinator`)

`pendingSnapshot(windows:capture:) -> PendingSnapshot?` returns nil unless all of these hold:
- a `snapshotter` is set (nil in tests);
- `textSnap.exactText` is on;
- `accessibilityTrusted()`.

Otherwise it starts `Task.detached { await snapshotter.read(windows, capture:, enableInElectron:) }` **as soon as the pixels are taken**, in parallel with the M7 source record. The capture never awaits it.

| Capture | `capture` rect (Quartz global points) | Windows |
|---|---|---|
| Area | the selection converted with `ProvenanceCollector.globalRect` | `selectionWindows`, the list the overlay froze |
| Full screen / each display | `CGDisplayBounds(displayID)` | `ProvenanceCollector.currentWindows()`; each display's file gets only the windows on that display |
| Window | known only once the image is in: `PendingSnapshot.windowCapture(image, windowBounds:)` (§2.6) | that one window only (nothing in front shows in a window capture) |
| Capture Text area/window | same as above; `PendingSnapshot.task(for: image)` hands TextCopier a `Task<UISnapshot?, Never>` | |
| Scrolling, recordings | none | |

- **Delivery:**
  - after `quickAccess.show`, `Task { if let read = await snapshot.snapshot(imageSize:) { attach(read, to: item) } }`;
  - `PendingSnapshot.snapshot(imageSize:)` uses `pixelsPerPoint = imageSize.width / capture.width`, so the "downscale to 1×" setting is handled for free;
  - it returns nil for an empty snapshot.
- **`attach`:**
  - dropped if `savedByEditor` contains the ID (§3, bug 6);
  - else `quickAccess.updateSnapshot`, which writes the xattr on the entry's current file, updates the item and notifies followers (editor, last item);
  - when the thumbnail is gone, it writes to the last item's file directly.

### 2.4 The tree walk (`AXSnapshotter`)

**The protocol.** Every call goes through `AXTreeReading`, so tests run against `FakeAXTree`:

```swift
protocol AXTreeReading: Sendable {
    func application(_ pid: Int32) -> AXNode          // timeout already set
    func bundle(of pid: Int32) -> AppBundle?
    func windows(of app: AXNode) -> [AXNode]           // AXWindows
    func children(of node: AXNode, limit: Int) -> [AXNode]
    func string(_ attribute: String, of node: AXNode) -> String?   // AXRole/AXSubrole/AXTitle/AXValue
    func frame(of node: AXNode) -> CGRect?             // AXPosition + AXSize
    func visibleRange(of node: AXNode) -> Range<Int>?  // AXVisibleCharacterRange
    func line(forIndex: Int, of: AXNode) -> Int?       // AXLineForIndex
    func range(forLine: Int, of: AXNode) -> Range<Int>?   // AXRangeForLine
    func string(for: Range<Int>, of: AXNode) -> String?   // AXStringForRange
    func bounds(for: Range<Int>, of: AXNode) -> CGRect?   // AXBoundsForRange
    func enableManualAccessibility(_ app: AXNode) -> Bool // AXManualAccessibility = true
}
```

- Ranges are **UTF-16 offsets**. Use `(s as NSString).length`, never `String.count`.
- Frames are Quartz global points with a top-left origin, the same space as `CGWindowListCopyWindowInfo` bounds.

**`read(_ windows:capture:enableInElectron:)`:**
1. **Window filter:** `layer == 0`, `alpha > 0`, `ownerPID != ownPID` (Bugeye's own windows are never read), and bounds intersect the capture.
2. **Concurrency:** each window runs in a task group. Each task hops onto a **private concurrent `DispatchQueue`** (`dev.msenechal.bugeye.accessibility`, `.userInitiated`) through `withCheckedContinuation`. AX calls block until the target app answers, so they must never run on Swift's cooperative pool (§3, bug 1).
3. **Order:** results come back front to back in the input order. A window that can't be read still returns an empty raw window with its bounds, so it still hides what's behind it.

**One window:**
- **Limits (`Walk`):**
  - a deadline of `budgetPerWindow` (**1 s**);
  - `remaining = elementCap` (**5,000** nodes);
  - whatever was read before a limit is kept.
- **App element:** `AXUIElementCreateApplication(pid)` with `AXUIElementSetMessagingTimeout(app, 0.25)`.
- **Electron and Chromium:**
  - **Detection:** the bundle ID is in `ProvenanceCollector.browsers` (`company.thebrowser.Browser`, `com.google.Chrome`), or the bundle contains `Contents/Frameworks/Electron Framework.framework`.
  - **Switch-on:** if the setting allows it and this pid is seen for the first time (`SwitchedOnApps`, an `NSLock`-guarded set of pids), the walker sets `AXManualAccessibility = true` on the app element.
  - **Limit:** this capture may still come back empty; the app builds its tree for the next one. A relaunched app has a new pid, so it is asked again.
- **Window matching:**
  - candidates are AX windows whose frame is within **2 pt** of the CGWindow bounds on all four values;
  - exactly one → it;
  - otherwise the `AXTitle` equal to the CG window title, among the close ones, or among all if none was close;
  - otherwise the first close one.
- **Depth-first walk:** a stack of `(node, clip)`, starting from the window's children with `clip = capture`. For each node:
  1. Decrement `remaining`. A node **with** a frame that doesn't intersect `clip` is skipped with its subtree. A node with no frame is walked.
  2. **Snap target:** if the role is in `elementRoles` and (its centre is inside `clip` or `clip == capture`), append `SnapshotElement(role, frame)`.
     - `elementRoles` = AXButton, AXTextField, AXTextArea, AXSearchField, AXComboBox, AXCheckBox, AXRadioButton (tabs), AXPopUpButton, AXMenuButton, AXTab, AXLink, AXRow, AXCell, AXImage, AXSlider.
  3. **Secure field:** subrole `AXSecureTextField` → stop. It is a target, never read.
  4. **`AXTextArea`:** `readTextArea`, then stop.
  5. **`AXStaticText` / `AXTextField`:** `readValue`, then stop.
  6. **Otherwise:** push the children (`AXUIElementCopyAttributeValues(kAXChildren, 0, limit: remaining)`), first child on top. `AXScrollArea` and `AXWebArea` narrow `clip` to their frame, so content scrolled out of view is not read.
- **Text areas** (Terminal, iTerm, editors):
  - skipped if the frame is under 4×4 pt: Monaco's hidden textarea;
  - only `AXVisibleCharacterRange` is read, line by line, as `monospaced: true`;
  - a blank line is kept, because a stack trace has empty lines.
- **Values** (labels, fields, web text):
  - `AXValue` must contain a non-whitespace character;
  - the row height comes from `AXBoundsForRange(0..<1)`;
  - **read row by row** when the value has a newline **or** the frame is taller than 1.5 rows (wrapped web text);
  - otherwise one cut line;
  - an element that doesn't answer `AXBoundsForRange` gives nothing, and OCR reads it.
- **`readLines`:**
  - first and last line numbers come from `AXLineForIndex`;
  - each line's range from `AXRangeForLine`, clamped to the wanted range;
  - then `cutLine`;
  - it stops when the deadline passes.
- **`cutLine`** keeps only what is shown:
  - the line's `AXBoundsForRange` box must have its **midY inside** the shown rect;
  - the text from `AXStringForRange` has trailing whitespace trimmed;
  - if the box fits horizontally (±0.5 pt), it is kept whole, with its box re-measured for the trimmed length;
  - else the first and last characters inside are found by **bisection** on single-character boxes' midX (`firstIndex(in:where:)`). That is a few calls, not one per character. The kept substring and its own bounds are returned;
  - a failed call aborts that line (nil).
- **Covered regions (`cover`):** for each element that produced lines, a rect is added covering the rows those lines span, at the element's full width, intersected with its frame. Not the whole frame: a text area's frame can run past what's shown, over a status bar that OCR should still read.

### 2.5 Geometry (`SnapshotGeometry.snapshot`)

```swift
static func snapshot(_ windows: [RawWindow], capture: CGRect, pixelsPerPoint ppp: CGFloat, imageSize: CGSize) -> UISnapshot
```

- **Pixel mapping:** `pixel = (point − capture.origin) × ppp`, intersected with the image rect. Anything empty after that is dropped.
- **Occlusion:**
  - windows are front to back;
  - for window *i*, an item whose **centre** lies inside any window in front (`windows[..<i]`) is dropped;
  - covered regions are **subtracted** by the front windows' bounds (`subtract` returns up to 4 rects), so only visible parts stay covered.
- **Elements** are kept only if:
  - both sides are ≥ **4 pt**;
  - they are visible in the capture;
  - they cover ≤ **90 %** of the capture area (a whole web area isn't a target).
- **`apps`:** a window's owner name is added (once, front first) only if it gave at least one line.
- **Line order:** by (minY, minX, original order).

### 2.6 Window captures (`PendingSnapshot.windowCapture`)

**The problem.**
- A window capture image holds the window plus its shadow margins, at the display's scale.
- Since `c66c4cc`, ScreenCaptureKit window captures are recaptured at full scale; ScreenCaptureKit squeezes window + shadow into the requested size. See `02-…`.
- So the AX frame must be placed on the window's own pixels.

**The method:**
- `WindowShadow.body(in:)` draws the image into an RGBA context and finds the opaque body (alpha ≥ 128). The shadow stays under half opacity.
- Each edge is measured along **three** rows or columns (¼, ½, ¾). They must agree to **2 px**, or the result is nil: a translucent toolbar or a rounded corner would shift the edge.
- `scale = body.width / windowBounds.width`. The body height must equal `windowBounds.height × scale` to within 2 px, or nil.
- `capture = (windowBounds.origin − body.origin / scale, imageSize / scale)`. The same pending read is re-pointed with `showing(capture)`.
- When nil, there is **no snapshot**. A shifted snapshot is worse than none, because exact text would replace the wrong pixels.

### 2.7 Merging with OCR (`ExactText.merge(_:map:)`)

1. **Fragments:** each OCR line that **intersects a covered region** is split into its words. Other lines stay whole. OCR reads a label and the field beside it as one line, and each part must be judged on its own.
2. **`agreeing`: drop exact lines the image doesn't show.**
   - For each exact line, the OCR fragments whose centre is inside its box are concatenated left to right.
   - Both sides are reduced to lowercase letters and digits, first 400 characters.
   - If both are non-empty and `Levenshtein × 2 > max(lengths)` (more than half differs), the exact line is dropped and its row is uncovered.
   - This catches an app that changed after the pixels were frozen, or that drew the text elsewhere. OCR slips of a character or two still agree.
3. **Drop OCR** fragments whose centre is inside any covered region.
4. **Exact pieces:** trailing whitespace trimmed. A blank piece is kept only if `monospaced`.
   - If no non-blank exact piece remains, the result is `TextLayout.lines(kept)` (plain OCR) with `exactApps = []`.
5. **Rows:**
   - all pieces are sorted by (minY, minX);
   - a non-monospaced piece joins the current row if that row's first piece is non-monospaced and `TextLayout.sameLine` holds;
   - monospaced pieces are always their own row;
   - each row is sorted by minX.
6. **Indentation:**
   - rows with no exact piece are indented among themselves with `TextLayout.indentation` (M6);
   - an exact row's indentation is its own text's leading spaces, never recomputed.
7. **Joining within a row:**
   - two adjacent **exact** pieces are glued with no space when the gap is under `0.25 × row height` (web text split into styled runs);
   - otherwise one space.
8. **Edges:** leading and trailing empty rows are trimmed. The result is `ExactTextResult(text, exactApps: snapshot.apps)`.

### 2.8 Following the edit (`edited`, `exported`)

**Redactions** are blurs and **filled** rectangles and ellipses (`blurRects` in `EditorWindowController`).

`ExactText.edited(s, crop:, blurs:)`:

| Line kind | Crop cuts it horizontally (its row is shown) | Fully inside crop | Row outside crop | Touched by a redaction |
|---|---|---|---|---|
| **Monospaced** | cut by character: each char is 1/n of the box; keep chars whose centre is inside | kept | dropped | every **word** that a redaction intersects is removed; the spacing before each kept word and the line's indentation are kept; nil if no word is left |
| **Other** (web, labels) | **dropped, and its row uncovered** so OCR of the edit reads it | kept | dropped | **dropped, row uncovered** |

- Non-monospaced character boxes are only estimates (proportional fonts), so those lines are handed to OCR rather than cut.
- **Uncovering** a row splits the covered region holding the line's centre into the parts above, below, left and right of that row.

`ExactText.exported(s, crop:, blurs:, origin:, scale:)`:
- applies `edited`;
- clips elements and covered regions to the crop;
- shifts everything by `origin` (`CanvasLayout.imageOrigin`, which includes frame padding and crop offset);
- scales by `scale`. The editor uses 1, since the export is at document scale.

**In the editor:**
- **On open:** a screenshot's snapshot is read **from its file** (`UISnapshotStore.read`), not from the in-memory item (§3, bug 6).
- **`updateItem`** (a late source or snapshot) keeps the snapshot known at open, because the document is still the original image. If none was known, it takes the late one and refreshes the snap targets.
- **⇧⌘C and Copy for AI:**
  - the edit is rendered;
  - `EditorTextReader.readText` reads OCR and shifts its boxes back into document pixels (by `-imageOrigin`);
  - that is the space `editedSnapshot` is in;
  - then `ExactText.merge`.
- **Saves (⌘S, Save As, file-gone Save As):**
  - `exportedSnapshot` is written to the saved file;
  - Quick Access gets `savedSnapshot`;
  - the coordinator records `editorSaved(item)`, which updates its last item and inserts into `savedByEditor`.

### 2.9 TextCopier

- **⇧⌘7: `copyText(from:pixelsPerPoint:waitingFor:)`:**
  - OCR starts as `async let` while `ProvenanceCollector.within(.seconds(1)) { await pending.value }` waits for the snapshot;
  - `within` resolves with the first of the result or a timer;
  - the slow read finishes unseen.
- **1× images:**
  - `forRecognition` enlarges 2× (`ImageCodec.downscaled(image, by: 2)`; yes, this enlarges);
  - `readMap(…, pixelsPerPoint: 2)` avoids a second enlargement;
  - word and line boxes are scaled back to the image's own pixels **before** they meet the snapshot.
- **Overlapping readings:** two can run (⇧⌘7 twice). Each writes the clipboard, and the last to finish wins.

### 2.10 Snapping data (UX in `03-editor.md`)

**`SnapTargets.from(snapshot:detected:ocr:)`:**
- **Elements:** the snapshot's elements. If there are none, the Vision rectangles.
- **Lines:**
  - the snapshot's lines; each word's box is its characters' 1/n share of the line box;
  - if there are none, OCR lines from `EditorTextReader`'s latest reading;
  - choosing the highlighter triggers that first OCR read if needed.

**`RectangleDetector`:**
- **When:** it runs **once, off the main thread**, when the editor opens and the snapshot has no elements.
- **Settings:** Vision `DetectRectanglesRequest` with `minimumAspectRatio 0.05`, `maximumAspectRatio 1`, `minimumSize 0.02`, `maximumObservations 50`.
- **Output:** boxes in top-left pixels; degenerate boxes are dropped.
- **Failures:** they return `[]`.

**`Snapper` constants:**
- threshold 6 screen points, converted at the current zoom;
- an edge snaps only to elements whose span beside the shape overlaps it;
- click-to-fit: a rectangle is the element outset by `stroke/2 + 2`; an ellipse is that rect × √2; a blur is exactly the element;
- the arrow head lands 2 px outside the nearest edge;
- the highlighter straightens when its height is under half its width and under 1.5 × thickness;
- holding ⌘ disables snapping.

### 2.11 Tests

- **Unit tests never touch real AX or Vision.**
- **`FakeAXTree` / `FakeAXElement` / `FakeAXApp`** (`Tests/CleanShotCopyTests/FakeAXTree.swift`):
  - text is laid out as a grid (`charWidth 7`, `lineHeight 14`), optionally wrapped (`wrap`) with no newline, like a web paragraph;
  - `answersRanges = false` models static text that ignores range calls;
  - `hiddenUntilSwitchedOn` models Chromium: the tree appears on the next capture after `AXManualAccessibility`;
  - `delay` makes every call sleep, like a hung app;
  - `calls` logs every call, to assert limits.
- **`FakeRectangles`** (`EditorSnapTargetsTests.swift`), `FakeTextReader`, `FakeFaces`.
- **Test files:**
  - CSCore: `SnapshotGeometryTests`, `ExactTextTests`;
  - app: `AXSnapshotterTests` (14 tests), `SnapshotWiringTests`, `EditorSnapshotSaveTests`, `EditorExactTextTests`, `ExactTextCopyTests`, `EditorSnapTargetsTests`, `EditorSnapMenuTests`;
  - CSEditor: `SnapperTests`.
- **Smoke tests (`CSC_INTEGRATION=1`):**
  - `aTextViewIsReadBackExactlyThroughAccessibility`:
    - opens an `NSTextView` window in the test process and reads it through real AX with `AXSnapshotter(ownPID: -1)`;
    - needs `AXIsProcessTrusted()` for the terminal;
    - must call `NSApplication.shared.finishLaunching()` first, because AppKit answers AX only once the app has launched;
    - polls `currentWindows()` until the new window appears;
    - it can fail when the screen is busy. Rerun it alone before calling it a regression.
  - `RectangleDetectorTests` has a Vision smoke test.

---

## 3. Gotchas and bugs we hit

Rows 1–7 have fix commits from the review pass or the user's manual pass. Rows 8–11 were handled while the feature was first written.

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | One hung app made OCR and every other `async` task stall; a snapshot could take ~6 s per element | (a) The walk's blocking AX calls ran on Swift's cooperative thread pool (only ~CPU-count threads), so a few blocked windows starved everything. (b) `AXUIElementSetMessagingTimeout` was set only on the app element; **child elements don't inherit it** and use the system default (~6 s). | `85dd156`: walk on a private concurrent `DispatchQueue` bridged with a continuation; set the 0.25 s timeout on **every** element returned (`LiveAXTree.timed`) |
| 2 | In window captures every box was shifted (exact text replaced the wrong pixels; snaps missed) | The window body was found along one middle row/column; a translucent toolbar or rounded corner moved an edge, and the aspect check (3 %) was too loose | `121c9d3`: three probes per edge must agree to 2 px, and the body height must match the window at the found scale to 2 px; otherwise **no snapshot** |
| 3 | A web paragraph cut by the selection pasted rows above and below; blur couldn't find words in it | A wrapped web value (one `AXValue`, several rows) was one line with one box spanning all rows. Line boxes also included trailing spaces. Scroll areas didn't clip, so scrolled-away content was read. Field values ran past their frame. Monaco's invisible 1×1 textarea produced lines. | `3dd6953`: wrapped values are read row by row (frame > 1.5 rows); line box = the trimmed text's own bounds; `AXScrollArea`/`AXWebArea` clip; a value is cut to its frame; text areas under 4×4 pt are skipped |
| 4 | "Name: Name: Morgan" in Copy Text; a line that had changed on screen came back from AX | An OCR line spanning an exact label and a non-covered field was kept or dropped as a whole by its centre. And AX is read slightly after the pixels are frozen, so the app may show something else by then. | `9e9c970`: OCR lines meeting a covered region are split into words; `agreeing` drops exact lines whose OCR differs by more than half (Levenshtein on letters/digits) and uncovers their rows |
| 5 | A filled box over text still let the text through ⇧⌘C; a blur over part of a web line removed the wrong words | Only blur annotations counted as redactions; per-character boxes of proportional web text are estimates, so word removal hit the wrong words | `c8972e6`: filled rectangles/ellipses count as redactions; non-monospaced lines touched by a redaction or cut by the crop are dropped and handed to OCR; monospaced lines keep word-level removal |
| 6 | After an editor save, Open Last Capture and ⇧⌘C showed the blurred or cropped text again; the next save wrote it back | Open Last Capture reused the coordinator's in-memory item with the **raw** snapshot; and a snapshot arriving late could overwrite the editor-saved file's xattr | `3281794`: the editor reads the snapshot from the **file** at open; an editor save updates the coordinator's last item; `savedByEditor` makes `attach` drop a late snapshot for a file an editor has saved over |
| 7 | On dense pages every rectangle edge jumped | Some element lines up with almost any x or y | `87b21c4`: an edge snaps only to elements whose span across it overlaps the shape (within the threshold) |
| 8 | First capture of VS Code, Cursor, Arc or Chrome has no exact text | Their AX tree is off until `AXManualAccessibility` is set; they build it asynchronously | By design: set it once per pid; the next capture reads it. Documented in the checklist. |
| 9 | AX smoke test read nothing | AppKit doesn't answer AX until `finishLaunching()`; the CG window list lags the window's appearance | Call `NSApplication.shared.finishLaunching()`; poll the window list |
| 10 | Off-by-n text cuts with emoji or accents | AX ranges are UTF-16 offsets | Always measure with `NSString.length`, never `String.count` |
| 11 | Snapshot lost after Save As or an editor save | Atomic file replacement drops xattrs | Copy back on every rewrite path (§2.2), as with M7's provenance |

---

## 4. Known open issues (from `docs/backlog.md`)

### M9 notes
- **App names after a crop:** the notification's "exact text from" names every app in the snapshot, even when a crop removed all of one app's lines. Record the app on each `SnapshotLine`.
- **Still OCR only:** M8's find and sensitive-data sweep, and the editor's Live Text selection, still read OCR only.

### M9 review minors
- **Edge search on the main actor:** `PendingSnapshot.windowCapture` draws the whole image on the main actor before `finish`, tens of ms before the thumbnail on a 2× window. Do it in the snapshot task.
- **Chromium zero-size wrappers:** these prune their visible children (`!frame.intersects(clip)` is true for an empty frame), so that text falls back to OCR. Prune only non-empty frames.
- **Gutter numbers:** a monospaced row never takes OCR pieces from the same row, so gutter line numbers beside an exact text-area row come out as their own line. This matters once VS Code gives exact text.
- **VS Code side effect:** `AXManualAccessibility` may switch VS Code into "Screen Reader Optimized" mode when `editor.accessibilitySupport` is `auto`. If seen, word the Settings note accordingly.
- **Tracking areas:** `EditorCanvasView.updateTrackingAreas` removes every tracking area on the view, not only its own.

### M10 note
- **Late snapshot and the index:** a snapshot that arrives after a capture was indexed doesn't trigger a re-read. That capture's index text stays OCR-only until it is re-indexed.

---

## 5. Do it better next time

1. **Put the walker in the portable core.** `AXSnapshotter`'s logic depends only on `AXTreeReading`, `CGRect` and Foundation. Move it, with `SnapshotGeometry`, `UISnapshot`, `ExactText`, `TextLayout`, `Snapper` and `SnapTargets`, into the core, and keep only `LiveAXTree` (the `AXReader` port adapter) in the macOS shell. Then nearly all of M9's logic and all its bug classes (§3 rows 3–7, 10) are testable on Linux with `FakeAXTree`. See `13-rebuild-strategy-agentic-ci-and-claude.md`.

   | Piece | Where |
   |---|---|
   | `UISnapshot` model and a versioned JSON codec | core |
   | `SnapshotGeometry`, `ExactText` (merge, agreeing, edited, exported, summary), `TextLayout` | core |
   | Tree walk: limits, clipping, cutting, bisection, Electron decision, window matching | core, over the `AXReader` port, with an injected clock for the deadline |
   | `AXUIElement…` calls, the messaging timeout, `NSRunningApplication` bundle lookup | shell (`LiveAXTree`) |
   | Window-body detection (`WindowShadow.body`) | core, on a `PixelBuffer` |
   | Vision rectangles, Vision OCR | shell, behind `RectangleFinder` / `TextReader` |
   | xattr read/write | shell, behind `FileMetadataStore`; the core decides *what* to write and when to copy back |
   | Pending-read lifecycle (start, attach, drop if the editor saved, wait ≤1 s for ⇧⌘7) | core state machine with a fake clock |

2. **Encode the snapshot in an explicit, versioned format.**
   - Add `version: 1` and encode rects as `{x,y,w,h}` yourself.
   - Don't rely on Apple's `CGRect` Codable shape (`[[x,y],[w,h]]`). swift-corelibs-foundation may not match it, and files written on macOS must decode in Linux tests.
   - Ignore unknown versions.
3. **Run blocking system calls off the cooperative pool from day one.**
   - Do this for every port whose macOS adapter blocks: AX, AppleScript or `NSAppleEventDescriptor` (M7), and the `SCShareableContent` waits.
   - Use a dedicated queue and a continuation, with a per-call timeout set on **every** element.
   - Write this rule into `11-…` and into the port's doc comment.
4. **Give each line its provenance:** the app, the element role, and whether it was cut or wrapped. That fixes the notification's app list, lets the merge treat web lines and terminal lines differently without guessing, and supports per-app policies.
5. **Feed exact text into find, the sweep, Live Text and the index.** One "best text map" service should produce a `TextMap` (words with boxes) from `ExactText.merge` plus OCR, and every consumer should read it. Monospaced exact lines give exact word boxes; for proportional text, ask AX for word bounds (`AXBoundsForRange` per word, within the budget) instead of estimating 1/n.
6. **Snapshot timing:** start the AX read *before* the selection overlay closes, or at least on the same runloop turn as the frozen pixels. Then `agreeing` rarely has to drop lines. Keep `agreeing` as the safety net.
7. **Keep the "no snapshot is better than a shifted one" rule** for window captures, and log when it triggers. Better still, ask ScreenCaptureKit for the window's content rect, or capture without the shadow, so no pixel guessing is needed.
8. **Prune only non-empty frames** in the walk. Chromium wraps visible content in zero-size groups.
9. **Re-index when a late snapshot lands** (M10 note), and re-run the badge or sweep if it uses exact text.
10. **Privacy with Claude features** (`13-…` §5): the AX snapshot stays local and is never sent wholesale. If a Claude feature needs a capture's text, send the merged text **after** the sensitive sweep has redacted it (see `07-…` §5). Secure fields are already never read. Keep the rule that the snapshot holds only what is inside the capture.
11. **Test fixtures:** the rebuild's fixture app (`13-…` §3) should include:
    - a monospaced text view with a stack trace;
    - a wrapped-paragraph web view;
    - a secure field;
    - a translucent-toolbar window;
    - a window partly covered by another.

    That replaces the busy-screen-dependent AX smoke test.
