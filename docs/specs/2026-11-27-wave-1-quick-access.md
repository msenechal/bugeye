# Wave 1: Quick Access

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → Mac batch → manual pass

Quick Access rebuilds the first build's thumbnail stack (`design/02` §1.4, §2.12): one floating thumbnail per capture, its strip and ⋯ menu, hover, Esc, drag-out, ⇧-click selection. It runs as one of the parallel Wave 1 sessions (`design/14` R1), on Wave 0's skeleton. It builds on the Wave 1 contracts PR (`docs/specs/2026-11-27-wave-1-contracts.md`; §3 here lists what it uses) and on Capture's split of ownership (`docs/specs/2026-11-27-wave-1-capture.md` C2). It owns thumbnails, Save, Save As…, Delete, and the `saved` and `deleted` events.

## 1. Decisions

From the brainstorm (your answer):

| # | Question | Decision |
|---|---|---|
| B1 | Behaviour | **Exactly as `design/02` §1.4 documents it**: size, position, stack limits, timers and pauses, look, animations, ✕, badges, strip buttons, ⋯ menu, drag-out, double-click, Esc, hover and key focus, ⇧-click selection and Combine. Plus `design/02` §5 items 7–9: a pure view model with the panel as a dumb renderer, no closure ever captures an entry (leak tests for every panel type), and one event bus. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| Q1 | **Wave 1 ships only the actions that exist in Wave 1:** Copy (PNG + URL), Save, Save As…, Reveal in Finder, Delete, drag-out, ✕. Everything else arrives later through the extension points in §3, with no edit to Quick Access: Edit / Trim / Open (primary), Copy Text, Copy for AI, Copy as Markdown, Open Source, Find Similar, Export GIF…, Combine, the source chip, the sweep badge and the learned ★ ring. The media badge on recordings arrives in Wave 1 the same way: the Recording epic sets it as a decoration (contracts K12). | One owner per action. The parallel Editor epic registers Edit itself (§3). [Low] |
| Q2 | **While no primary action is registered for a kind, the strip shows Copy · Save · ⋯ only**, sharing the width. There is no disabled placeholder, and double-click does nothing (no beep). Once the Editor epic registers Edit, the strip becomes Copy · Save · Edit · ⋯ with no Quick Access change. | A dead yellow button would be tapped and do nothing. [Low: a placeholder is one row in the strip table.] |
| Q3 | **Extension points live in shared code, landed by the contracts PR** (§3): a reshaped `QuickAccessActionSpec` with a placement and kinds, handlers registered in the shared `ActionRouter` (contracts K6), the thumbnail-decoration store, and the editor's two bus changes. The activity feed for the habits epic stays in `QuickAccessCore` until that epic promotes it (contracts K3). | Area cores can't depend on each other (Wave 0 P14), and the Editor and Recording sessions work in parallel. [Medium: a missed extension point means a later epic edits Quick Access.] |
| Q4 | **⇧-click selection works now; Combine does not.** Selecting shows the border and ✓ and pauses every timer. The host's strip is replaced only while an action with `placement: .selection` is registered (the collections epic's Combine). Until then the host keeps its normal strip. | B1 asks for the selection rules; Combine needs collections. [Low] |
| Q5 | **Editing state and preview refresh come over the bus.** The editor publishes `editingStarted` / `editingEnded` (contract values, contracts K5) and `edited` with a ≤ 480 px `preview`. Quick Access never decodes a capture file. | One "capture changed" channel (`design/02` §5.9). The editor already holds the render. [Low] |
| Q6 | **Save moves through the contract's `CaptureFileWriter.move(_:into:)` (contracts §4.1.2); Save As… copies through `CaptureFileWriter.copy(_:to:identity: .new(id))` (Q18).** The copy is published as `created` with `origin: "quickAccess"`, and Quick Access ignores `created` events it published itself, so the copy gets no thumbnail. Quick Access publishes no `moved` in Wave 1; it follows `moved` from others. | Keeps the one-writer rule and the xattrs (`design/11` §6). The copy is a new capture for the index (`design/02` §1.4). [Low] |
| Q7 | **No new ports for macOS-only effects.** Trash, Reveal in Finder, the save panel, panels, animation and focus are effects the view model emits and Quick Access's own macOS files perform. Moving and copying files is portable and runs in `QuickAccessCore`. | Fewer shared files; the decisions stay Linux-testable. [Low] |
| Q8 | **Settings live in `QuickAccessCore`, under `quickAccess.*` keys**, read fresh at each show (Capture C6). Pane `Quick Access`, order 20, after Capture (10). A duration change applies to thumbnails shown afterwards; a position change at the next layout. | No edit to the shared `AppSettings`. [Low] |
| Q9 | **`NightChrome` comes from the contracts PR** (tokens and view styles, `design/01` §2.15, with §4's values; contracts §4.5), because Recording's options bar and countdown are night panels too. This epic uses it and doesn't edit it. | Q9's own cost case: another Wave 1 spec needed it. [Low] |
| Q10 | **Every user-visible string is settled in §5**, including those the docs leave open: failure notices, accessibility labels, Settings options. | `design/11` §7. [Low] |
| Q11 | **Edge rules the docs leave open:** Delete of a file that is already gone counts as deleted (no notice). Save As… onto the capture's own file does nothing. Only clicks on the image area toggle or clear the selection; ✕, strip and ⋯ clicks don't. ⇧-click on a recording, GIF or collection is ignored. A `created` for a capture already shown is ignored. Delete asks no confirmation (as documented). | Each is one test. [Low] |
| Q12 | **The documented layout stays, known issues included.** A new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). They go in this epic's ledger under `Backlog:`, which the wave-closing PR moves to `docs/backlog.md` (Q16). | B1: exactly as documented. [Low] |
| Q13 | **⋯ menu order is by `order`, with no separators.** Reveal in Finder is 800, Delete 1000. Later epics use: Copy Text 100, Copy for AI 200, Copy as Markdown 300, Open Source 400, Find Similar 500, Export GIF… 850. That reproduces the documented order for every kind. | The docs list no separators. [Low] |
| Q14 | **Testing split** (§8): the view model, file actions and every string on Linux; panel properties, hosting, Esc routing, drag provider and leak tests on hosted macOS CI; the look, animations and focus return into real apps in the Mac batch and your manual pass. | `design/14` R8–R10. [Low] |
| Q15 | **Reconciled with the Wave 1 contracts spec** (27 Nov 2026). §3 is now a list of what this epic uses from it. Renamed: `openedInEditor` / `closedInEditor` → `editingStarted` / `editingEnded`. Moved: `QuickAccessActionHandlers` into `ActionRouter`, `ModuleWiring` / `SharedServices` into `QuickAccessWiring` / `AppContext`, `NightChrome` into the contracts PR; `QuickAccessActionID` and the activity feed into `QuickAccessCore`. Dropped: `RecordingQuickAccessHandler` (tests write handlers inline). Recording thumbnails get their ▶ badge in Wave 1 as a Recording decoration (contracts §6, item 1). No settled string changed. | One contract for five parallel epics. [Low] |

