# 10: Collections and the Guide Recorder (M11)

> **Superseded in part (Nov 2026):** the user wants collections exported as designed presentations and the guide recorder to produce a zoomed, captioned video. See `14-direction-changes-and-agentic-proposals.md` R5 and R6.

M11 adds one new kind of document, the **collection**: an ordered page of image blocks and text blocks, saved as a reopenable `.bugeye` package and exported as an image, a PDF, Markdown or HTML. Two features fill it:
- **Collections (RD-25):** combine captures, with text between them, into one editable document ("annotated screen, explanation, next screen").
- **Guide recorder (RD-18):** ⇧⌘9 records a how-to. Each click becomes a numbered step: the screen just before the click, a marker on the click point, and a caption read from the clicked element ("Click **Save**").

RD-21 (re-editable captures) was **dropped** by the user ("overkill, only for myself"). Image blocks are plain images; annotating one goes through the existing editor, whose ⌘S flattens. Step markers are never burned in: the collection stores them and draws them at display and export time.

Sources: spec `docs/superpowers/specs/2026-10-27-collections-design.md` (approved, `8eef60a`), plan `docs/superpowers/plans/2026-10-27-m11-collections.md` (`65ff9ba`, 25 tasks), checklist `docs/manual-checklist-m11-collections.md`, branch `feat/m11-collections` (37 commits, about 1,047 tests green). **Status when written:** executed and review-fixed (3 Critical + 8 Important fixed), waiting for the user's manual pass; not merged to `master`.

---

## 1. What it does

### 1.1 Ways in

| Way | Result |
|---|---|
| Menu bar **New Collection** | a new window with one heading block "Untitled"; title `Collection YYYY-MM-DD at HH.MM.SS`; not dirty (closing asks nothing) |
| Quick Access ⇧-click 2+ thumbnails → **Combine (N)** | a new dirty collection, one image block per capture, **oldest at the top**, with provenance and scale; files stay put; thumbnails stay in Quick Access; selection clears |
| Drag and drop into an open collection | PNG/JPEG/HEIC/TIFF files (Finder, Quick Access thumbnails), or raw PNG/TIFF data (an image dragged from a browser), inserted at the drop line; anything else shows no drop line |
| Toolbar **Add Capture…** | Find Capture in pick mode (screenshots only, ⌘-click multi-select, Return adds); inserted below the last selected block, else at the end |
| ⇧⌘9 / menu bar **Record Guide** | records a guide, opens it as an unsaved collection on Done |
| Finder double-click / `open` | `.bugeye` packages open in Bugeye |
| Menu bar **Open Recent ▸** | last 10 packages, missing ones pruned when the menu opens |
| Find Capture / Spotlight | collections are indexed; Return / continuation opens them |

Menu bar order (M11): Capture Area, Capture Scrolling Area, Capture Text, Capture Window, Capture Fullscreen, Record Screen, **Record Guide** (shows ⇧⌘9), separator, Open Last Capture, Find Capture…, Duplicates…, **New Collection**, **Open Recent ▸**, separator, Settings…, Quit Bugeye.

### 1.2 The collection window

