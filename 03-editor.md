# 03 — The annotation editor

Covers M2 (the editor), the editor half of M6 part 4 (Live Text selection, editor backlog fixes), the editor side of M8 (find bar, Highlight/Box/Blur all, the editor's sweep bar), the editor side of M9 (snapping to UI elements, exact text in Copy Text and saves), M7/M10 hooks (source chip, Copy for AI, Find Similar) and M11's collection-image mode.

Sources: `Sources/CSEditor/*` (editor files, not the `Collection*` ones), `Sources/CleanShotCopy/Editor/*`, `Sources/CleanShotCopy/MainMenu.swift`, `Sources/CleanShotCopy/Collections/DocumentWindows.swift`; spec §6 of `docs/superpowers/specs/2026-10-16-cleanshot-copy-design.md`, `2026-10-21-backlog-design.md` §2 and §4.2, `2026-10-22-find-and-sweep-design.md` §3, `2026-10-23-ax-snapshot-design.md` §4; plans m2, m6d, m8, m9; checklists m2 and m6-backlog; `docs/backlog.md`; git history.

---

## 1. What it does

### 1.1 Opening

- **Ways in:** Quick Access **Edit** button, a double-click on a screenshot thumbnail, menu bar **Open Last Capture**, Find Capture / Spotlight results (screenshots only). Recordings open the trim window instead (see `04-recording-and-media.md`), GIFs the default viewer, collections their own window.
- **One editor per capture.** Opening a capture that already has an editor brings that window forward (matched by `CaptureItem.id`).
- **The Quick Access thumbnail stays** while its capture is open in an editor: its dismiss timer is paused (`QuickAccessController.setEditing`) and resumes when the editor closes.
- **A missing or unreadable file** opens nothing and posts "Couldn't open capture" / "<name> is missing or unreadable."
- **Dock icon and main menu** appear while any editor (or collection window) is open; Bugeye is otherwise a menu-bar-only (`.accessory`) app. `DocumentWindows` counts open document windows: `.regular` at 1, `.accessory` back at 0.
- **Window:** titled with the file name, resizable, min 640 × 420, no tabs. It is sized to the canvas + 40 pt (+ chrome height), capped at 85 % of the main screen's visible frame, centred, then zoomed to fit.

### 1.2 Layout

Top to bottom: toolbar (40 pt) · divider · find bar (34 pt, when open) · sweep bar (34 pt, when showing) · canvas (scroll view) · divider · options strip (36 pt).

**Toolbar**, left to right: 11 tool buttons (SF Symbols, tooltip "Arrow (A)" etc.), a divider, **Frame** (popover), spacer, Undo, Redo, **Copy Text**, **Copy for AI**, **Copy**, **Save**, the drag handle (`hand.draw` symbol, "Drag the edited image into another app"), and the source chip (M7).

### 1.3 Tools and keys

Plain letter keys on the canvas switch tools (no modifier). They are ignored while a text field or the find field has focus.

| Key | Tool | SF Symbol | Behaviour |
|---|---|---|---|
| V | Select | `cursorarrow` | Click selects (dashed outline + handles); drag moves; handles resize; Delete/Backspace deletes; double-click a text annotation re-edits it. Also the Live Text tool (§1.8). |
| C | Crop | `crop` | Drag a crop rect. The canvas shows the whole image (no frame) with the outside dimmed 50 % black and a 1 pt white border. Options strip shows "W × H px" or "Drag to crop", plus **Reset Crop**. Non-destructive until export. |
| A | Arrow | `arrow.up.right` | Drag tail → head. ⇧ snaps to 45°. |
| R | Rectangle | `rectangle` | Drag. ⇧ makes a square. Outline or **Filled**. |
| O | Ellipse | `circle` | Drag. ⇧ makes a circle. Outline or Filled. |
| L | Line | `line.diagonal` | Drag. ⇧ snaps to 45°. |
| T | Text | `textformat` | Click places a text field; click on an existing text annotation re-edits it. |
| P | Pen | `pencil.tip` | Freehand polyline. |
| H | Highlighter | `highlighter` | Freehand, 3× stroke width, 40 % opacity, overlapping strokes of one annotation don't darken. |
| B | Blur / Pixelate | `square.grid.3x3` | Drag a rect. Mode Pixelate / Blur, strength Light / Medium / Strong. Never has a shadow. |
| N | Numbered step | `1.circle` | Click adds a filled circle with the next number. |

Default tool on open: **Arrow** (`InteractionController.tool = .arrow`).

Other canvas keys: **Esc** deselects, clears the Live Text selection, closes the find bar and takes the keyboard back from VisionKit; **Backspace (51) / forward Delete (117)** delete the selected annotation.

**Text entry:** the field uses bold system font at the chosen size in the chosen colour. **Return** commits, **Option-Return** inserts a newline (`usesSingleLineMode = false`), **Esc** cancels, a click anywhere else on the canvas commits and does nothing else. Any toolbar/options action, undo, save, copy or tool change commits the text first. Empty or whitespace-only text is discarded; emptying an existing text annotation deletes it. While typing, ⌘Z / ⇧⌘Z undo the typing (the field editor's undo manager), not the document.

**Degenerate input:** a click with a shape tool (extent < 3 image px) creates nothing; a shape entirely in the frame padding or outside the crop is dropped; a blur is clamped to the visible area. Text and steps can only be placed inside the visible area.

### 1.4 Options strip

Shows the options of the current tool, or of the selected annotation's tool in Select mode. Changing an option while an annotation is selected restyles it (one undo step, even for a continuous colour-panel drag).

| Option | Tools | Values |
|---|---|---|
| Colour | all but Select, Crop, Blur | 6 swatches: red (1, .23, .19), orange (1, .58, 0), yellow (1, .8, 0), green (.2, .78, .35), blue (0, .48, 1), black; plus a `ColorPicker` (no opacity). Default red. |
| Width | Arrow, Rect, Ellipse, Line, Pen, Highlighter, Step | Thin 2 pt / Medium 4 pt / Thick 8 pt. Default Medium. |
| Filled | Rect, Ellipse | checkbox, default off |
| Shadow | Arrow, Rect, Ellipse, Line, Pen, Text, Step | checkbox, default off |
| Size | Text | 16 / 24 / 36 / 48 pt, default 24 |
| Mode, Strength | Blur | Pixelate / Blur (default Pixelate); Light 1 / Medium 2 / Strong 3 (default 2) |
| (Crop) | Crop | size label, Reset Crop |
| (Select) | Select | "Click an annotation to select it · drag to move · Delete removes it" |

Selecting an annotation loads its style into the strip first, so a later restyle can't silently reset its fill (bug fixed in `dbadb7c`).

### 1.5 Background frame

The **Frame** popover: "Background frame" toggle, then (when on) six fill swatches, **Padding** slider 0–160 pt, **Corner radius** slider 0–32 pt, **Shadow** toggle.

- Defaults when turned on: padding 48 pt, gradient 0, radius 10 pt, shadow on. Off by default.
- Fills: 4 diagonal gradients (top-left → bottom-right) plus solid white and solid black:
  - indigo (.39,.40,.95) → pink (.93,.36,.70)
  - orange (1,.62,.27) → coral (.96,.31,.45)
  - teal (.20,.80,.75) → blue (.16,.42,.90)
  - graphite (.30,.32,.36) → near-black (.08,.08,.10)
- The image (with its annotations) is clipped to a rounded rect inside the padding; the frame shadow follows the content's alpha, so a transparent window capture casts a correct shadow.
- One slider drag is one undo step; a run of keyboard steps on a slider is also one step (`e68db00`).

### 1.6 Undo, zoom

- **Undo / Redo:** ⌘Z / ⇧⌘Z, the toolbar buttons and Edit menu. Every drag (draw, move, resize, crop, slider) is exactly one step; a click that changes nothing makes no step; a new edit clears redo. Up to 200 steps.
- **Zoom:** View → Zoom In ⌘= (×1.25), Zoom Out ⌘− (÷1.25), Actual Size ⌘1, Zoom to Fit ⌘0 (never above 100 %, 20 pt margin), plus pinch and two-finger double-tap (smart magnify). Range 10 %–800 %. A canvas smaller than the viewport is centred (`CenteringClipView`).
- Handles, selection outlines, find/sweep outlines and hit areas keep a constant size on screen at any zoom.

### 1.7 Output

| Command | Key | What happens |
|---|---|---|
| Copy | ⌘C, toolbar | The flattened render as PNG on the clipboard. With a Live Text selection, ⌘C copies the selected text instead (the toolbar button always copies the image). |
| Copy Text | ⇧⌘C, toolbar | OCR of the flattened render, merged with the capture's Accessibility snapshot (exact text, M9). Notification "Text copied" + summary, or "No text found in the image" / "The clipboard wasn't changed.", or "Couldn't read text". |
| Copy for AI | ⌥⇧⌘C, toolbar | The render + a text block (see `06-provenance-and-clipboard.md`). Nothing is saved. |
| Copy as Markdown | Edit menu | Saves like ⌘S first; a temp capture is then moved into the save folder; then copies `![…](path)`. "Markdown link copied". |
| Save | ⌘S, toolbar | Overwrites the capture file atomically with the flattened render; the Quick Access preview refreshes; the capture is re-indexed under the same ID. |
| Save As… | ⇧⌘S | Writes a flattened copy elsewhere (PNG); the editor keeps tracking the original and stays dirty. Not indexed. |
| Drag handle | — | Drops a rendered PNG named like the capture (temp folder `Bugeye-Drag/`). |
| Open Source | File menu, chip | Opens the capture's source (M7). |
| Find Similar | File menu | Enabled once the capture is indexed (M10). |

**Saving a moved or deleted capture:** alert "The original file is gone" / "“<name>” was moved or deleted since it was opened." with **Save As…** and **Cancel**; Save As then makes the editor track the new file (`911ead3`).

**Unsaved changes:** closing asks "Save changes to “<name>”?" / "Your annotations will be lost if you don't save them." with **Save**, **Don't Save**, **Cancel**. ⌘Q asks the same for every dirty editor in turn; Cancel keeps the app running. The window's close button shows the edited dot (`isDocumentEdited`).

### 1.8 Live Text selection (M6 part 4)

- With the **Select** tool, hovering text shows the I-beam; drag selects words; double-click a word; triple-click a line; right-click gives the system menu (Copy, Look Up, Translate…). VisionKit's own "Live Text" corner button is hidden.
- **Annotations come first:** a click on an annotation or on the selected annotation's handles selects/moves/resizes it as before; double-clicking a text annotation still edits it.
- Other tools draw normally; the text layer is hidden for them.
- The text is read from the **flattened render** when the editor opens and again 0.5 s after the last document change, so a blurred word stops being selectable.
- Tool change, Esc or a new reading clears the selection. No text or a failed read: nothing visible, no notification.

### 1.9 Find (⌘F) and the sweep bar (M8, editor side)

- **Edit → Find…** (⌘F) opens a dark "night" bar under the toolbar: search field (placeholder "Find"; Match case in its menu), the message or count ("3 of 12"), ‹ (⇧Return) and › (Return), **Highlight all**, **Box all**, **Blur all**, ✕ (Esc). Both directions wrap. The canvas scrolls the current match into view (24 pt margin).
- Messages: "Reading…" before the first reading; "No text found in this image"; "No matches".
- Matching: case-insensitive by default, always diacritic-insensitive, never across lines; a match inside a word gets a proportional slice of the word box.
- Outlines: 1.5 screen-pt yellow (`NightChrome.accent`) around every match; the current one also filled at 25 %. Overlay only, never exported.
- Actions: every match becomes an annotation, all added as **one undo step**, then the bar closes:
  - Highlight all: a highlighter stroke through the box's middle in the current colour/width; a box taller than the stroke gets back-and-forth passes so it is covered.
  - Box all: a rectangle 3 px larger on every side, current colour/width/shadow.
  - Blur all: a blur 3 px larger on every side, current mode/strength, clamped to the crop.
- **Sweep bar** (amber, dashed outlines): "N items look possibly sensitive" with **Blur all**, **Review** (then **Blur** / **Skip** per finding) and **Ignore**. Details in `07-sensitive-sweep-and-find.md`.

### 1.10 Snapping to UI (M9, editor side)

- Rectangles, ellipses and blurs snap their edges to the captured UI elements while drawn or resized, within **6 screen points**. Only the edges a handle moves snap.
- A **click without dragging** on an element fits the shape to it: rectangle = element outset by strokeWidth/2 + 2 px; ellipse = that rect scaled √2 about its centre (the ellipse through its corners); blur = the element.
- **Arrow heads** snap to the nearest edge of the smallest element under the head, 2 px outside it.
- **Highlighter strokes** that are mostly horizontal over a text line straighten into a band along the line, ends snapped to word edges.
- Hovering with Rectangle/Ellipse/Blur/Arrow outlines the element a click would fit (1 pt dashed accent). Holding **⌘** disables snapping for that event; **Edit → Snap to Elements** toggles it for all editors and is stored in Settings → Text & snapping.
- ⇧ (square / 45°) wins over snapping. Targets outside the crop are ignored. Annotations never snap to other annotations.

### 1.11 Collection-image mode (M11)

A collection's image block opens in the same editor on a temp PNG copy (`isCollectionImage = true`): no Save As, no Copy as Markdown, no Open Source, no Find Similar, no sweep bar. ⌘S hands the new render and the editor state back to the collection; it never touches Quick Access or the index. Closing without saving changes nothing.

---

## 2. How it's built

### 2.1 Targets and files

| Target | File | Role |
|---|---|---|
| CSEditor (Swift 6, pure) | `Model.swift` | `RGBA`, `StrokeWidth`, `BlurMode`, `Style`, `AnnotationShape`, `Annotation`, `BackgroundFrame`, `EditorState`, `EditorGeometry` |
| | `EditorDocument.swift` | state, snapshot undo, dirty flag, step numbering, `addAll` |
| | `EditorTool.swift` | tools, keys, `ToolOptions`, `EditorShortcuts` |
| | `AnnotationGeometry.swift` | handles, bounds, hit testing, translate, resize, `StepBadge` |
| | `InteractionController.swift` | mouse → document edits, drafts, crop, text commit, restyle coalescing, snapping |
| | `CanvasLayout.swift` | canvas size, image origin, content rect |
| | `EditorRenderer.swift`, `AnnotationPainter.swift`, `FramePainter.swift`, `BlurCache.swift`, `TextLayout.swift` | Core Graphics / Core Text / Core Image drawing |
| | `EditorExporter.swift` | render, PNG, save, save copy, drag file |
| | `LiveTextGate.swift`, `FindAction.swift`, `Snapper.swift` | pure rules for M6d, M8, M9 |
| App (Swift 5) | `Editor/EditorManager.swift` | one editor per capture, wiring, quit prompt, snap setting fan-out |
| | `Editor/EditorWindowController.swift` | window, output, save, find, sweep, snapping targets, Copy Text |
| | `Editor/EditorCanvasView.swift` | AppKit canvas: drawing via the renderer, mouse/keys, text field, overlays |
| | `Editor/EditorViewModel.swift`, `Editor/EditorChrome.swift` | SwiftUI toolbar / options / frame popover bridge |
| | `Editor/LiveTextController.swift` | `LiveTextEngine` protocol, debounced reads, `VisionKitLiveText` |
| | `Editor/FindModel.swift`, `FindBar.swift`, `EditorTextReader.swift`, `SweepModel.swift`, `EditorSnapTargets.swift`, `CenteringClipView.swift` | |
| | `MainMenu.swift`, `Collections/DocumentWindows.swift` | menus, activation policy |

### 2.2 Coordinates and units

- **Annotations are stored in image pixels, top-left origin, y down.** Sizes (stroke width, font size, padding, corner radius, badge diameter) are in **points** and multiplied by the capture's `pixelsPerPoint` (`ppp`, `max(1, item.pixelsPerPoint)`).
- Every `CGContext` the renderer draws into gets a y-down user space (`translateBy(0, h); scaleBy(1, -1)`). `CGContext.draw(image)` assumes y-up, so images go through `ImageDrawing.drawFlipped`. Core Text lays out y-up, so `TextLayout.draw` flips locally.
- **Canvas view** is flipped (`isFlipped = true`); view units are points (`canvas pixels / ppp`); the scroll view's `magnification` does the zoom. Image point = `layout.imagePoint(fromCanvas: viewPoint × ppp)`.
- `CanvasLayout(imageSize:state:pixelsPerPoint:showingFullImage:)`:
  - export / normal: `visible = crop ?? whole image`, `pad = round(frame.padding × ppp)`, size = visible + 2·pad, `contentRect = (pad, pad, visible)`, `imageOrigin = (pad − visible.minX, pad − visible.minY)`.
  - crop tool: `showingFullImage = true` → the whole image, no frame.

### 2.3 Model

```swift
enum AnnotationShape {
  case arrow(from:, to:), line(from:, to:)
  case rectangle(CGRect, filled: Bool), ellipse(CGRect, filled: Bool)
  case text(origin: CGPoint, string: String, fontSize: CGFloat)   // fontSize in points
  case pen([CGPoint]), highlighter([CGPoint])
  case blur(CGRect, mode: BlurMode, strength: Int)                 // 1...3
  case step(center: CGPoint, number: Int)
}
struct Annotation { let id: UUID; var shape; var style: Style }   // Style = color RGBA, width, shadow
struct EditorState { var annotations: [Annotation]; var crop: CGRect?; var frame: BackgroundFrame? }
struct BackgroundFrame { padding = 48; fill = .gradient(0) | .solid(RGBA); cornerRadius = 10; shadow = true }
```

- `AnnotationShape.minimumExtent = 3` image px: below it a shape isn't "meaningful" and isn't added.
- `EditorGeometry.clampedCrop` rounds to whole pixels, intersects the image, and rejects < 3 px.
- Step numbers are stored on the annotation; `nextStepNumber = max(existing) + 1` (so undoing the last step and clicking reuses its number). Collections compute numbers instead (see `10`).

### 2.4 Document and undo

`EditorDocument` (final class, not `@MainActor`, pure):

- `state` is a small value type; undo keeps **whole-state snapshots** (`undoStack: [EditorState]`, limit 200).
- `beginChange()` remembers the state (only if no change is open); `update { }` mutates and calls `onChange`; `endChange()` pushes the remembered state **only if it differs**, and clears redo. `apply { }` = begin + update + end. A drag is begin on mouse-down, update per move, end on mouse-up → one step.
- `canUndo` is also true while an open change differs from its start (so the Undo button enables during a keyboard slider run); `undo()` closes any open change first.
- `isDirty = state != savedState`; `markSaved()` after a save.
- `addAll(_:)` adds many annotations as one step (Find's and the sweep's "… all").

### 2.5 InteractionController

Pure; the canvas converts events to image pixels and forwards them.

- `Drag` cases: `.drawing(start)`, `.moving(id, last)`, `.resizing(original, handle, grabOffset)`, `.cropping(start)`.
- **Hit areas in screen points**, converted to image pixels on every zoom change: `handleSize = 8`, `minimumHitDistance = 6`, `snapDistance = 6`; `tolerance_px = value × ppp / zoom`. `zoom` is set by the canvas from the scroll view's magnification.
- **Select mouse-down:** handle of the selected annotation → resize (keeps the grab offset, so a click on a handle doesn't jump the edge); else topmost hit (reverse z-order) → select (loading its options) and begin a move; double-click on text → `.beginTextEntry`; else deselect.
- **Hit testing** (`Annotation.hitTest`): lines/arrows by distance to the segment; rect/ellipse outline as a ring of ±tolerance (filled = inside); pen/highlighter by distance to any segment; text, blur, step by bounds. Tolerance = max(strokeWidth/2, minTolerance).
- **Handles:** 8 for rect/ellipse/blur, `start`/`end` for line/arrow, none for pen, highlighter, text and step (those can only move).
- **Drafts:** a shape tool creates a `draft` annotation drawn live; on mouse-up it is click-fitted (§1.10), straightened (highlighter), clamped to the visible rect (blur clamped; others dropped if their bounds miss it), and added if meaningful.
- **Text:** returns `.beginTextEntry(origin, editing)`; `commitText` adds, replaces (keeping the font size), or removes when empty. The annotation being re-edited is hidden (`hiddenID`) while its field is up.
- **Restyle coalescing:** `applyOptionsToSelection` opens one change per annotation (`restylingID`) and keeps updating it, so a colour-panel drag is one undo step; any other action calls `finishPendingChanges()`.
- **Frame edits:** `beginFrameChange` / `setFrame` / `endFrameChange`. An unbracketed `setFrame` (keyboard slider steps) opens a change that the next edit closes.
- `displayState` = document state − hidden + draft + draft crop: what the canvas draws.
- `activeID`: the annotation being drawn, moved or resized, for the live-drawing optimisation.

### 2.6 Rendering

`EditorRenderer` draws **both the export and the canvas**, so what you see is what you save.

- `render(image:state:ppp)` → `CGImage` of `CanvasLayout(showingFullImage: false)`; bitmap: 8-bit RGBA premultiplied-last, in the capture's colour space if it is RGB, else sRGB.
- **Without a frame:** clip to `contentRect`, draw the image, then every annotation translated by `imageOrigin`.
- **With a frame:** draw the background (solid fill, or a linear gradient from (0,0) to the far corner, extended both ends); set the frame shadow (offset (0, −6 ppp), blur 20 ppp, 40 % black) scaled by `deviceScale`; open an **unbounded transparency layer** (so the shadow outside the content isn't clipped); clip to the rounded content path (radius = min(cornerRadius × ppp, half the short side)); draw the content.
- **Per annotation** (`AnnotationPainter`): optional shadow (offset (0, −2 ppp), blur 6 ppp, 45 % black; never for highlighter or blur), highlighter alpha 0.4, then **one transparency layer per annotation** over its bounds + 16 ppp. The layer makes overlapping highlighter segments one even wash, and casts a shape's shadow once.
  - Strokes: round caps and joins.
  - Arrow: head length = min(length, max(width × 3.5, 12 ppp)), half-width 0.45 × head; the shaft stops 0.3 × head inside the head so there's no gap.
  - Text: `CTFontCreateUIFontForLanguage(.emphasizedSystem, size × ppp)` (fallback Helvetica-Bold), framesetter suggested size + 1 px each way; drawn with its top-left at `origin`.
  - Step: filled circle of diameter 22 / 28 / 36 pt (thin / medium / thick), number at 0.55 × diameter, black on light colours and white on dark (`0.299r + 0.587g + 0.114b > 0.6`).
- **Blur** (`BlurCache`): crops the **original capture** (not annotations below it) to the integral rect, runs Core Image on `clampedToExtent()` (so edges don't fade), crops back:
  - pixelate: `CIFilter.pixellate()`, `scale = strength × 6 × ppp`, `center = .zero`;
  - blur: `CIFilter.gaussianBlur()`, `radius = strength × 5 × ppp`.
  - One shared `CIContext(options: [.cacheIntermediates: false])`; results cached by (rect, mode, strength, ppp), cache cleared past 64 entries.
- **`CGContext.deviceScale`** = √|det(CTM to device)|. `setShadow` offset and blur are in device space and ignore the CTM, so both shadows are multiplied by it. It is 1 in every export bitmap, so goldens don't change.

### 2.7 The canvas (`EditorCanvasView`)

- `refresh()` resizes the view to `layout.size / ppp`, keeps the Live Text view covering `bounds` (hidden unless Select), redraws, invalidates cursor rects (arrow / I-beam / crosshair) and syncs the view model.
- **Draw:** everything except the active annotation is rendered once into a cached bitmap (keyed by state + layout; `baseRenderCount` is a test hook); the active annotation is drawn live on top. Before this, every mouse move on a 5K capture with a frame re-rendered everything (~180 ms) (`645eecd`).
- **Overlays** (never exported), all at fixed screen width: find outlines (yellow), sweep outlines (amber dashed), crop dimming, snap outline (1 pt dashed accent), selection outline (1 pt dashed 4/3, outset 2 pt) and white handle squares of 8 screen pt.
- **Keys:** the canvas is first responder, so it gets `undo:`, `redo:`, `copy:`, `delete:` before the window. `keyDown` maps via `EditorShortcuts.action(keyCode:characters:hasModifiers:)`.
- **Text field:** an `NSTextField` subview positioned at `origin` minus **2 pt** (the field editor's line-fragment padding), so committed text stays where it was typed (`33d2852`). `controlTextDidEndEditing` commits; `cancelOperation:` cancels.
- **Zoom tracking:** `scrollView.contentView.postsBoundsChangedNotifications = true` and the controller observes `boundsDidChangeNotification`; every zoom, including smart magnify, changes the clip view's bounds synchronously, so `canvas.magnification` (and the hit tolerances) are always current (`c1db340`).
- Hover: one tracking area (`mouseMoved`, `activeInKeyWindow`, `inVisibleRect`); `flagsChanged` re-checks the outline when ⌘ is pressed or released.

### 2.8 Window controller, manager, menus

- `EditorWindowController(item:clipboard:liveTextEngine:textReader:faceDetector:rectangleDetector:)` returns nil when the PNG can't be read. All services are injected (fakes in tests).
- Init loads the capture's provenance and (for screenshots) its UI snapshot **from the file's xattrs**, not from the item (fixes `0e58d59`, `3281794`).
- The first Live Text read, the sweep and rectangle detection start in **`showWindow`**, not `init`: tests build editors they never show and must not call VisionKit or Vision.
- **Save path:** `EditorExporter.save` writes `.atomic` → that drops extended attributes, so after every write the controller re-writes the provenance (`ProvenanceStore.write`), the transformed snapshot (`UISnapshotStore.write(exportedSnapshot)`) and the capture ID (`CaptureIdentity.assign`). Save As copies get provenance and snapshot but a new ID.
- `windowWillClose` nils `editorDocument.onChange`, cancels Live Text and text reading, calls `onClose`.
- `EditorManager` keeps `openEditors`, forwards callbacks with `[weak self]`, increments/decrements `DocumentWindows`, pushes the snap setting to every editor, and implements `shouldTerminate()` (asks each dirty editor; `confirmClose` is injectable for tests).
- **Main menu** (`MainMenu.install`), visible only while a document window is open: Bugeye (Quit ⌘Q); File (Save ⌘S, Save As… ⇧⌘S, Export… ⌘E for collections, Open Source, Find Similar, Close ⌘W); Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut, Copy ⌘C, Copy Text ⇧⌘C, Copy for AI ⌥⇧⌘C, Copy as Markdown, Paste, Delete, Select All, Find… ⌘F, Snap to Elements); View (Zoom In ⌘=, Zoom Out ⌘−, Actual Size ⌘1, Zoom to Fit ⌘0). Standard actions use string selectors and go to the first responder. `validateMenuItem` disables Save As / Copy as Markdown / Open Source / Find Similar in collection-image mode and shows Snap's checkmark.
- **SwiftUI chrome:** `EditorRootView` hosts the toolbar, bars, canvas (`NSViewHost` wraps the scroll view) and options strip. View state lives in `EditorViewModel: ObservableObject` with `@Published` (the CLT has no `@State` macro plugin; even `showingFramePopover` lives there). `beforeAction` commits text before any chrome action.

### 2.9 Live Text

- `protocol LiveTextEngine: AnyObject` (`@MainActor`): `view`, `shouldBegin`, `read(_ image:) async throws`, `clear()`, `hasSelection`, `selectedText`, `clearSelection()`. Unit tests use a fake; the app uses `VisionKitLiveText`.
- `VisionKitLiveText` owns `ImageAnalyzer` and `ImageAnalysisOverlayView`:
  - `preferredInteractionTypes = .textSelection`; `setSupplementaryInterfaceHidden(true, animated: false)` at init **and after every new analysis** (the corner button otherwise reappears).
  - `analyze(image, orientation: .up, configuration: .init([.text]))`, then `try Task.checkCancellation()` before assigning `overlay.analysis`.
  - Delegate `overlayView(_:shouldBeginAt:forAnalysisType:)` converts the point to the canvas and asks `LiveTextGate.allowsTextInteraction(tool:hitsAnnotation:isTyping:)` (Select tool, no annotation or handle hit, no text being typed). `hitsAnnotationOrHandle(at:)` mirrors `mouseDown`'s select branch so they can't disagree.
  - `overlayView(_:shouldHandleKeyDownEvent:)` returns false, so tool letters, Esc and Delete reach the canvas.
- **Geometry:** the overlay is a subview of the canvas (the scroll view's document view) with frame = `canvas.bounds` and the default `contentsRect` (0,0,1,1). Zoom and scroll move it for free. This only works because in Select mode the canvas *is* the export render (crop + frame); in Crop mode it isn't, which is one reason the overlay is hidden for non-Select tools (the other: its cursor rects would beat the tools' cursors). Added `positioned: .below` so the text field sits above it.
- `LiveTextController`: `start()` reads now; `documentChanged()` calls `engine.clear()` at once (a blurred word must stop being selectable immediately) and reads again after **0.5 s** (`debounce`); each schedule cancels the previous task. `sleep` is injected for tests. Read failures are swallowed by design.
- VisionKit links with the Command Line Tools through autolinking; `import VisionKit` needs no Package.swift change.

### 2.10 Find and reading the edit

- `EditorTextReader` renders the flattened edit (the same render as Copy Text), runs `TextRecognizing.readMap(image, pixelsPerPoint:)` and, when the sweep wants faces, `FaceDetecting.faces(in:)` concurrently, then shifts all boxes by `−layout.imageOrigin` into **document image pixels**. A generation counter drops stale results; a new read cancels the old one.
  - `readNow()` (editor opening with the sweep on), `readIfNeeded()` (find opening; skips if current or in flight), `documentChanged()` (re-read after 0.5 s only while find is open or the sweep is on, else just mark stale).
- `FindModel` (`ObservableObject`): `query`, `matchCase`, `map`, `matches` (document pixels, reading order), `current`. `update(map)` keeps the current index; a query change resets to 0. `command(_:shift:)` handles Return / ⇧Return / Esc from the field.
- `FindField` is an AppKit `NSSearchField` (so it takes focus from the canvas and letter keys type), `sendsSearchStringImmediately`, dark appearance, Match case in `searchMenuTemplate` (rebuilt to show the checkmark). `FocusingSearchField` takes first responder in `viewDidMoveToWindow`, because SwiftUI inserts the bar on its next update.
- `FindAction.annotations(for:options:pixelsPerPoint:)` is pure; padding 3 px; highlight path passes = ⌈box height / stroke width⌉, alternating direction.

### 2.11 Snapping data

- `SnapTargets.from(snapshot:detected:ocr:)`: elements = the capture's Accessibility snapshot elements, else `RectangleDetector` (Vision) results, run once off the main thread only when the snapshot has no elements; lines = snapshot lines (word boxes estimated as each character's equal share of the line width), else OCR lines from the latest `EditorTextReader` reading. With the Highlighter chosen and no lines yet, the editor triggers a reading.
- `Snapper.snap(rect, edges:, to:, threshold:)`: each moving edge snaps to the nearest matching edge within the threshold, **considering only elements beside the shape** (their span across that edge overlaps the shape's, ± threshold). `fitted` is set only when all four edges hit the same element.
- `InteractionController.movingEdges(handle, from:, to:)` picks the edges a handle drags, flipping when dragged past the opposite edge.
- Highlighter straightening requires: ≥ 2 points, height < width/2 and < 1.5 × thickness, a line whose box contains the stroke's mid-y and overlaps it horizontally.

### 2.12 Exact text in the editor (M9)

- `editedSnapshot` = `ExactText.edited(snapshot, crop:, blurs:)` where "blurs" = blur rects **and filled rectangles/ellipses** (both hide text). Copy Text merges it with OCR of the render (`ExactText.merge`).
- `exportedSnapshot` = `ExactText.exported(…, origin: layout.imageOrigin, scale: 1)`: what a save writes onto the file, so the saved file's snapshot matches its pixels. The editor itself keeps the original snapshot (its document is still the original image).

---

## 3. Gotchas and bugs we hit

| Symptom | Root cause | Fix | Commit |
|---|---|---|---|
| A thumbnail's preview, drag-out and Quit flow broke around editing (M2 final review #1–#4, #6, #10) | Several lifecycle gaps: ⌘Z while typing undid the document; ⌘Q quit with unsaved edits; the Quick Access thumbnail auto-dismissed while its capture was being edited; with auto-save off, Quick Access Save moved the file and the editor kept saving to the old temp path; toolbar actions didn't commit typed text; hovering a thumbnail made its panel key and stole keys from the editor | Field editor's undo manager while typing; `shouldTerminate` loop; `setEditing` pauses the timer; `EditorManager.itemChanged` re-points the editor; `beforeAction` commits text; Quick Access remembers and restores the previous key window | `a77bc5a` |
| Restyling via the colour panel made dozens of undo steps; restyling reset a shape's fill; a click on a handle jumped the edge to the mouse; shapes drawn in the frame padding were kept invisibly | No coalescing; options weren't loaded on selection; no grab offset; no visibility clamp | `restylingID` coalescing; load options on select; `grabOffset`; `clampedToVisible` | `dbadb7c` |
| Drawing/moving lagged on a 5K capture with a frame (~180 ms per mouse move) | Every redraw rendered the frame, shadows and all annotations | Cache the base render; draw only the active annotation live | `645eecd` |
| At 25 % zoom thin lines were hard to click; handles grew and shrank with zoom | Hit distance and handle size were in view points | Constants in screen points, converted with `ppp / zoom` | `8244b67`, `c1db340` |
| After a two-finger double-tap zoom, handle hit areas were wrong until the next menu zoom | Smart magnify animates `magnification` without `didEndLiveMagnifyNotification` | Observe the clip view's `boundsDidChange` (fires on every zoom) | `c1db340` |
| The live (dragged) annotation's shadow was ~3× too big when zoomed out | `CGContext.setShadow` uses device space and ignores the CTM; the cached base is 1:1 so looked right, the live layer was drawn into the zoomed view context | Multiply shadow offset/blur by `deviceScale` | `27eebe8` |
| Committed text jumped 2 pt left | The field editor draws the first glyph after a 2 pt line-fragment padding | Place the field 2 pt left of `origin` | `33d2852` |
| ⌘S on a capture moved or deleted in Finder silently recreated it | Atomic write to a missing path just creates the file | Check existence; alert with Save As… / Cancel | `911ead3` |
| A run of keyboard steps on a frame slider made no undo step, so the next ⌘Z also reverted the previous edit | SwiftUI may not send `onEditingChanged` for key steps; an unbracketed `update` records nothing | Unbracketed `setFrame` opens a change closed by the next edit; `canUndo` counts an open change | `e68db00` |
| After a Live Text selection, ⌘C / ⌘Z / Delete / letter keys stopped reaching the canvas | VisionKit's overlay takes first responder during a selection | Esc makes the canvas first responder again; overlay delegate refuses key events | `c597d68` |
| Editor Copy Text on 1× captures missed small text | The capture's scale wasn't passed, so 1× text wasn't enlarged before Vision | Pass `pixelsPerPoint`; `readMap` enlarges 1× images 2× | `c597d68` |
| The source chip was empty for captures reopened later | The editor used the item's in-memory provenance only | Read provenance stored on the file (`withStoredProvenance`) | `0e58d59` |
| Open Last Capture after an editor save brought back blurred/cropped text on ⇧⌘C and the next save | The editor reused the capture's raw (pre-edit) snapshot from memory | Read the snapshot from the file's xattr; editor saves update the coordinator's last capture; a late snapshot after an editor save is dropped | `3281794` |
| Every rectangle edge jumped while drawing on a dense page | On a dense UI some element lines up with almost any x or y | Snap an edge only to elements beside the shape | `87b21c4` |
| The editor's sweep cleared or restored the Quick Access badge wrongly | Unsaved edits and early saves forwarded findings | Forward only a fresh reading of a saved (non-dirty) document | `441d197` |
| **Closed editor's canvas stays in memory** (open) | After typing in one editor while another editor window is open, closing the first keeps its `EditorCanvasView` alive, held by an observer block AppKit registers in `-[NSView _commonAwake]`. Outside Bugeye's code; reproduces on master; found by the leak test. The editor and window *are* freed. | Not fixed. The leak test checks the editor and window only, with a comment explaining why the canvas isn't checked. | `442baf2`, `e75de6d` |

Other lessons:

- **The CLT toolchain has no SwiftUI macro plugin**: no `@State`, `@Observable`. `@StateObject`, `@ObservedObject`, `@Published` and `@Environment` compile. Popover state therefore lives in the view model.
- **`VisionKitLiveText()` can't be a default argument** of a `@MainActor` init (default arguments are evaluated nonisolated); the init takes an optional and creates it inside.
- **Swift 6 mode in CSEditor:** no global or static `let`s of non-Sendable types (the shared `CIContext` is `nonisolated(unsafe) static`); create renderers locally in tests.
- **Leak tests** must poll (`for _ in 0..<30 { sleep 100 ms }`): AppKit frees closed windows lazily. Every closure in the window controller, manager and SwiftUI root captures `[weak self]`.
- **Never spin `RunLoop.main` synchronously in a test**; it stalls main-queue waits of other parallel tests.
- **Golden images:** `Tests/CSEditorTests/Golden/composite.png`, compared per pixel with a small tolerance; `CSC_RECORD_GOLDENS=1` rewrites them. Review Focus items that earned tests: y-flip orientation (a shape at the top-left lands top-left; blur samples the pixels under it, not a mirrored region), crop + frame + Retina sizes, undo granularity, degenerate input, save semantics.

---

## 4. Known open issues (from `docs/backlog.md`)

- The closed-editor canvas retention above.
- ⌘S clears the Live Text selection and re-reads the image although saving doesn't change it.
- VisionKit's I-beam and right-click menu may still appear over an annotation that sits on text; only selection start is gated.
- On a tall capture each settled edit renders the full image twice on the main thread (Live Text and find/sweep): ~0.35 s and 1.4 GB transient at 60,000 px. Share one render or render off-main.
- If the editor's render fails, find stays on "Reading…" (should deliver an empty reading).
- The sweep bar appearing a second after opening pushes the canvas down; `chromeHeight` ignores the bars.
- Every save re-reads the image, even with no change since the last reading.
- An open editor keeps the sweep kinds it opened with.
- Live Text, find and the sweep read OCR only; the snapshot's exact lines would make them exact.
- `EditorCanvasView.updateTrackingAreas` removes every tracking area on the view, not only its own.
- `updateItem` sets `viewModel.provenance = newItem.provenance` instead of the kept `item.provenance`.
- The drag-handle file carries no provenance record.
- Editor Save As copies aren't indexed.
- Collection mode: an editor save after its block was deleted is dropped silently.

---

## 5. Do it better next time

### 5.1 Portable core vs macOS shell

The first build already had the right instinct (pure `CSEditor` + thin AppKit canvas) but `CSEditor` draws with Core Graphics, Core Text and Core Image, so none of it runs on Linux. Split it this way:

| Portable core (Linux-tested) | macOS shell |
|---|---|
| Model: annotations, state, frame, tools, options, key map | `NSWindow`, scroll view, `NSTextField` text entry, SwiftUI chrome |
| `EditorDocument` (snapshot undo, coalescing, dirty) | Mouse/keyboard event conversion (view pts → image px) |
| `InteractionController` (all drag, select, crop, text commit, snapping logic) | Executing the display list with Core Graphics |
| Geometry: hit testing, handles, `CanvasLayout`, arrow-head maths, step badge maths, highlight paths | Blur/pixelate pixels via Core Image (or a core `PixelBuffer` implementation, see below) |
| **Display-list renderer**: state → `[DrawCommand]` | Text shaping and measuring (`TextMeasuring` port) |
| `Snapper`, `LiveTextGate`, `FindAction`, `FindModel`, `SweepModel`, view models | VisionKit Live Text, Vision OCR, rectangle and face detection (ports) |
| Exact-text transforms (`ExactText.edited/exported`) | xattrs, atomic file writes, pasteboard, `NSSavePanel`, alerts |

### 5.2 The display list is the centre of the editor

- **Define `DrawCommand`** in the core: `fillPath`, `strokePath(width, cap, join, dash)`, `image(id, rect)`, `textRun(string, font descriptor, color, origin)`, `blurRegion(rect, mode, strength, ppp)`, `pushLayer(alpha, shadow, bounds)` / `popLayer`, `clip(path)`, `linearGradient`. Render = `func displayList(for state: EditorState, layout: CanvasLayout) -> [DrawCommand]`.
- Make every unit explicit in the commands: **image pixels, y-down**. The shell does the one flip. This kills the y-flip bug class (Review Focus #1) at the type level.
- **Shadows and layers are commands**, with values in canvas pixels; the shell applies `deviceScale` once when executing into a zoomed context. That makes the `27eebe8` bug impossible to reintroduce in feature code.
- **Text needs measuring** for bounds, hit testing and step labels: put a `TextMeasuring` port in the core (fake = fixed advance per character) so layout is testable on Linux, and keep pixel-accurate goldens on macOS only.
- **Tests:** golden **JSON** snapshots of display lists on Linux (cheap, diffable, deterministic); a small set of pixel goldens on macOS (orientation, frame + shadow, blur sampling, highlighter overlap).
- **Blur:** sample the original image only (as now). Either keep Core Image in the shell behind a `BlurRenderer` port, or implement pixelate and a box/gaussian blur on `PixelBuffer` in the core (portable, testable, and pixelate is trivial). Clamp-to-extent semantics must match.
- **Cache by command list, not by state:** the canvas caches the rasterised base and draws only the active annotation's commands live. Keep that optimisation; it was the fix for 180 ms frames.

### 5.3 Behaviour to keep, designed in from day one

- Image-pixel storage with point-based sizes × ppp; `CanvasLayout` as the single source of geometry for canvas, export, OCR offsets, Live Text and collections (`editorShift`).
- Snapshot undo with begin/update/end and "no step if unchanged"; coalesce restyles and slider runs; a test per gesture asserting exactly one step.
- All on-screen constants (handles 8, hit 6, snap 6, outlines 1–1.5) in **screen points**, converted with `ppp / zoom`, and zoom observed from the clip view bounds.
- Live Text overlay = a subview of the canvas covering exactly the export render; hidden for non-Select tools; gate in the core.
- Every write path that replaces a file restores xattrs (provenance, snapshot, ID). Better: one `CaptureFileWriter` in the shell that writes atomically **and** re-applies all metadata, so no feature can forget one (this bug class recurred in M7, M9, M10).
- Read per-capture metadata (provenance, snapshot) from the file at open, never from a possibly stale in-memory item.

### 5.4 Fix what stayed open

- One render per settled edit, shared by Live Text, find and the sweep, produced off the main thread (the core display list makes off-main rendering easy: execute it into a bitmap context on a background queue).
- Feed find, the sweep and Live Text from the merged exact text (snapshot + OCR), not OCR alone.
- Read sweep kinds per scan; deliver an empty reading on render failure; don't re-read after a save with no changes.
- Reserve space for the find/sweep bars so the canvas doesn't jump.
- Avoid the canvas retention: don't add/remove `NSTextField` subviews per text entry; keep one reusable field (or a lightweight custom text view) owned by the canvas and hidden when unused, and keep a leak test that covers the canvas too.
- Text entry: render the in-progress text through the same display list (draw it live, edit a model string) instead of overlaying an AppKit field; that removes the 2 pt inset hack and keeps WYSIWYG exact.
- Make step numbers computed (as collections do) or renumber on delete, so numbering can't get gaps.

### 5.5 Claude (optional, opt-in)

The editor is a natural host for API features listed in `13` (e.g. suggesting what to blur, captioning). Route them through the core's `LLMClient` port, send the **flattened, already-redacted render** (never the original pixels when the user blurred something), and keep every result as ordinary annotations added in one undo step, like Find's "… all".
