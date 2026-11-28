# Wave 1 Editor core: plan

**Goal:** the annotation editor of `docs/specs/2026-11-27-wave-1-editor.md` (approved 28 Nov 2026): the display-list executor, the portable editor core, the macOS editor shell, and its wiring.
**Spec:** `docs/specs/2026-11-27-wave-1-editor.md`; contract: `docs/specs/2026-11-27-wave-1-contracts.md` (merged in PR #3). Where this plan and the spec differ, the spec wins unless a ruling below says otherwise.
**Ledger:** `docs/ledgers/wave-1-editor.md`. Commit trailers: the session's Co-Authored-By and Claude-Session lines.
**Process:** written and executed by the same session without approval (`design/14` R11). Ambiguities are decided and ledgered as `Ruling:` with their cost if wrong.

## Slices and pull requests

The epic lands as four PRs to `main`, each on its own branch, stacked in this order (each branch starts from the previous one, so the ledger stays linear; a PR's diff shows the unmerged slices below it until they merge, then the branch merges `main`):

| # | Branch | What | macOS CI |
|---|---|---|---|
| A | `feat/wave1-editor-executor` | plan, ledger, the display-list executor (`Sources/Mac/MacAdapters/DisplayList/`) and its probe tests (E11, K10). Early, because Recording's overlay PR waits for it | yes |
| B | `feat/wave1-editor-core` | `EditorCore`, all portable: model, document, geometry, layout, interaction controller, text layout, renderer, region effects, zoom, window sizing, sessions, last capture, chrome models, strings, module | no (Linux only) |
| C | `feat/wave1-editor-app` | `Sources/BugeyeApp/Editor/`: window, canvas, text view, chrome, ImageIO helpers, drag handle, prompts, the `EditorHost` implementation, and its macOS tests. Not wired: `EditorWiring` stays empty | yes |
| D | `feat/wave1-editor-wiring` | `EditorWiring.modules` and `install`; merges after Quick Access's wiring PR, one at a time with OCR and Recording (contracts §9). Description ends with the `CLAUDE.md changes` block | yes |

PRs start as drafts; `make test-core lint guards` is the check while drafted, pushes are batched (R10). The `macos` job is reached with a manual `workflow_dispatch` run on the branch while drafted, then by marking the PR ready. Each PR, when complete, gets a fresh final review (a subagent with no memory of writing it) and one fix pass for Critical and Important findings. No `needs-mac-check` on any Editor PR (E16, contracts §9).

## Facts checked

- Swift 6.4.3 on Linux here, as `.swift-version`. `EditorCore` depends on `BugeyeCore` and `BugeyeFeatures`; its test target on `EditorCore` and `BugeyeTestSupport` (`Package.swift`). `MacAdapters` depends on `BugeyeCore` only, so the executor can't see `RegionEffects`: blur goes through an injected closure (spec §8.1).
- Contract names used, checked on `main` (`44a44d9`): `DisplayCommand` (all nine cases), `GroupStyle`, `Shadow`, `GradientStop`, `BlurEffect`, `LineCap`, `LineJoin`, `VectorPath.ellipse(in:)`, `.roundedRect(_:cornerRadius:)`, `FontDescriptor.systemFontName`, `DisplayList.isBalanced`, `goldenJSON()`; `TextMeasuring`, `TextLineMetrics`, `FakeTextMeasurer`, `CoreTextMeasurer`, `CoreTextFonts.font(for:)`; `CaptureEventBus`, `CaptureChange.editingStarted/.editingEnded`, `CaptureEvent.preview`, `previewMaxWidth`; `CaptureFileWriter.write(_:to:attributesFrom:identity:requireExisting:)`, `TargetMissing`, `RenameFailed` (descriptions); `ClipboardWriter`, `ClipboardPayload(png:)`, `FakeClipboard`; `Notifier`, `FakeNotifier`; `PixelBufferImages.cgImage/pixelBuffer/preview`; `QuickAccessActionSpec`, `QuickAccessActionHandler`, `QuickAccessActionContext`; `ActionRouter.onQuickAccessAction/onMenuItem(_:isEnabled:perform:)/onOpen/canOpen/open`; `DocumentWindows.opened/closed`; `TerminationGate.addAsk`; `MainMenu` shell items and their selectors; `AppContext` and `AppContext.testing`; `EditorWiring.modules/install`.
- The `macos` workflow accepts `workflow_dispatch`, so a drafted branch can get a macOS run.

## Plan rulings

- **P1 — The plan lists files, tests and shapes, not every line of code** (as the contracts plan's P1): the same session writes and executes it at once (R11), and the committed code with tests seen failing first is the reviewable artefact. (cost if wrong: low.)
- **P2 — Four stacked slices** (table above) instead of one branch: the executor reaches `main` first for Recording, and each PR stays reviewable. (cost if wrong: low; a rebase if a lower PR changes in review.)
- **P3 — `EditorRenderer.lists`** takes `state`, `layout`, `ppp`, `measurer`, `active`, `hidden`, `selection` and `zoom` (the image size is the layout's). The overlay needs the selection, which the spec's signature leaves out. (cost if wrong: none.)
- **P4 — A blur's destination rect is its source rect**: the blur rect rounded outward to whole pixels and intersected with the image, then translated by `imageOrigin` (an integral offset). Spec §7 draws the integral source into the unrounded rect, which would rescale it by a fraction of a pixel. A blur entirely outside the image draws nothing. (cost if wrong: low; at most a pixel of difference at the edges.)
- **P5 — Text metrics:** every line of a text annotation uses the ascent and descent of measuring a single space (`" "`) at the font, so empty lines (from ⌥Return) keep their height; each line's width is its own measurement. Bounds = (origin, max width × lines × (ascent + descent)). (cost if wrong: low.)
- **P6 — Step label:** the number's baseline is `center.y + (ascent − descent) / 2`, which centres the measured box vertically. (cost if wrong: none.)
- **P7 — The selection outline** is drawn in `(0, 0.48, 1)` (the Blue swatch), 1 screen pt, dash 4/3, around the annotation's bounds outset 2 screen pt; handles are white 8 pt squares with a 1 pt `(0.5, 0.5, 0.5)` border. The spec leaves the outline's colour open. (cost if wrong: low; a colour.)
- **P8 — `EditorSessions` talks to the shell through an `EditorHost` protocol** (load, show, bring forward, retitle, export, the four prompts, log); the shell's window controllers implement nothing of the rules. Saves, Save As, copy, close and quit flows are `async` methods on `EditorSessions`, tested with a fake host. (cost if wrong: none.)
- **P9 — Save generations** increment when a save is requested; a finishing save marks the document saved and publishes `edited` only if no newer save was requested meanwhile and the session is still open (S6). The queued newer save does both for its own snapshot. (cost if wrong: low; one `edited` event instead of two.)
- **P10 — Save As failures** name the chosen file: `Couldn't save “<chosen name>”`. (cost if wrong: none.)
- **P11 — The drag handle renders off the main actor:** mouse-down on the handle starts the export and the write into the drag folder; the drag begins on the first mouse-dragged event after the file is ready. A failure beeps and logs; the drag never starts. (cost if wrong: low; a drag needs a moment of movement on big captures.)
- **P12 — Pixelate** cell = `max(1, round(cellSize))` px, averaging premultiplied bytes with round-half-up; **gaussian** = three box passes per axis with the box widths of the standard three-box approximation of σ = radius (W. Jarosz), clamped edges, integer running sums with round-half-up. (cost if wrong: low; E5's swap to Core Image remains.)
- **P13 — Shape degenerate checks** use closed intervals for "bounds miss the visible rect", so a perfectly horizontal line (zero-height bounds) inside the image isn't dropped. (cost if wrong: none.)

## Steps only the user can do

None until the manual pass (`docs/checklists/wave-1-editor.md`, written in slice D), which runs on the wiring PR's build once Capture's and Quick Access's wiring PRs are on `main`.

## Tasks

Each code task: write the tests, run the stated filter and see them fail (a compile failure for new names counts), write the code, see them pass, then `make test-core lint guards`. Tasks marked **macOS** can't compile here: test and code are committed together and the `macos` job is the result.

### Slice A — `feat/wave1-editor-executor`

1. **Plan and ledger.** This file and `docs/ledgers/wave-1-editor.md`. Draft PR.
2. **macOS: the executor** (`Sources/Mac/MacAdapters/DisplayList/DisplayListExecutor.swift`). `DisplayListExecutor(images:blur:)`; `execute(_:in:contextIsFlipped:)` (flips once when the context is y-up; groups → `saveGState` / `setAlpha` / `setShadow` × device scale / transparency layers in `bounds`; `clip`; strokes with cap, join, dash; gradients extended both ends; images and blur results drawn upright; `textRun` through `CoreTextFonts` at its baseline); `render(_:colorSpace:)` → `CGImage` (RGBA8 premultiplied last). `deviceScale(of:)` = √|det(CTM)|. Tests (`Tests/MacAdaptersTests/DisplayList/DisplayListExecutorTests.swift`, probes only, E21): a fill at the top-left lands top-left; an image's top row lands at the top; a blur region asks the closure for its source rect and draws the result upright at its rect; stroke cap and dash; gradient colours at both ends and beyond; clip limits a fill; group opacity halves alpha; an isolated group with opacity doesn't darken overlaps; a shadow's offset falls downward and scales with the device scale (2× context); a text run's ink sits above its baseline and matches `CoreTextMeasurer`'s width within 1 px; an unbalanced list draws nothing past the error.

### Slice B — `feat/wave1-editor-core` (Linux)

3. **Model** (`Model.swift`): `StrokeWidth`, `BlurMode`, `AnnotationStyle`, `AnnotationShape`, `Annotation`, `FrameFill`, `BackgroundFrame`, `EditorState`, `ToolOptions`, `EditorPalette` (swatches, gradients). Tests: defaults (§5.5, §5.6), widths 2/4/8, step diameters 22/28/36, palette values.
4. **Tools and keys** (`EditorTool.swift`): tools, letters, symbols, names, tooltips `<Tool> (<Key>)`, option sets per tool, cursors; `EditorShortcuts.action(keyCode:characters:modifiers:)` (letters without modifiers, case-insensitive, ⇧ excluded; Esc 53; Backspace 51; Delete 117; else nil).
5. **Geometry** (`EditorGeometry.swift`, `AnnotationGeometry.swift`, `TextLayout.swift`): `clampedCrop`; 45° snap and square; bounds; handles; hit testing (I1–I3); translate; resize with grab offset and flips; text layout on `FakeTextMeasurer`; computed step numbers (E7); degenerate checks (§5.4).
6. **CanvasLayout** (`CanvasLayout.swift`): crop, frame, 1× and 2×, showing the full image; `imagePoint(fromCanvas:)`.
7. **EditorDocument** (`EditorDocument.swift`): U1–U6, `cancelChange()` (E15).
8. **InteractionController** (`InteractionController.swift`): I4–I7, U5, U7, E15, the §5.4 rules, text entry, crop, frame edits, snapping hook (§8.3).
9. **RegionEffects** (`RegionEffects.swift`): byte-for-byte on synthetic buffers: pixelate grid anchored at the origin, partial edge cells, cell 1 is identity; gaussian of a constant is constant, edges clamped (no fade), a single bright pixel spreads symmetrically, radius 0 is identity.
10. **EditorRenderer** (`EditorRenderer.swift`): base, active and overlay lists (§7), golden JSON in `Tests/EditorCoreTests/Fixtures/` (loaded through `Bundle.module`): every tool, frame on and off, crop, crop tool overlay, shadows, highlighter, blur, multi-line text, steps, selection; every list `isBalanced`.
11. **Zoom and window sizing** (`ZoomModel.swift`, `WindowSizing.swift`).
12. **Chrome models and strings** (`EditorChrome.swift`, `EditorStrings.swift`): toolbar items in order with the reserved slots (§8.3), option rows per tool, frame popover values, `EditorServices`; every §5 string character for character.
13. **Module** (`EditorModule.swift`): ids, the Edit action, Open Last Capture.
14. **Sessions** (`EditorSessions.swift`, `EditorHost.swift`): S1–S7, E3, E4, E13, E19, E20 with a fake host, the real bus, `DocumentWindows`, a real `CaptureFileWriter` on a `TempDirectory` with `FakeFileMetadataStore`, `FakeClipboard`, `FakeNotifier`.
15. **LastCapture** (`LastCapture.swift`): S8 / E12.
16. **Drag folder** (`DragFolder.swift`): the folder under a given temporary directory, the file name, the 24 h cleanup on a `TempDirectory`.

### Slice C — `feat/wave1-editor-app` (macOS)

17. **ImageIO helpers** (`Editor/EditorImages.swift`): decode a PNG for display in its own colour space, encode PNG, the export render through the executor, the blur provider (`PixelBufferImages` extraction in the capture's colour space, `RegionEffects`, cache of 64). Tests: orientation, crop + frame + 2× sizes, frame shadow on a transparent capture, highlighter overlap, Strong pixelate and blur sample the pixels under them, text against `CoreTextMeasurer`.
18. **Canvas, clip view, text view** (`Editor/EditorCanvasView.swift`, `Editor/CenteringClipView.swift`): flipped view, cached base keyed by the base list's hash, active and overlay drawn live, events to the controller, the one reusable `NSTextView`.
19. **Chrome** (`Editor/EditorViewModel.swift`, `Editor/EditorChromeViews.swift`): SwiftUI toolbar, options strip, frame popover, from the core's chrome models.
20. **Window controller** (`Editor/EditorWindowController.swift`): layout, sizing, zoom, menu selectors and validation (E24), close prompt.
21. **Host and manager** (`Editor/EditorManager.swift`, `Editor/EditorPrompts.swift`, `Editor/EditorDragHandle.swift`): `EditorHost`, alerts, save panel, the termination participant, logging (§8.4). Tests (`Tests/BugeyeAppTests/Editor/`): save keeps the ID and other xattrs (real `XattrMetadataStore`), Save As gets a new ID, menu validation, `DocumentWindows` round trip, unsaved and quit prompts with injected answers, a leak test polling for the editor, its window and its canvas.

### Slice D — `feat/wave1-editor-wiring`

22. **Wiring** (`Wiring/EditorWiring.swift`): `modules = [EditorModule()]`; `install` binds the Edit action, Open Last Capture (with `isEnabled`), `onOpen(.screenshot)`, the termination ask. Test through `AppContext.testing`.
23. **Checklist** `docs/checklists/wave-1-editor.md` (§9 item 4) and the PR description's `CLAUDE.md changes` block.

## Review Focus

- Orientation: the executor's one flip, images and blur results drawn upright, text baselines, shadow offsets in device space (y up) at a zoomed device scale.
- Late results: a save finishing after a newer save was queued, after the window closed, after the capture moved (`TargetMissing` redo) or was deleted (gone alert, `created` instead of `moved`).
- Undo granularity: every gesture one step, Esc mid-drag none, restyle coalescing closed by the next other action, keyboard slider runs.
- The text view: focus, ⌘Z routed to it while typing, commit before every chrome action, IME.
- Main thread: decode, export, PNG encode, region effects and writes off the main actor; the canvas rasterises the base only on a state change.
- Retention: the canvas, its text view and every closure of the window controller and SwiftUI chrome are freed on close (leak test).
- macOS code in slices A, C and D wasn't compiled in this session before the `macos` job: name clashes (`Shadow`, `LineCap`, `Annotation`, `EditorTool` beside AppKit and SwiftUI).