- Normal titled, resizable window: default 760 × 900, min 520 × 400, tabbing disabled. Title = the package's file name (or the default name before the first save).
- While any editor or collection window is open, Bugeye is a regular app (Dock icon, main menu, ⌘Tab) via `DocumentWindows`.
- **Toolbar** (night gradient, 44 pt): title field (renames the collection's `title`, commits on Return only) · **+ Text ▾** (Heading / Paragraph / Caption, inserted after the last selected block, else at the end) · **Add Capture…** · **Frame ▾** (None, Indigo, Orange, Teal, Graphite, White, Black: fills only) · **Export ▾** (disabled when there are no blocks).
- **Read-only** (a package with a newer `version`): edit controls disabled; notice bar "Made by a newer Bugeye: read-only."; Export and Copy still work; Save / Save As disabled.
- **The page:** one view-based `NSTableView` column, content width at most 900 pt, centred with insets (top 16, bottom 40). Rows:

| Row | Look and behaviour |
|---|---|
| Heading | inline `NSTextView`, 20 pt bold |
| Paragraph | 14 pt, wraps; Return = newline |
| Caption | 13 pt, with "n." drawn beside it (not editable) |
| Image | stored image cropped, framed, markers drawn (the editor's red step badge); never above 1:1 in points; 28 pt left inset for the grip |
| Missing image | grey rounded box "Image missing", 4:3 at column width; selectable and deletable |
| Between rows | on hover: a grip `⋮⋮` on the left and a thin line with "+" in the 10 pt gap under the row; clicking "+" inserts an empty paragraph below and focuses it |

- **Keys and mouse:**

| Input | Effect |
|---|---|
| Return in a heading or caption | focus the next text block, or insert a paragraph after this block |
| ⌘↩ | insert a paragraph below |
| Esc in text | end the edit (focus goes to the table) |
| click / ⌘-click / ⇧-click a row | table selection |
| drag a row | reorder (drop above a row) |
| ⌫ / ⌦ with rows selected (not editing text) | delete the blocks |
| ⌥-click an image | add a marker |
| drag a marker (> 2 pt) | move it |
| click a marker, then ⌫ | remove it |
| double-click an image (not on a marker) | open it in the editor |
| **C** (no ⌘⌃⌥) with an image selected | crop mode: the whole unframed image fitted in the row; drag a rectangle; Return/Enter applies; Esc cancels; ⌘R resets the crop |
| ⌘S / ⇧⌘S | Save / Save As… |
| ⌘E | Export again in the last format (first time: Image (Vertical)) |
| ⇧⌘C | Copy Image (vertical PNG); the Edit menu item is retitled "Copy Image" (the editor renames it back to "Copy Text") |
| ⌘Z / ⇧⌘Z | document undo / redo |
| ⌘W | close; asks if dirty |

- **Closing / quitting with changes:** "Save changes to “<name>”?" / "Your changes will be lost if you don't save them." with Save / Don't Save / Cancel. An empty, never-saved collection closes without asking. Open image editors on this collection close first, each asking for its own unsaved changes.

### 1.3 Step numbering (the rule users see)

- Each **caption** block is a step, numbered 1, 2, 3… in block order. Shown and exported as `"n. " + text`.
- An image's **markers** take the number of the nearest caption above it since the previous image block. An image with markers and no such caption gets the next number of its own. All markers of one image share its number.
- Headings, paragraphs and images without markers have no number.
- Numbers are never stored: moving, inserting or deleting renumbers on the next read.

### 1.4 Editing an image block

- Double-click opens the regular editor on a **temp copy** of the block's PNG (at the block's scale). The editor is in "collection image" mode: Save As…, Copy as Markdown, Open Source and Find Similar are disabled; no sensitive-data bar; its ⌘S touches neither Quick Access nor the index.
- On each editor ⌘S the collection stores the flattened PNG as a new `images/<uuid>.png`, shifts markers by where the old image's (0, 0) landed (crop origin and frame padding), drops markers now outside, resets the block's crop, and marks itself dirty. The original screenshot in the save folder is untouched.
- Closing the editor without saving changes nothing. Double-clicking again while its editor is open fronts that editor.

### 1.5 Export

| Format (Export ▾ title) | Output |
|---|---|
| Image (Vertical) | one PNG: blocks top to bottom, 24 pt gaps, 40 pt margin, column = widest rendered image (600 pt if no image); text at column width |
| Image (Horizontal) | one PNG: each image with the text blocks since the previous image above it, wrapped at that image's width; left to right, top-aligned; trailing text is its own 600 pt column |
| Image (Grid) | one PNG: 2 columns as wide as the widest image; captions held and drawn under their image; a heading or paragraph spans both columns and starts a new row; leftover captions as full rows at the end |
| PDF | A4 595 × 842 pt, 40 pt margins, selectable Core Text text; pagination in §2.6 |
| Markdown | `<Name>.md` + folder `<Name> images/NN.png` (01, 02… in block order) |
| HTML | one `<Name>.html`, images inline as base64 PNG, built-in stylesheet, dark mode via `prefers-color-scheme` |
| Copy Image (⇧⌘C) | the vertical PNG on the clipboard |

- Save panel defaults to `<save folder>/Collections/` and `<window name>.<ext>`.
- Every image block is drawn the same way in every format: the stored PNG, cropped, markers drawn as step badges, framed with the collection's frame.
- Text: heading 28 pt bold, paragraph and caption 18 pt; `**…**` runs bold with the asterisks hidden (image, PDF, HTML, the window). Text colour: black with no frame, white on a gradient frame, a contrasting colour on a solid frame.
- Scale: images keep their own pixel scale; text is drawn at the largest image's `pixelsPerPoint` rounded and clamped to 1…2.
- A single image export whose long side exceeds 16,000 px is scaled down; notification "Exported <file>" / "Scaled down to fit 16,000 px."
- Failure: alert "Couldn't export" with the reason; nothing left behind.
- Exports and Copy run off the main thread.

### 1.6 The guide recorder

- **Start:** ⇧⌘9 (`HotkeyManager.Action.recordGuide = 8`, `kVK_ANSI_9`) or menu bar Record Guide. ⇧⌘9 again, or **Done**, ends it. The "macOS screenshot shortcuts are still on" notice also names ⇧⌘9.
- **Blocked** while a recording, a scrolling capture or a screenshot is busy (`HotkeyRoute`); the menu item is disabled then. ⇧⌘9 during a guide always routes to Done.
- **Permissions:** Screen Recording (`CGPreflightScreenCaptureAccess`) and Accessibility (`AXIsProcessTrusted`) both required. Otherwise alert "Record Guide needs Screen Recording and Accessibility." with **Open Setup** (opens Settings → Setup) and **Cancel**; nothing starts.
- **The guide bar:** night, non-activating, floating panel at the bottom centre (24 pt above the visible frame's bottom) of the display under the mouse: `● Guide · N steps` (singular "step") · **Window | Display** (segmented; remembered in `guide.mode`; applies to the next step) · **Undo Step** (disabled at 0) · **Pause** / **Resume** · **Done**. At 100 steps the status reads "100 steps: press Done" in the accent colour and further steps are ignored. Clicks on the bar never become steps (global monitors don't see Bugeye's own windows) and the bar is excluded from the frames.
- **A step per mouse-down** (left or right), while recording and not paused:
  1. the frame from just before the click;
  2. cropped to the clicked window (Window mode, default) or the whole display (Display mode);
  3. a caption block, then an image block with one marker at the click point.
- **Double-click:** a second left mouse-down within 0.4 s and 4 pt of the previous step's click, on the same element, rewrites that step's caption ("Double-click **x**") and adds no step.
- **Typing:** keys without ⌘ or ⌃ after a click step mark it once: caption + ", then type". The typed text is never read into the model, the draft, the index or anywhere else. Typing before the first click, or after a shortcut step, is ignored.
- **Shortcuts:** a key with ⌘ or ⌃ adds a text-only step "Press **⌘S**" (modifier glyphs in ⌃⌥⇧⌘ order, then the key). The same shortcut repeated within 1 s is merged. ⌥ alone is not a shortcut (AZERTY/German layouts type `[ ] { } | ~` with ⌥).
- **Pause:** clicks and keys ignored until Resume; streams keep running. **Undo Step:** removes the last step's caption, image block and file.
- **Done:** stops monitors and streams, waits for pending writes, opens the draft as an **unsaved** collection titled `Guide YYYY-MM-DD at HH.MM.SS`, first block a heading **"Guide: <app of the first click step>"**. 0 steps: the draft is deleted and nothing opens. First ⌘S saves into `Collections/` and deletes the draft; Don't Save deletes the draft.
- **Stream failure** (display unplugged, permission revoked): input stops at once, the draft so far opens (if it has steps), notification "Guide stopped: <reason>."
- **Quit during a guide:** the guide ends and opens (steps kept) and that quit is cancelled.
- **Drafts:** `~/Library/Caches/Bugeye/Drafts/<Guide …>.bugeye/`; at launch, entries modified more than 7 days ago are deleted (detached utility task).

**Caption wording** (`StepCaption`):

| Element (left click) | Caption |
|---|---|
| button, pop-up button, link, cell, row, disclosure triangle, slider, text field, text area, combo box, anything else with a label | Click **label** |
| menu item, menu bar item | Choose **label** |
| checkbox, value 0 when read / value 1 | Check **label** / Uncheck **label** |
| radio button | Select **label** |
| tab (`AXTab`, or `AXRadioButton` with subrole `AXTabButton`) | Open the **label** tab |
| right-click on a labelled element | Right-click **label** |
| double-click on a labelled element | Double-click **label** |
| no element or no label | Click in **App** / Right-click in **App** / Double-click in **App** |
| after typing | "<caption>, then type" (once) |
| ⌘/⌃ shortcut | Press **⌘S** |

App falls back to "the app" when it can't be read.

---

## 2. How it's built

### 2.1 Code map

| Target | Files | Role |
|---|---|---|
| CSEditor | `CaptureCollection.swift` | model, `stepNumbers()`, `displayText(of:numbers:)`, `index(of:)` |
| CSEditor | `CaptureCollection+Edit.swift` | edits, `imageReplaced`, `editorShift` |
| CSEditor | `CollectionDocument.swift` | undo/redo, typing steps, images, dirty, read-only, save |
| CSEditor | `CollectionPackage.swift` | `.bugeye` read/write |
| CSEditor | `CollectionLayout.swift`, `CollectionText.swift`, `CollectionExporter.swift`, `CollectionExporter+Documents.swift` | export maths, Core Text, PNG/PDF/Markdown/HTML, atomic write |
| CSEditor | `Model.swift` | `RGBA`, `BackgroundFrame`, `Fill` gained `Codable` |
| CSCore | `DocumentText.swift` | `InlineBold`, `MarkdownEscape`, `HTMLEscape` |
| CSCore | `StepCaption.swift`, `GuideStepBuilder.swift`, `GuideFrames.swift`, `FrameRing.swift`, `GuideSettings.swift` | pure guide logic |
| CSCore | `QuickAccessSelection.swift`, `DismissTimer.restart`, `CaptureKind.collection` | |
| CSCapture | `GuideFrameBuffer.swift` | SCStream per display |
| App `Collections/` | `CollectionManager`, `CollectionWindowController`, `CollectionPageView`, `CollectionRowViews`, `CollectionToolbar`, `CollectionExport`, `DocumentWindows`, `RecentCollections` | |
| App `Guide/` | `GuideSession`, `GuideRecorder`, `GuideBar`, `GuideInputMonitor`, `StepElementReader`, `LiveAXPoint` | |
| App | `QuickAccessController`/`ThumbnailView` (selection, Combine), `FindCaptureModel`/`FindCapturePanel` (pick mode, collection glyph), `Indexer` (collections), `EditorManager.openCollectionImage`, `EditorWindowController.isCollectionImage`, `HotkeyManager`/`HotkeyRoute`, `MenuBarController`, `MainMenu` (Export… ⌘E), `AppDelegate`, `Resources/Info.plist` | |

**Naming:** the spec's `Collection` / `Block` are `CaptureCollection` / `CollectionBlock` in code. A public `Collection` in CSEditor would shadow Swift's `Collection` protocol in every importing file.

### 2.2 The model (CSEditor, pure, `Codable, Equatable, Sendable`)

```swift
public struct CaptureCollection { static let currentVersion = 1
    var version: Int; var title: String
    var frame: BackgroundFrame?          // shared by every image block; nil = "None"
    var blocks: [CollectionBlock] }
public struct CollectionBlock: Identifiable { var id: UUID; var content: Content
    enum Content { case text(TextBlock), image(ImageBlock) } }
public struct TextBlock { enum Style: String { case heading, paragraph, caption }; var style: Style; var text: String }
public struct ImageBlock {
    var file: String                     // "images/<UUID>.png", relative to the package
    var pixelSize: CGSize                // of the stored image
    var pixelsPerPoint: CGFloat          // capture's scale; a guide step's display scale
    var crop: CGRect?                    // image pixels, top-left origin; nil = whole
    var markers: [StepMarker]            // StepMarker { var point: CGPoint } image pixels, top-left
    var source: CaptureProvenance? }     // the M7 record
```

`BackgroundFrame` = `padding` (pt, default 48), `fill` (`.gradient(Int)` / `.solid(RGBA)`, default `.gradient(0)`), `cornerRadius` (10), `shadow` (true). The toolbar only changes `fill` (`BackgroundFrame.fillChoices` = 4 gradients + white + black).

`stepNumbers()` walks the blocks with a counter `n` and a `pending` number: a caption does `n += 1`, records `n`, sets `pending = n`; an image with markers takes `pending` or else `n += 1`; every image block resets `pending = nil`.

**Edits** (`CaptureCollection+Edit.swift`), each one undo step in the document:
- `insert(_:at:)`: index clamped to `0...count`.
- `move(ids:to:)`: `index` is a position in the current array; the moved blocks land before the first **unmoved** block at or after it (the anchor), keeping their relative order; no anchor → end. This is what makes `NSTableView` drop rows (`.above`) behave.
- `remove(ids:)`, `setText`, `setStyle`.
- `setCrop(_:for:) -> Bool`: standardized, intersected with the image, `.integral`; refused (no change, `false`) when null or under 8 × 8 px; nil clears.
- `addMarker`, `moveMarker`, `removeMarker`: points clamped to the image.
- `imageReplaced(id:file:newSize:shift:)`: markers `+ shift`, those outside the new bounds dropped, new file and size, crop reset.
- `editorShift(imageSize:state:pixelsPerPoint:)` = `CanvasLayout(imageSize:state:pixelsPerPoint:showingFullImage: false).imageOrigin`: where the original (0, 0) lands in the editor's flattened export (minus the crop origin, plus frame padding × scale).

### 2.3 `CollectionDocument` (CSEditor, a final class)

- State: `collection`, `packageURL` (nil until saved), `imageURLs: [String: URL]` (block file → where the PNG is now: draft, scratch, editor save), `isReadOnly`, `onChange`, undo/redo stacks of whole `CaptureCollection` snapshots, `savedState`, `typingStart`.
- `isDirty` = `savedState != collection`. `startsDirty: true` (Combine, guides) sets `savedState = nil`.
- `apply { }`: mutate a copy; if unchanged, nothing; else push the old snapshot, clear redo, `onChange`. No-op when read-only.
- **Typing steps:** `beginTyping()` remembers the state; `type { }` mutates without an undo entry (the view shows it already); `endTyping()` pushes one undo step if anything changed. The window's `documentChanged` returns early while typing so a reload doesn't end the edit. The text view's own undo handles in-edit typing; at end of editing the row calls `undoManager?.removeAllActions(withTarget: textStorage)` so the typing becomes one document step.
- `undo()` ends typing first.
- `addImage(at:url, pixelSize:, pixelsPerPoint:, source:, markers:, at:)` creates `images/<UUID>.png`, maps it to `url`, inserts.
- `replaceImage(id, with:url, size:, shift:)` new file name + `imageReplaced`.
- `imageURL(for:)`: `imageURLs[file]`, else the file in the package if it exists, else nil (= "Image missing").
- `save(to:)`: end typing → `keepUndoImages()` → `CollectionPackage.write(collection, images: imageURLs, to: url, from: packageURL)` → `packageURL = url`, `imageURLs = kept`, `savedState = collection`.
- **`keepUndoImages()`:** files referenced only by undo/redo states would not be copied into the new package (unreferenced files are dropped), so an undo after a save would show "Image missing". Each such file is kept: a scratch/draft file outside any `.bugeye/` is kept where it is; a file inside a package is copied to `$TMPDIR/Bugeye-collection-undo/<UUID>.png`.

### 2.4 The `.bugeye` package

```
<Name>.bugeye/
  collection.json        CaptureCollection, JSONEncoder [.prettyPrinted, .sortedKeys]
  images/<UUID>.png      one per image block: unframed, uncropped, no markers
```

Example `collection.json` (Swift's synthesized `Codable`: enums with associated values encode as `{"case": {"_0": …}}`; `CGPoint`/`CGSize` as `[x, y]`/`[w, h]`; `CGRect` as `[[x, y], [w, h]]`; nil optionals omitted; `/` escaped as `\/`):

```json
{
  "blocks" : [
    { "content" : { "text" : { "_0" : { "style" : "heading", "text" : "Guide: Safari" } } },
      "id" : "11111111-1111-1111-1111-111111111111" },
    { "content" : { "text" : { "_0" : { "style" : "caption", "text" : "Click **Save**" } } },
      "id" : "22222222-2222-2222-2222-222222222222" },
    { "content" : { "image" : { "_0" : {
          "crop" : [ [ 0, 40 ], [ 2400, 1500 ] ],
          "file" : "images\/4F1C0D2E-0000-0000-0000-000000000000.png",
          "markers" : [ { "point" : [ 812, 640 ] } ],
          "pixelSize" : [ 2400, 1600 ],
          "pixelsPerPoint" : 2,
          "source" : { "...": "the M7 CaptureProvenance, when known" } } } },
      "id" : "33333333-3333-3333-3333-333333333333" }
  ],
  "frame" : { "cornerRadius" : 10, "fill" : { "gradient" : { "_0" : 0 } }, "padding" : 48, "shadow" : true },
  "title" : "Guide 2026-10-27 at 14.02.11",
  "version" : 1
}
```

- **Location:** `<save folder>/Collections/` (default `~/Pictures/Bugeye/Collections/`), created on first save.
- **UTI** (`Resources/Info.plist`): exported type `dev.msenechal.bugeye.collection`, description "Bugeye Collection", conforms to `com.apple.package` and `public.composite-content`, extension `bugeye`. Document type: role Editor, `LSHandlerRank` Owner, `LSTypeIsPackage` true. Finder shows one file; double-click opens Bugeye. Save panel uses `UTType(filenameExtension: "bugeye", conformingTo: .package)`.
- **Read:** `readAny(url)` decodes any version (errors: `.unreadable(reason)`, "The collection's document is damaged." for bad JSON). `read(url)` also throws `.newerVersion(v)` above `currentVersion`. `CollectionDocument.open` uses `readAny` and sets `isReadOnly = version > currentVersion`. Missing image files are not errors.
- **Write (atomic):** build a complete package in a hidden temp sibling `.<Name>.bugeye.tmp-<UUID>` (same folder, so same volume), copying each block's image from `images[file]`, else from the package at `from` (the document's own package: needed for Save As), else the package already at `url`. Missing sources are skipped (they show "Image missing"). `collection.json` written `.atomic`. Then `FileManager.replaceItemAt(url, withItemAt: temp)` if the destination exists, else `moveItem`. On error the temp is removed and the old package is intact. Images no block references are not copied, so a save drops them.
- **ID xattr:** the package folder carries `dev.msenechal.bugeye.id` (search identity, M10). `replaceItemAt` swaps the folder, which **drops its xattrs**, so `CollectionManager.write` reads the ID before saving and re-assigns it after (new UUID on first save).
- **Names:** `FileNamer.baseName(prefix:date:)`: `Collection YYYY-MM-DD at HH.MM.SS`, `Guide YYYY-MM-DD at HH.MM.SS`. Renaming the title never renames the file.

### 2.5 Layout, text and image export (CSEditor)

- `CollectionExporter.renderImage(block, number:, frame:, source:, renderer:)`: builds an `EditorState` with `crop`, `frame` and one `.step(center:number:)` annotation per marker (red, width `.medium`; none when the block has no number) and renders it with the editor's `EditorRenderer` at `max(1, pixelsPerPoint)`. Same path for the window rows, so the window and exports match the editor.
- `CollectionLayout.page(items, layout:, scale:, measure:) -> PageLayout` (pure maths: margin 40 pt, gap 24 pt, text-only width 600 pt, all × scale). Images arrive at page scale: `k = pageScale / image.pixelsPerPoint`.
- `CollectionText`: `CTFontCreateUIFontForLanguage(.system / .emphasizedSystem)`; height via `CTFramesetterSuggestFrameSizeWithConstraints` (+1, ceiled); draw by flipping into Core Text's y-up space. `InlineBold.parse` splits on `**`; an odd marker count keeps the last `**` literal.
- `renderPage`: an sRGB RGBA8 `CGContext`, flipped to y-down, scaled by `k = min(1, 16000 / longSide)`; background = `FramePainter.drawBackground` with a full-page `CanvasLayout`, else white; then images and texts at their placements. Returns `(image, scaledDown)`.
- Missing images are left out of image exports.

### 2.6 PDF, Markdown, HTML, writing

**PDF** (`pdfData`): `CGContext(consumer:mediaBox:)`, A4, y-down per page.
- `CollectionLayout.pdfPages(blocks)`: each image block ends a page, with the text since the previous image above it; a heading starts a new page; trailing text is a page of its own.
- **Text flows across pages** (`c9d701f`): `CTFramesetterSuggestFrameSizeWithConstraints` with the remaining height returns the fitting range; draw it, advance, start a new page and continue with the rest. If not even one line fits an empty page, stop.
- **Images:** natural size = pixels / ppp, scaled to the text width (`k0`). If that doesn't fit the space left **and** the space left is under one third of the usable page height **and** something is already on the page, start a new page; then scale to fit what's left (`c9d701f`). Before the fix an image could be squeezed into a sliver at the bottom.
- Blocks are separated by 12 pt.

**Markdown** (`markdown(_:imagesFolder:)`):
- heading: `# ` when it is the **first block**, else `## `; caption: `**n.** ` + text; paragraph as is; blocks joined by a blank line, final newline.
- image: `![Step n](<<Name> images/NN.png>)` (angle brackets because the folder name has spaces), alt `Image NN` without a step.
- Text goes through `MarkdownEscape.inline`: `**` runs stay bold (`**…**`), everything else escaped: `\ ` `` ` `` `* _ [ ] < > |` backslashed; a line starting with `#`, `-`, `+` gets a leading `\`; `12. ` style ordered-list starts get `\.`.
- Missing image: the link is replaced by `*Image missing*`.
- Writes `<Name>.md` and the `<Name> images/` folder.

**HTML** (`html(_:png:)`): `<!doctype html>`, `charset utf-8`, viewport, `<title>` escaped; first block heading → `<h1>`, other headings `<h2>`; caption `<p class="step"><b>n.</b> …</p>`; paragraph `<p>`; images `<img src="data:image/png;base64,…" alt="Step n">` (alt "Image"); missing → `<p class="missing">Image missing</p>`. Text escaped with `HTMLEscape` (`& < > " '`), `**` runs as `<b>`. Inline CSS: system font 16/1.5, `max-width: 860px`, images `max-width:100%`, dark colours under `@media (prefers-color-scheme: dark)`. Works offline.

**Write** (`CollectionExporter.write(format, of:, to:, load:) -> Bool scaledDown`): throws `.nothingToExport` for an empty collection; renders into a hidden `.export-<UUID>` folder next to the destination; then moves each output (`replaceItemAt` if it exists); the temp folder is always removed (`defer`). Throws `.renderFailed` if the page can't be drawn.

**Off the main thread** (`a507583`): the window passes a snapshot of the collection and a `[file: URL]` map to a `Task.detached(priority: .userInitiated)`, which decodes each image with ImageIO inside the task.

### 2.7 The window (app)

- `CollectionWindowController` owns the `CollectionDocument`, a per-window scratch folder `$TMPDIR/Bugeye-collection-<UUID>/` (dropped images, conversions, editor saves; deleted in `windowWillClose`), the page, the toolbar model, and `editors: [UUID: EditorWindowController]`.
- **Image cache** (`a507583`): decoded `CGImage`s keyed by URL, LRU, at most 24 (a 100-step 5K guide must not hold every frame). Row heights are computed from the model (`pixelSize`, crop, frame), never by decoding.
- **Inserting images:** `imageInfo(url)` reads width, height, DPI (`kCGImagePropertyDPIWidth`, default 72 → `ppp = max(1, round(dpi/72))`) and type without decoding. PNGs are **copied byte for byte** into scratch; other formats decoded and re-encoded as PNG. A capture's known scale and provenance override the file's (Combine, Add Capture…).
- `CollectionPageView` (an `NSScrollView` with a `CollectionTableView`): one column sized to `min(contentWidth, 900)`, centred via `contentInsets`; `reload()` recomputes numbers and keeps the selection by ID. Rows are recreated on every reload (no reuse).
- **Drag and drop:** rows write their block UUID under the private type `dev.msenechal.bugeye.block`; `registerForDraggedTypes([block, .fileURL, .png, .tiff])`; drops forced to `.above`; internal → `.move` (`moveBlocks`), files/images → `.copy`; refused when read-only or nothing readable.
- `ImageRowView` (flipped): `placement` uses `CanvasLayout` to map image pixels ↔ view points (`viewPoint`, `imagePoint`), marker hit radius = badge radius at the current scale, at least 8 pt. Crop mode draws the uncropped, unframed source fitted in the row height, a 45 % black even-odd mask outside the draft rectangle and a white outline.
- `CollectionRowView` (`NSTableRowView`) draws the hover grip and "+" line and handles the "+" click (clicks on a cell's empty parts bubble up to it).
- **Editor round trip:** `CollectionManager.editImage` writes the decoded block to `scratch/edit-<UUID>.png` and calls `EditorManager.openCollectionImage(url, pixelsPerPoint:, onSaved:, onClosed:)`. The editor reports `(CGImage, EditorState)` per save. The window keeps, per block, the size of the image the editor opened and the shift of its previous save; each save's markers move by the **difference** since the previous save, because the editor keeps editing the image it opened with (`imageEdited`).
- `validateMenuItem` renames `editorCopyText:` to "Copy Image" and disables export/copy for empty collections and Save for read-only.

### 2.8 `CollectionManager` (app)

- One window per package: `open(url)` fronts an existing window whose `packageURL` matches (standardized path).
- `newEmpty()`, `newFrom(items:)` (inserts with `at: 0` and an incrementing index, so the given order is kept; closes and returns nil if no image was readable), `open(_:)`, `openDraft(_:name:)` (reads with `read`, maps every image to the draft package, `startsDirty`, remembers `draftURL`).
- Save: read-only → no; first save runs an `NSSavePanel` in `Collections/` named `<name>.bugeye`; later saves overwrite in place; Save As always asks. After a successful write: re-assign the ID xattr, rename the window, delete the draft, add to recents, `onSaved(url)` → `indexer.add(CaptureItem(id: xattr ID, kind: .collection, createdAt: Date()))`. A failure shows "Couldn't save collection" with the error; the document stays dirty and the old package is intact.
- Open failure: notification "Couldn't open collection" / "<file name>: <reason>".
- `shouldTerminate()`: each dirty window is fronted and asks; Cancel stops the quit. `AppDelegate.applicationShouldTerminate` checks `guide.shouldTerminate()`, `editors.shouldTerminate()`, `collections.shouldTerminate()` in that order.
- `RecentCollections`: `UserDefaults` key `collections.recent`, last 10 paths, newest first; `existing()` prunes missing ones.
- `cleanDrafts(in:olderThan: 7 days)` by content modification date.
- Finder opening: `AppDelegate.application(_:open:)` filters `.bugeye` URLs. AppKit can call it **before** `applicationDidFinishLaunching`; those URLs are queued in `pendingCollections` and opened once the manager exists (`a2bb26c`).

### 2.9 Quick Access selection and Combine

- `QuickAccessSelection` (CSCore): `ids` in selection order, `host` = the most recently ⇧-clicked still selected; `timersPaused = !ids.isEmpty`; `combineHost` only with ≥ 2; `ordered(byStack:)` gives stack order (oldest first); `removed(id)` when a selected thumbnail is dismissed.
- ⇧-click (checked with `NSEvent.modifierFlags` in the tap handler) toggles, **screenshots only** (`offersCopyText(kind)`); a plain click clears. Selected thumbnails: 2 pt accent outline and a `checkmark.circle.fill` top-right.
- The first selection pauses every timer; a newly shown thumbnail is paused at once while a selection exists. Clearing (plain click, Esc on a thumbnail, Combine, last selected dismissed) restarts every timer with its **full** timeout (`DismissTimer.restart`), except the hovered one and those being edited. Esc with a selection clears it instead of dismissing.
- The host's strip shows **Combine (N)** instead of Copy / Save / Edit; Combine passes the selected items oldest first to `CollectionManager.newFrom`.

### 2.10 Search integration

- `CaptureKind.collection` (prefix "Collection", extension `bugeye`); every `switch` handles it (opens via `openCollection`, Spotlight content type `.package`).
- Indexer: kind `.collection` reads the package (§09 §2.5); the launch pass scans `Collections/*.bugeye` (top level only, hidden temp siblings skipped).
- Find Capture: **Collections** kind chip; cells show the first image (`ThumbnailCache.cover`) and a stack glyph.
- **Pick mode** (`FindCaptureModel.onPick`): setting it forces the kind chip to Screenshots (and `refresh` re-forces it); ⌘-click toggles `picked` (a check overlay); Return/double-click hands the picked records (or the selected one), each re-located to its current path, to `onPick`, then closes. `AppDelegate.addCapture` inserts them with their `pixelsPerPoint` and the file's provenance. With indexing off, the panel shows "Search is off in Settings".

### 2.11 The guide recorder internals

**Session** (`GuideSession`): permission check → `makeRecorder()` → `try await recorder.start()` → show `GuideBarPanel`. `done()` closes the bar and awaits `recorder.done()`. Failures close the bar and post the message. `shouldTerminate` ends a running guide and returns false.

**Recorder** (`GuideRecorder`, `@MainActor ObservableObject`):
- `start()`: name `Guide <date>`; create the draft folder and write an empty package; start the frame buffer for every display (excluding Bugeye's PID); hook `onFailure`; start input.
- Input: `GuideInputMonitor` uses `NSEvent.addGlobalMonitorForEvents` for `[.leftMouseDown, .rightMouseDown]` and `.keyDown` (auto-repeats skipped). Global monitors never see Bugeye's own windows, so the bar is never a step. Key monitoring needs Accessibility. The point is the **event's own** `cgEvent.location` (global, top-left), not `NSEvent.mouseLocation` (`959bf46`); the time is `NSEvent.timestamp` (seconds since boot).
- `click(point, time, right)`: if recording and not paused, **first** take the shot (frame + window rect), **then** read Accessibility (slow; the click takes effect meanwhile) (`959bf46`), then feed `GuideStepBuilder`.
- On `.added`: the first click step inserts heading "Guide: <app>" at the top if there is no heading; append caption; for click steps with a shot append an image block with one marker; `stepBlocks` remembers each step's block IDs for Undo and caption changes.
- **Draft writes** are serialized: each `enqueueWrite` chains on the previous task in a detached task that writes the PNG (if any), removes undone files, and rewrites `collection.json` atomically from a snapshot. Memory stays flat. `done()` awaits them.
- `shot(at:time:)`: display containing the click → `frames.frame(display:before:)` → in Window mode `GuideFrames.windowRect` → `pixelRect` (points → pixels, integral, clipped) → `cropping(to:)`; marker = `GuideFrames.marker(click, in: crop, ...)`; block scale = the display's `backingScaleFactor`.
- Displays (`AppDelegate.guideDisplays`): `NSScreen.screens`, `NSScreenNumber`, frames converted to global top-left using the **first** screen's height. Windows (`guideWindows`): `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`, front to back, PID, layer, bounds.

**Frames** (`GuideFrameBuffer`, CSCapture):
- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`; per requested display an `SCContentFilter(display:excludingApplications: [Bugeye], exceptingWindows: [])`.
- `SCStreamConfiguration`: width/height = display points × `filter.pointPixelScale` (native pixels), `minimumFrameInterval = CMTime(value: 1, timescale: 8)` (8 fps), `kCVPixelFormatType_32BGRA`, `showsCursor = false`, `queueDepth = 4`. Output on a private serial queue.
- Each sample: only `SCFrameStatus.complete` frames (idle frames carry no pixels); `VTCreateCGImageFromCVPixelBuffer`; then an **owned copy** (`ScrollFrameSource.ownedCopy`) so holding frames never starves ScreenCaptureKit's buffer pool; pushed into the display's `FrameRing` with `CMTimeGetSeconds(presentationTimeStamp)`. That timestamp is on the host clock (seconds since boot), the same clock as `NSEvent.timestamp`, so they compare directly.
- `FrameRing<T>`: capacity **8** (about one second at 8 fps; was 3, see §3); `frame(before:)` = `GuideFrames.pick`: the newest frame with time < click time, else the oldest kept.
- `didStopWithError`: reported once, mapped with `ScreenCapturer.map` (user-declined → permission denied), delivered on the main queue.

**Window rect** (`GuideFrames.windowRect`): the first (topmost) window not owned by Bugeye containing the click; if its layer > 0 (menu, popover), union with the first layer-0 window of the same PID; clipped to the display; nil → whole display.

**Element** (`StepElementReader` + `LiveAXPoint`):
- `AXUIElementCreateSystemWide()` + `AXUIElementCopyElementAtPosition`; every element gets `AXUIElementSetMessagingTimeout(..., LiveAXTree.messagingTimeout)` (0.25 s, the M9 limit).
- Walk up `kAXParentAttribute` at most 6 levels to the first role in `StepCaption.actionableRoles` (`AXButton, AXMenuItem, AXMenuBarItem, AXCheckBox, AXRadioButton, AXTab, AXPopUpButton, AXLink, AXTextField, AXTextArea, AXComboBox, AXCell, AXRow, AXDisclosureTriangle, AXSlider`); none found → the original element.
- App name: `AXUIElementGetPid` → `NSRunningApplication.localizedName`, else "the app".
- **Label:** first non-empty of `AXTitle`, `AXDescription`, `AXPlaceholderValue`, the first `AXStaticText` child's `AXValue` (children read with `AXUIElementCopyAttributeValues(..., 0, 8)`). `**` stripped, whitespace collapsed, cut to 60 characters as 59 + "…".
- **Privacy:** never a field's `AXValue`. For `textEntryRoles` (`AXTextField, AXTextArea, AXComboBox, AXSearchField`) the static-text child is **not** read (it is the typed content in web views and Electron) (`5c78528`). A secure field (`AXSecureTextField` subrole) gives its title only.
- Checkbox state: `AXValue` as a number, read at click time (≠ 0 → "Uncheck").

**Step builder** (`GuideStepBuilder`, pure): constants `limit = 100`, `doubleClickInterval = 0.4`, `doubleClickDistance = 4`, `shortcutRepeat = 1`. `handle(GuideInput) -> GuideChange` (`.added(i)`, `.captionChanged(i)`, `.ignored`, `.limitReached`). Rules:
- paused → ignored;
- a left click within 0.4 s and 4 pt of the last **left click** step with an equal `StepElement` → that step becomes a double-click (typed flag cleared);
- full → limitReached;
- shortcut (`KeystrokeFormatter.label(..., showAllKeys: false)` non-nil, needs ⌘ or ⌃) → text step unless the same caption was the last text step within 1 s (then only its time updates);
- other key → marks the last step `typed` once if it is a click step.
- `undo()` pops the last step.

---

## 3. Gotchas and bugs we hit

The final review (fresh reviewer over the whole branch) found **3 Critical and 8 Important** issues; they were fixed in the nine commits below. The commits have no bodies and the per-finding severity wasn't recorded, so the table gives what each diff shows.

| Symptom | Root cause | Fix |
|---|---|---|
| Save As produced a package with every image "missing"; undo after a save brought back blocks with missing images | `write` looked for unchanged images only in the **destination** package (empty for Save As); `save` cleared `imageURLs`, and images only undo still referenced were dropped from the new package | `write(..., from: packageURL)` copies from the document's own package; `keepUndoImages()` preserves undo-only images in scratch or `$TMPDIR/Bugeye-collection-undo/` (`1a6fb3d`) |
| A guide caption could contain what the user typed into a web text area or composer | The label fallback read the first `AXStaticText` child; in web views/Electron a field's static-text child **is** its content | Never read the static-text child of `textEntryRoles` (`5c78528`) |
| Double-clicking a `.bugeye` in Finder while Bugeye was not running opened nothing | AppKit calls `application(_:open:)` before `applicationDidFinishLaunching`; `collections` was still nil | Queue `pendingCollections`, open them at the end of launch (`a2bb26c`) |
| Closing a collection with an open, dirty image editor lost the edit (or the editor's later save hit a gone window); double-clicking the image again opened a second editor | The collection didn't track its editors | `editors[blockID]`; `windowShouldClose` asks each dirty editor first (Cancel stops the close), then closes them; a second double-click fronts the open editor (`af06086`) |
| Quitting during a guide lost its steps (the old code fired `guide.done()` asynchronously while the app terminated) | Quit didn't wait for the guide | `GuideSession.shouldTerminate()` ends the guide (which opens the collection) and cancels this quit (`3104528`) |
| Crop mode showed the already-cropped, framed image, so you couldn't widen a crop, and a tall image overflowed its row | The row drew `rendered` in crop mode | Crop mode draws the uncropped, unframed `source`, fitted inside the current row height (`a409fdf`) |
| A step showed the wrong window or a frame from after the click (menu already open/closed, new page loaded) | (1) The click point came from `NSEvent.mouseLocation` at handler time, not the event's own location; (2) the window rect and frame were picked **after** the Accessibility read, which can take several 0.25 s timeouts; (3) only 3 frames (375 ms) were kept, so by the time the frame was picked none older than the click remained | Use `event.cgEvent.location`; take window and frame first, then read AX; `FrameRing.capacity` 3 → 8 (about 1 s) (`959bf46`) |
| Big guides and drops froze the window and used gigabytes; Add Capture… and Combine lost each capture's scale (markers and text drawn at 1× on Retina captures) and its source; exports blocked the main thread | Every image decoded eagerly into an unbounded dictionary, row heights decoded images, PNGs re-encoded on insert; Add Capture inserted by URL only; exporter ran on the main actor | LRU cache of 24 decoded images, row heights from the model, PNGs copied as files, `imageInfo` reads size/DPI without decoding; insert API takes `(url, pixelsPerPoint, source)`; export and Copy in a detached task with a file map (`a507583`) |
| PDF: a long paragraph ran off the page bottom; an image after text was squeezed into a sliver | Text drawn in one frame without flowing; images scaled to whatever height was left | Flow text with `CTFramesetterSuggestFrameSizeWithConstraints`' fit range across pages; an image that would end up in under a third of a page starts a new page (`c9d701f`) |

Other gotchas found while building:
- **Package swaps drop xattrs.** `replaceItemAt` on the package folder loses `dev.msenechal.bugeye.id`; read it before and write it after every save.
- **`Collection` name clash** (see §2.1).
- **SwiftUI macros unavailable** (Command Line Tools only): toolbar and bar models are `ObservableObject` + `@Published`.
- **Text undo vs document undo:** the text view's own undo actions are removed at the end of editing (`removeAllActions(withTarget: textStorage)`), so ⌘Z after leaving a block undoes the whole typing as one document step instead of replaying character undos against a reloaded row (design rule from the plan; not a recorded bug).
- **Reloading the table while typing ends the edit:** `documentChanged` skips reloads while `doc.isTyping`; height changes use `noteHeightOfRows(withIndexesChanged:)` instead.
- **Two clocks:** SCStream presentation timestamps and `NSEvent.timestamp` are both host-time seconds since boot; don't convert either to `Date`.
- **Idle SCStream frames:** only `.complete` status frames carry pixels; on a static screen the ring may hold only old frames, which is fine (the screen didn't change).
- **ScreenCaptureKit buffer pool:** copy each frame (`ownedCopy`) before keeping it, or the stream stalls when the ring holds its surfaces.
- **Bugeye's own bar in frames:** exclude Bugeye's `SCRunningApplication` in the filter and its PID in `windowRect`.
- **Editor as collection image editor:** the Edit menu's ⇧⌘C item is shared; the collection window retitles it "Copy Image" in `validateMenuItem` and the editor retitles it "Copy Text".
- **Spec deviations (planned):** `frame` is optional (nil = None); `ImageBlock.pixelsPerPoint` added; Settings has no shortcut list, so ⇧⌘9 joined the "shortcuts still on" notice; the editor reports its whole `EditorState` and the collection computes the marker shift; the page background is the system text background, not the night background.
- **Tests:** fakes `FakeFrameSource`, `FakeGuideInput`, `FakeAXPoint`; real SCStream/AX/export only under `CSC_INTEGRATION=1` (`theGuideBufferHasAFrameFromBeforeNow`, `aRealAccessibilityReadOfTheMenuBarGivesACaption`, `theRealDisplaysAndWindowsAreReadable`, `aRealCollectionExportsToEveryFormat`); `make smoke`'s filter was widened to include them (`e5abd5e`).

---

## 4. Known open issues (deferred minors, `docs/backlog.md` "M11 review minors")

- A double ⇧⌘9 can start two guides: `GuideSession.start` has no `isStarting` guard while `recorder.start()` awaits.
- A click on the menu bar in Window mode gives a thin menu-bar strip (WindowServer's layer-24 window has no layer-0 partner); treat menu-bar/Dock layers as the front app's window or the display.
- `guideWindows()` doesn't skip transparent or unshareable overlay windows (Rectangle, Zoom, Raycast), which can be picked as the clicked window.
- A display plugged in mid-guide gets no stream: its clicks become caption-only steps.
- An Accessibility failure gives the heading "Guide: the app".
- A checkbox's state is read after the mouse-down may have toggled it: Check/Uncheck can come out reversed.
- The frame ring copies every full-resolution frame (8 fps per display): heavy on 5K.
- Frame ▾ offers fills only; padding, corners and shadow aren't adjustable.
- Renaming in the toolbar commits on Return only; clicking away leaves field and model apart.
- HEIC/JPEG drops ignore EXIF orientation.
- Markdown: single newlines inside a paragraph become soft breaks and a heading with a newline splits; HTML has no `dir="auto"` for RTL text.
- An editor save after its block was deleted is dropped silently.
- Quit asks about an empty, never-saved, dirty collection that closing alone wouldn't ask about.
- The ✓ on a selected Quick Access thumbnail can sit over the source chip.
- Partly fixed, rest deferred: the clicked element's AX read still runs on the main thread (up to ~30 calls × 0.25 s in a slow app); visible image rows re-render at full resolution on every document change; `renderPage` holds every full-resolution render before scaling to 16,000 px.

Also observed while writing this (not in the backlog):
- `$TMPDIR/Bugeye-collection-undo/` is never cleaned.
- Every collection save re-indexes it with `createdAt = Date()`, so its date in Find Capture is the last save.
- `AppDelegate.application(_:open:)` has mis-indented lines from the `a2bb26c` re-indent; harmless.

---

## 5. Do it better next time

1. **Make the guide session a state machine** (`idle → starting → recording ⇄ paused → finishing`) so double ⇧⌘9, quit, failure and Done can't race. Test it with fakes.
2. **Capture the step synchronously at the event.** Take the window list and pick the frame inside the event handler (both are cheap), then do AX on a background queue with a hard total budget (say 0.5 s) and fill the caption in later. A global monitor runs after the target app may have handled the mouse-down, so a checkbox's value can already be toggled. Use a `CGEventTap` (listen-only, head insert) to read the value before delivery, or caption neutrally ("Toggle **x**") when unsure.
3. **Don't copy every frame.** Keep frames as `IOSurface`-backed buffers with a retained pool of 8, or downscale only the ring copy and re-grab at full size from the surface for the picked frame. Or keep fewer frames per display but sample on click.
4. **Window choice:** skip windows with alpha 0, `kCGWindowSharingState == none`, and known overlay layers; map menu-bar and Dock layers to the front app's main window or the display.
5. **Handle display changes:** observe `NSApplication.didChangeScreenParametersNotification` and start/stop streams per display.
6. **Package writes:** keep the swap, but carry xattrs through a single helper, and clean undo copies when the document closes. Consider storing image files content-addressed (`images/<sha256>.png`) so Save As and undo never lose an image and duplicates are free.
7. **Rows:** cache each row's rendered image at display size (not full resolution) keyed by (file, crop, frame, markers, numbers), and reuse table cells.
8. **Export:** render each image scaled to its final page size before compositing, so a 16,000 px page never holds full-resolution renders. Write PDFs with the same display list as the image export.
9. **Full Frame controls** (padding, corners, shadow) reusing the editor's picker, as the spec asked.
10. **Rename on focus loss**, not only Return. Apply EXIF orientation on drops (`kCGImageSourceCreateThumbnailWithTransform` or orientation-aware decode). Markdown: turn single newlines into hard breaks (two spaces) or separate paragraphs; HTML: `dir="auto"` on text elements.
11. **Typed text privacy as an invariant test:** feed the builder and reader a fixture where every AX string of a field equals a secret and assert the secret never appears in captions, the draft, the index or exports.

### Portable core vs macOS shell (rebuild on Linux, see `13-rebuild-strategy-agentic-ci-and-claude.md`)

| Piece | Where | Notes |
|---|---|---|
| `CaptureCollection`, blocks, step numbering, all edits, `imageReplaced` | portable core | already pure; uses only Foundation geometry |
| `CollectionDocument` (undo, typing steps, dirty, read-only, `keepUndoImages` decisions) | portable core | file copies through a `FileStore` port |
| `.bugeye` package read/write, version rule, temp-sibling swap | portable core | `FileManager.replaceItemAt` exists in swift-corelibs-foundation but its semantics differ; put the swap behind the port and test the real one on macOS CI. The ID xattr goes through `FileMetadataStore` |
| `CollectionLayout`, PDF pagination decisions, Markdown, HTML, `InlineBold`, `MarkdownEscape`, `HTMLEscape` | portable core | Markdown and HTML are plain strings: golden-file tests on Linux |
| `renderImage`, `renderPage`, PDF drawing, text measurement | core emits a **display list**; macOS shell rasterises with Core Graphics / Core Text | text height needs a `TextMeasurer` port (Core Text on macOS, a fake with fixed line metrics on Linux); PDF text flow needs "how many characters fit" from the same port |
| `StepCaption`, `GuideStepBuilder`, `GuideFrames` (pick, window rect, pixel rect, marker), `FrameRing` over `PixelBuffer`, `GuideSettings` | portable core | already pure |
| `GuideSession` / `GuideRecorder` logic (steps → blocks, draft writes, Undo, Done, failure, quit) | portable core as a state machine | ports: `ScreenSource` (frames), `InputSource` (clicks/keys), `AXReader` (element at point), `WindowList`, `Clock` |
| `StepElementReader` walk-up and label rules | portable core over an `AXReader` port | `LiveAXPoint` is the macOS adapter |
| `QuickAccessSelection`, timer restart rules, pick-mode model | portable core | |
| `GuideFrameBuffer` (SCStream), `GuideInputMonitor` (global monitors), `LiveAXPoint`, window list, `NSTableView` page, row views, toolbar, panels, save panels, UTI/Info.plist, editor round trip | macOS shell | thin adapters; real ones run only in the self-hosted Mac smoke job |

**Claude (opt-in, redacted, with the template fallback; see file 13 §5):**
- Guide captions: polish template captions into prose, and write a caption when AX gave nothing (Electron/canvas apps) from a crop around the click point plus role/title/app name. Never send typed text, secure fields, or field values; the reader already never collects them, so they can't leak.
- Guide title and a short intro paragraph; collection intro and per-image captions from the images and existing text blocks.
- Put the LLM call behind an `LLMClient` port in the core with a fake; the result fills normal text blocks (undoable), so a collection never depends on the network to open or export.