Rulings added after the Wave 1 spec review (28 Nov 2026), one per finding (cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| Q16 | **Wave 1 sequencing** (contracts §9). Branches are `feat/wave1-quick-access-<slice>`, fix and stacked PRs included; the ledger is `docs/ledgers/wave-1-quick-access.md`, with backlog items (Q12's included) under `Backlog:`. The wiring PR merges after Capture's; `needs-mac-check` goes on it and on later PRs that change the wired feature. Its description ends with a `CLAUDE.md changes` block; Quick Access never edits `CLAUDE.md` or `docs/backlog.md`. | Wave 1 spec review, findings 2, 3, 5, 7 and 30. [Low] |
| Q17 | **A Save As… chosen after the thumbnail went away is still made.** The model keeps the item while the save panel is open; expiry, eviction, ✕ and Esc don't cancel the copy. Only a `deleted` event does (the file is gone). The documented timer pauses are unchanged. | Wave 1 spec review, finding 10: a 5 s thumbnail could time out behind the panel and the chosen file was never written. Pausing the timer instead would add a pause `design/02` §1.4 doesn't document. [Low] |
| Q18 | **Save As… copies the file** with `CaptureFileWriter.copy(_:to:identity: .new(id))` (contracts K28), for every kind, instead of reading it into memory. | Wave 1 spec review, finding 11: a multi-GB recording would be loaded whole; the first build copied the file (`design/02` §2.12). [Low] |
| Q19 | **No thumbnail for an editor's `created`.** Rule 1 also ignores `created` from the Editor (its gone-file Save As… after a Delete, Editor E20), as it ignores its own Save As… copy. | Wave 1 spec review, finding 16: the Editor now publishes `created` in that case; a copy the user saved isn't a new capture to act on. [Low] |
| Q20 | **The writer's errors read as settled text** in the `<error>` notices (contracts K30), e.g. `Too many files are already named like “Screenshot 2026-11-27 at 14.03.12.png”.` | Wave 1 spec review, finding 15. [Low] |

## 2. Scope

In scope:
1. The stack: show, layout, eviction, screen fit, timers and their pauses, fade and slide.
2. The thumbnail: image, ✕, selection border and ✓, strip, ⋯ menu, the decoration slots (in Wave 1 only Recording's media badge fills one).
3. Actions: Copy, Save, Save As…, Reveal in Finder, Delete, drag-out, double-click (runs the primary once registered), Esc.
4. Hover and key focus, with focus return.
5. ⇧-click selection; the `.selection` slot for Combine.
6. Following the bus: `created`, `saved`, `moved`, `edited`, `deleted`, `editingStarted`, `editingEnded`; publishing `saved`, `deleted` and the Save As copy's `created`.
7. The Quick Access settings pane, logging.

Out of scope: every action and decoration listed in Q1 (later epics); GIFs and collections arriving at all (Wave 1 creates screenshots and recordings, though the model handles every `CaptureKind`); the action-habits store; Duplicates; Open Last Capture.

## 3. Uses from the contracts

Everything below is in `docs/specs/2026-11-27-wave-1-contracts.md` and lands in the Wave 1 contracts PR, before any epic starts. Nothing in this epic touches a contract file (contracts §3); after the merge it writes only `QuickAccessCore`, `Sources/BugeyeApp/QuickAccess/`, `Sources/BugeyeApp/Wiring/QuickAccessWiring.swift` and their tests. Section numbers below are the contracts spec's.

- **Bus and items** (§4.1.1): `CaptureItem` (with `duration`), `CaptureKind`, `CaptureChange` (with `editingStarted`, `editingEnded`), `CaptureEvent` (`preview` on `created` and `edited`), `CaptureEventBus` (subscribe, publish, `item(_:)`), `CaptureSubscription`, `CaptureEventRecorder`. Quick Access publishes with `origin: "quickAccess"`.
- **Files** (§4.1.2): `CaptureFileWriter.move(_:into:)` for Save (never replaces; ` (2)` on a clash; same-volume rename or cross-volume copy keeping the attributes; the source untouched on failure); `CaptureFileWriter.copy(_:to:identity:)` for Save As… (Q18); the writer's errors' settled descriptions (Q20).
- **Ports and adapters** (§4.1.5, §4.4): `Notifier` + `FakeNotifier`; `ClipboardWriter` and its pasteboard adapter; `PixelBufferImages.cgImage` to draw a `preview`.
- **Quick Access types** (§4.2.1, §4.2.3): `QuickAccessActionSpec` with `QuickAccessPlacement` (`.primary`, `.menu`, `.selection`) and `kinds`; the registry conflicts `quickAccessPrimaryTaken` and `quickAccessSelectionTaken`; `QuickAccessTrigger`, `QuickAccessSubitem`, `QuickAccessActionState`, `QuickAccessActionContext`, `QuickAccessActionHandler`; `ThumbnailDecoration` and `ThumbnailDecorations`.
- **Router** (§4.2.4): `ActionRouter.quickAccessHandler(for:)` is the handler registry: a spec is shown only while it has a handler (`onQuickAccessAction`, registered by its owning module, Quick Access included).
- **Shell** (§4.5): `QuickAccessWiring` (`modules`, `install`), `AppContext` (`captureEvents`, `router`, `thumbnailDecorations`, `settingsPanes`, `clipboard`, `notifier`, `fileWriter`, `general`, `debugCommands`, `retain`), `AppContext.testing` for its macOS tests, `NightChrome`.
- **Wave 0, unchanged:** `ClipboardPayload`, `AppSettings.saveFolder`, `FolderPath`, `SaveFolder.ensureExists`, `SettingsStore`, `CaptureID`, `PixelBuffer`, `Rect2D`.

Quick Access-only and therefore in `QuickAccessCore`, not shared: `QuickAccessActionID` (`quickAccess.copy`, `.save`, `.saveAs`, `.reveal`, `.delete`), `PerformedQuickAccessAction` and `QuickAccessActivity` (record, observe), shaped as this spec's earlier draft had them, for the habits epic to promote later.

## 4. The thumbnail and stack (look)

| Property | Value |
|---|---|
| Thumbnail | 240 × 176 pt: image area 136 pt high, strip 40 pt |
| Position | Bottom-left (default) or bottom-right of the **visible frame** of the display under the pointer when the latest `created` arrived; 16 pt margin, 10 pt gap; newest at the bottom |
| Stack | At most 5 and never more than fit (§6.2) |
| Look | Night chrome: gradient `#2B3242` → `#1B1F29`, 1 px inner border white 8 %, 10 pt corners, dark appearance; text `#E8EAF0`; accent `#FFC93C` (hover `#FFD666`, text on accent `#1F2430`); control fill white 7 % (hover 12 %) |
| Image | The `created` preview, aspect-fill, clipped to the image area |
| ✕ | Top-left, yellow (accent) glyph on a dark circle; dismisses |
| Selected | 2 pt accent border and a ✓ at top-right |
| Decorations | Source chip at the top, right of ✕; media badge bottom-right; warning badge centred on the image's bottom edge (in Wave 1 only the media badge, set by Recording). At most one of each case is drawn, the first provider's; a second is logged |
| Strip | 8 pt padding, 6 pt gaps, 28 pt high buttons: Copy, Save, primary (accent fill), ⋯ (28 pt square). Buttons other than ⋯ share the remaining width |
| Ring | 1.5 pt accent ring on the suggested strip button, or on ⋯ |
| Animation | Fade in 0.18 s; fade out 0.15 s, then close; the stack slides to close gaps in 0.18 s |

Panel (`design/02` §2.12): `NSPanel` with `[.nonactivatingPanel, .borderless]`, `level = .statusBar`, clear background, shadow, not movable, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `NSAppearance(named: .darkAqua)`, `canBecomeKey = true`, `canBecomeMain = false`. Esc arrives as `keyDown` keyCode 53 or as `cancelOperation(_:)`; both send `escape`. Dismissal **closes** the panel.

## 5. Behaviour and strings

### 5.1 Strip and menu

| Slot | Screenshot | Recording | GIF |
|---|---|---|---|
| Copy | `Copy`: one item, PNG read from the file + file URL | `Copy`: file URL only | same as recording |
| Save | `Save` while `isSaved == false`; `Save As…` once saved | same | same |
| Primary | the registered `.primary` spec for the kind, else absent (Q2) | same | same |
| ⋯ | registered `.menu` specs for the kind, then `Reveal in Finder` (800), `Delete` (1000) | same | same |

- The suggested action (a `suggestedAction` decoration): if its id is Copy, Save, Save As… (both ring the Save slot) or the primary, that button gets the ring. Otherwise ⋯ gets the ring and the item's title is prefixed `★ ` (U+2605, space).
- With a `.selection` spec registered and two or more selected, the host's strip is one accent button `<title> (N)`, e.g. `Combine (3)`.
- Accessibility labels: ✕ `Dismiss`, ⋯ `More`.
- Double-click on the image runs the primary with trigger `.doubleClick`; with none registered it does nothing.

### 5.2 Actions

Every action goes through one dispatcher keyed by `CaptureID`, which first records a `PerformedQuickAccessAction` (for strip, menu, double-click, decoration and selection triggers), then acts on the entry's **current** item.

| Action | Effect | Event published |
|---|---|---|
| Copy | `ClipboardWriter.write` per §5.1. File missing or unreadable: notice | none |
| Save | Ensure the save folder (`AppSettings.saveFolder`, read fresh) exists, then `CaptureFileWriter.move(file, into: folder)`. The button becomes `Save As…` | `saved` (`isSaved = true`, new `fileURL`, `previousURL`, `origin: "quickAccess"`) |
| Save As… | Save panel: name field = current file name, starting folder = the file's folder, content type of the file. On OK: `CaptureFileWriter.copy(current, to: chosen, identity: .new(newID))` (Q18), for every kind. Chosen = current file: nothing (Q11). The copy is made even if the thumbnail was dismissed while the panel was open, unless a `deleted` event dismissed it (Q17) | `created` for the copy (new id, `isSaved = true`, the thumbnail's preview, `origin: "quickAccess"`) |
| Reveal in Finder | `NSWorkspace.activateFileViewerSelecting([url])` | none |
| Delete | Saved: move to the Trash. Temp: remove the file. Already gone: treated as done. Then dismiss | `deleted` |
| Drag | Image drag provides the file at the entry's current URL at drag start; the thumbnail stays | none |
| ✕ | Dismiss. A temp file stays in the temp folder (purged after 24 h by Capture) | none |

File work (Copy's read, Save, Save As…) runs off the main actor; its result returns as an event tagged with the `CaptureID` and is dropped if the entry is gone, except that a finished Save or Save As… still publishes its event (the file did move).

### 5.3 Notices

Posted through `Notifier`. `<path>` is shown as General shows it (`~/…`); `<name>` is the file name; `<error>` is the error's `localizedDescription`, settled for the writer's errors by contracts K30 (Q20).

| Case | Title | Body |
|---|---|---|
| Save: folder missing or unwritable | `Couldn't save to folder` | `<path> is unavailable. The capture stays in the temporary folder.` |
| Save: other failure | `Couldn't save to folder` | `<error>` |
| Save As… failed | `Couldn't save a copy` | `<error>` |
| Copy: file missing or unreadable | `Couldn't copy` | `<name> is missing or unreadable.` |
| Delete failed | `Delete failed` | `<error>` |

A failed action leaves the thumbnail and its timer as they were.

### 5.4 Settings pane

Pane `Quick Access` (module `quickAccess`, order 20). Two pickers:
- `Auto-dismiss`: `Never`, `5 seconds`, `10 seconds`, `30 seconds`, `60 seconds`.
- `Position`: `Bottom left`, `Bottom right`.

| Key | Type | Default | Valid |
|---|---|---|---|
| `quickAccess.autoDismissSeconds` | Int | 5 | 0 (Never), 5, 10, 30, 60; anything else → default |
| `quickAccess.position` | String | `bottomLeft` | `bottomLeft`, `bottomRight`; anything else → default |

## 6. The view model

`QuickAccessModel` in `QuickAccessCore` is the single owner of the stack. It is pure, on the main actor, with an injected clock value per event, and returns effects. The macOS controller feeds it events and performs effects; panels and views hold no state of their own.

**State:** `entries` (oldest first), each `{ item: CaptureItem, preview: PixelBuffer?, timer: DismissTimer, duration: Duration?, isEditing: Bool }` · `hovered: CaptureID?` · `selection: QuickAccessSelection` · `anchor: Rect2D` (visible frame, Cocoa points) · `position` · `keyPanel: CaptureID?` · `rememberedKeyWindow: WindowToken?` · `ticking: Bool` · `pendingSaveAs: [CaptureID: CaptureItem]` (Q17).

**Events:** `bus(CaptureEvent, now, anchor?, settings?)` (anchor and fresh settings only with `created`) · `tick(now)` · `hoverBegan(id, bugeyeKeyWindow: WindowToken?, now)` · `hoverEnded(id, bugeyeIsActive, now)` · `imageClicked(id, shift, now)` · `imageDoubleClicked(id)` · `escape(id, now)` · `closeTapped(id)` · `stripTapped(id, slot)` · `menuChosen(id, actionID, subitemID?)` · `decorationTapped(id, actionID)` · `selectionActionTapped` · `decorationsChanged(id)` · `fileActionFinished(id, action, result)` · `saveAsChosen(id, url?)` · `fadeOutFinished(id)`.

**Effects:** `showPanel(id, frame)` · `fadeIn(id)` · `fadeOut(id)` · `closePanel(id)` · `layout([id: Rect2D], animated)` · `render(id, ThumbnailState)` · `makeKey(id)` · `restoreKey(WindowToken)` · `activateFrontmostApp` · `startTicker` / `stopTicker` · `copy(ClipboardPayload)` · `runFileAction(id, .save | .saveAs(URL) | .readForCopy)` · `trash(url)` / `remove(url)` · `reveal(url)` · `showSavePanel(id, name, directory)` · `perform(QuickAccessActionContext)` · `recordActivity(PerformedQuickAccessAction)` · `publish(CaptureEvent)` · `notify(title, body)` · `log(message)`.

`ThumbnailState` is the whole render: preview, ✕, selected flag, strip buttons (title, id, accent, ring, enabled), ⋯ items (title with ★, id, state, subitems), decorations. The view draws it and nothing else.

### 6.1 Rules (each a named test)

1. **Show.** `created` with `origin` other than `"quickAccess"` and `"editor"` (copies the user saved, not new captures, Q19) and an id not already shown appends an entry: duration from fresh settings (0 → nil, never expires); timer started at `now`, paused at once if the selection is non-empty; `anchor` and `position` replaced; `limit = fitting(anchor.height)`; `push(…, sparing: hovered)`; every evicted entry is dismissed (rule 8); `showPanel`, `fadeIn`, `layout` for all; `startTicker` if not ticking.
2. **Fit.** `fitting(h) = max(1, floor((h − 2·16 + 10) / (176 + 10)))`; the stack holds at most `min(5, fitting)`. Push evicts from the oldest, skipping the hovered id and never the new item, until the count fits or only those two remain. ≈850 pt → 4.
3. **Layout.** For `entries.reversed()` (newest first) at index i: `y = anchor.minY + 16 + i·186`; `x = anchor.minX + 16` (bottom left) or `anchor.maxX − 16 − 240` (bottom right). Every entry follows the latest anchor. Any change of entries emits `layout(animated: true)`.
4. **Timers.** `DismissTimer` with `remaining` and `runningSince`; `pause(at:)` banks elapsed time; `resume(at:)`; `restart(duration:at:)`; `isExpired(at:)`; nil duration never expires. A timer runs only if its entry is not hovered, not editing, and the selection is empty. `tick` every 0.5 s dismisses expired entries; the ticker stops when `entries` is empty.
5. **Hover.** `hoverBegan`: `hovered = id`, pause its timer, remember `bugeyeKeyWindow` if given (Bugeye active and its key window isn't a thumbnail), `makeKey(id)`, `keyPanel = id`. `hoverEnded`: `hovered = nil`; resume unless editing or selection non-empty; if `keyPanel == id`, then `restoreKey(remembered)` when `bugeyeIsActive` and one is remembered, else `activateFrontmostApp`; `keyPanel = nil`.
6. **Esc.** On the key thumbnail: selection non-empty → clear it (rule 7); else dismiss that thumbnail.
7. **Selection.** `imageClicked(shift: true)` on a screenshot toggles its id; the host is the most recently ⇧-clicked id still selected. The first selected id pauses every timer. `imageClicked(shift: false)` on any image clears the selection. Clearing (plain click, Esc, a `.selection` action, the last selected dismissed) restarts every timer with its entry's full duration, except the hovered one and those editing. A `.selection` action runs with the selected items in stack order, oldest first, then clears the selection. ⇧-click on other kinds does nothing.
8. **Dismiss** (✕, Esc, expiry, eviction, Delete, a `deleted` event): remove from the selection (clearing rules if it empties), from `hovered`; if `keyPanel == id`, focus returns as in rule 5; `fadeOut` then `closePanel` on `fadeOutFinished`; the rest `layout`. A dismissed id never produces effects again, except a Save As… whose panel is open (rule 11).
9. **Following the bus.** For a shown id: `saved` / `moved` replace the item (button title follows `isSaved`); `edited` replaces the preview when one is given; `deleted` dismisses; `editingStarted` sets `isEditing` and pauses; `editingEnded` clears it and resumes per rule 4; any other change, known or not, re-renders (so handler states and decorations refresh). Events for ids not shown are ignored, except that `saved`, `moved` and `deleted` update or drop a `pendingSaveAs` item (Q17).
10. **Strip and menu.** Built per §5.1 from the registry's specs filtered by kind and by handler presence; each handler's `state` is asked at render: `hidden` drops the item, `disabled` greys it, `submenu` nests subitems. The primary is never hidden by state; `disabled` greys it.
11. **Actions.** Per §5.2. Delete on a saved file emits `trash`, on a temp file `remove`; the dismiss and `deleted` follow the success result. Save emits `runFileAction(.save)`; success publishes `saved` and re-renders. Save As… emits `showSavePanel` and the model keeps the entry's item in `pendingSaveAs` until the answer; `saveAsChosen(nil)` does nothing. `saveAsChosen(id, url)` for an entry dismissed by a `deleted` event does nothing; in every other case, the entry still shown or dismissed meanwhile (✕, Esc, expiry, eviction), the copy is made from the kept item (updated by `saved` and `moved` events) and its `created` published (Q17).
12. **No captured entries.** Every closure a panel or view holds captures only a `CaptureID` and a `weak` reference to the controller (`design/02` §5.8).

Regression tests carried over by name (`design/02` §3.2): `evictedQuickAccessPanelIsDeallocated`, `hoveredThumbnailIsNotEvictedByANewCapture`, `stackLimitFollowsTheVisibleHeight`, `escapeAsCancelOperationDismissesAndClosesTheGap`, `keyFocusReturnsWhenThePointerLeaves`, `saveKeepsTheSourceExtension`, `lateEventFollowsTheMovedFile`.

## 7. Architecture

| Target | Platform | Quick Access content |
|---|---|---|
| `BugeyeCore`, `BugeyeFeatures`, `BugeyeApp` shared files | | none: §3 comes from the contracts PR |
| `QuickAccessCore` | portable | `QuickAccessModule` (pane spec; `.menu` specs for Reveal in Finder and Delete); `QuickAccessStack`; `DismissTimer`; `QuickAccessSelection`; `QuickAccessLayout`; `QuickAccessModel` (§6); `ThumbnailState` and the strip/menu builder; `QuickAccessFileActions` (copy read, Save via `move`, Save As via `copy`, results as values); `QuickAccessSettings`; `QuickAccessStrings`; `WindowToken`; `QuickAccessActionID`, `QuickAccessActivity`, `PerformedQuickAccessAction` |
| `BugeyeTestSupport` | portable | nothing; tests use the contract's and Wave 0's fakes and write handlers inline |
| `BugeyeApp` (`QuickAccess/`, `Wiring/QuickAccessWiring.swift`) | macOS | `QuickAccessController` (bus subscription, display-under-pointer lookup, 0.5 s ticker, effect executor); `QuickAccessPanel`; SwiftUI `ThumbnailView` in an `NSHostingView` whose `rootView` is replaced on render; drag provider; `NSSavePanel`, Trash, Reveal and focus effects; the Quick Access pane (registered through `settingsPanes`), drawn with the contract's `NightChrome` |

Main thread: file reads, moves, copies and trashing run off the main actor. Only the model, the controller, the views and the bus are on it.

**Logging:** `os.Logger`, subsystem `dev.msenechal.bugeye`, category `quickAccess`: `show <id> stack <n>` · `dismiss <id> <reason>` (`close`, `escape`, `expired`, `evicted`, `deleted`) · `saved <file name>` · `failed <action> <id>: <error>` · `no handler for <action id>` · `decoration ignored <case> from <provider>`. File paths other than names are never logged.

## 8. Done when

1. The Wave 1 contracts PR has merged before this epic's first PR, and the session has checked §3's names against it. Branches: `feat/wave1-quick-access-<slice>` (fix and stacked PRs included); ledger `docs/ledgers/wave-1-quick-access.md`. Sequencing, merge order and Mac checks: contracts §9 (Q16); Quick Access's wiring PR merges after Capture's.
2. `linux` and `macos` are green on every ready-for-review PR of the epic (R10: drafts get no CI; pushes are batched), and `claude-review` has posted on each. Linux covers §6 rules 1–12 and the named regressions, `fitting` and layout on 1 and 2 displays with negative origins, timer banking, selection and host order, the strip/menu builder with fake specs and handlers (primary absent, primary present, hidden/disabled/submenu, ★ and ring placement, `Combine (N)`), Save, Save As… and Copy against temp folders and `FakeFileMetadataStore`, published events with `CaptureEventRecorder`, settings parsing, and every string in §5 character for character. macOS CI covers the panel's properties, Esc through both `keyDown` 53 and `cancelOperation`, render replacement, the drag provider's URL after Save, the pane, and leak tests: an evicted, a dismissed and an Esc-dismissed panel and its hosting view deallocate.
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. The Mac batch (`needs-mac-check` on the wiring PR, once Capture's wiring PR is on `main`, contracts §9) passes, reading the stack through a `quickAccess.stack` debug command (contracts K23): drag-out to Finder makes a copy of the current file; with the fixture app's `Type here` field focused, hovering a thumbnail then leaving returns typing to the fixture; thumbnails never appear in a full-screen capture.
5. Your manual pass, `docs/checklists/wave-1-quick-access.md` (`design/11` §5 format): Before you start (quit the old app; Wave 1 Capture installed) · How to check (`ls ~/Pictures/Bugeye`, `ls ~/Library/Caches/dev.msenechal.bugeye/Captures`, `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`) · A. Look: size, night chrome, ✕, strip, ⋯ · B. Stack: five captures, laptop screen limit, bottom left and right, display under the pointer, fade and slide · C. Timers: 5 s, Never, 60 s, hover pause, selection pause and full restart · D. Hover and keys: Esc dismisses, typing goes back to your app · E. Actions: Copy (paste into Slack, Finder, Preview), Save with saving off, Save As…, Reveal in Finder, Delete (saved to Trash, temp removed), drag to Finder and Slack · F. Selection: ⇧-click, ✓ and border, plain click and Esc clear · G. Failures: save folder unplugged, file deleted in Finder then Copy and Delete · H. Settings pane.
6. You say "all good", and the last (wiring) PR merges, its description ending with a `CLAUDE.md changes` block (contracts §9).
