# Wave 1 Quick Access: plan

**Goal:** build Quick Access (`docs/specs/2026-11-27-wave-1-quick-access.md`): the thumbnail stack, its strip and ⋯ menu, timers, hover and focus return, ⇧-click selection, Copy, Save, Save As…, Reveal in Finder, Delete, drag-out, the settings pane and logging, on the merged Wave 1 contracts.
**Spec:** `docs/specs/2026-11-27-wave-1-quick-access.md` (approved 28 Nov 2026), on `docs/specs/2026-11-27-wave-1-contracts.md` (merged, PR #3). Where this plan and the spec differ, the spec wins unless a ruling below says otherwise.
**Branches** (contracts §9, Q16), each a PR to `main`, merged in this order:

| Slice | Branch | Content | CI |
|---|---|---|---|
| 1 | `feat/wave1-quick-access-core` | plan, ledger, `QuickAccessCore` building blocks (Tasks 1–9) | linux |
| 2 | `feat/wave1-quick-access-model` | `QuickAccessModel` (§6), stacked on slice 1 (Tasks 10–14) | linux |
| 3 | `feat/wave1-quick-access-mac` | `Sources/BugeyeApp/QuickAccess/`: controller, panel, view, pane, debug command, macOS tests (Tasks 15–19); nothing wired | linux, macos |
| 4 | `feat/wave1-quick-access-wiring` | `QuickAccessWiring` filled (Task 20); `needs-mac-check`; merges after Capture's wiring PR | linux, macos, Mac batch |

**Ledger:** `docs/ledgers/wave-1-quick-access.md`. Commit trailers: the session's Co-Authored-By and Claude-Session lines.
**PRs:** each slice opens as a draft once its first commits exist. While a draft, `make test-core lint guards` is the check and pushes are batched (R10). A PR is marked ready when it needs the `macos` job or is done; each gets one fresh final review and one fix pass.
**Process:** written and executed by the same session without approval (`design/14` R11). Ambiguities are decided and ledgered as `Ruling:`.

## Facts checked

- Toolchain here: Swift 6.4.3 on Linux, the same as `.swift-version`.
- The contracts PR merged as `44a44d9`. Every name in the spec's §3 exists on `main`: `CaptureItem`, `CaptureKind`, `CaptureChange` (with `editingStarted` / `editingEnded`), `CaptureEvent` (with `preview`), `CaptureEventBus`, `CaptureSubscription`, `CaptureEventRecorder`; `CaptureFileWriter.move(_:into:named:identity:)`, `.copy(_:to:identity:)` (throws `SameFile` onto itself, contracts ruling I3), `NoFreeName`, `RenameFailed`, `TargetMissing`; `Notifier`, `FakeNotifier`; `ClipboardWriter`, `FakeClipboard`, `PasteboardClipboardWriter`; `PixelBufferImages.cgImage`; `QuickAccessActionSpec`, `QuickAccessPlacement`, `QuickAccessTrigger`, `QuickAccessSubitem`, `QuickAccessActionState`, `QuickAccessActionContext`, `QuickAccessActionHandler`, `ThumbnailDecoration`, `ThumbnailDecorations`; `ActionRouter.quickAccessHandler(for:)`; `FeatureConflict.quickAccessPrimaryTaken` / `.quickAccessSelectionTaken`; `QuickAccessWiring`, `AppContext` (every member the spec lists), `AppContext.testing`, `NightChrome` with `nightPanel(cornerRadius:)` and `NightButtonStyle(accent:)`; `AppSettings.saveFolder`, `FolderPath`, `SaveFolder.ensureExists`, `SettingsStore`, `InMemorySettingsStore`, `FakeFileMetadataStore`, `TempDirectory`.
- `ThumbnailDecorations.decorations(for:)` returns the providers' decorations flattened, without provider names (see P9).
- `QuickAccessCore` depends on `BugeyeCore` and `BugeyeFeatures`; its tests on `QuickAccessCore` and `BugeyeTestSupport`. `BugeyeApp` already depends on every area core. No manifest change is needed.
- `scripts/guards.sh`: portable targets import Foundation and Swift modules only; `Debug*.swift` files start with `#if DEBUG`.

## Plan rulings

- **P1 — The plan lists shapes, tests and commands, not every line of code** (the contracts plan's P1). The same session writes and executes it at once (R11) and the spec fixes the behaviour; code is written in the branch with each test seen failing first. (cost if wrong: low; the final review reads the diff.)
- **P2 — The model's clock is a monotonic `TimeInterval`** (`now: Double`, seconds; the controller passes `ProcessInfo.processInfo.systemUptime`), not `Date`: a wall-clock change never expires or freezes a thumbnail. (cost if wrong: none.)
- **P3 — `QuickAccessModel` is a `@MainActor final class`** with `handle(_ event:) -> [QuickAccessEffect]`. It gets the registry's specs, a handler lookup (the router), a decoration lookup and an id maker at init, so rendering asks handler states at render time (rule 10) and Save As… ids are deterministic in tests. (cost if wrong: none.)
- **P4 — Quick Access's own ⋯ items are handled inside the model.** `quickAccess.reveal` and `quickAccess.delete` are `.menu` specs of `QuickAccessModule` and are shown, like every spec, only while a handler is registered (the wiring registers them; their `perform` asks the controller to run the built-in on each item). Choosing them from the menu or a decoration runs the built-in directly, not the handler, so Delete's file work stays in one path. (cost if wrong: low.)
- **P5 — File actions carry the item, and Save carries the folder.** `runFileAction(id, .readForCopy(item) | .save(item, folder:, displayPath:) | .saveAs(item, to:, newID:))`: the controller reads `AppSettings.saveFolder` fresh at the moment of the tap (General's `folderURL` and `displayedFolder`) and passes them in the event `stripTapped(id, .save, saveFolder:)`, so the model stays the only decider and `QuickAccessFileActions` stays a pure function of its inputs. (cost if wrong: none.)
- **P6 — One Save, Save As… copy or Delete at a time per thumbnail.** While one runs for an id, Save, Save As… and Delete taps on that id are ignored (Copy is allowed). Without it a double-click on Save would move the file twice, the second failing with a notice. (cost if wrong: low; a second tap does nothing until the first finishes, well under a second.)
- **P7 — A finished Delete publishes `deleted` even if the thumbnail went away meanwhile**, like Save and Save As… (§5.2): the file is gone, and the bus must forget it. (cost if wrong: low.)
- **P8 — `bugeyeIsActive` is model state**, updated by a new event `appActiveChanged(Bool)` (the controller observes `NSApplication.didBecomeActive` / `didResignActive`) as well as by `hoverEnded`. Rule 8's focus return on a dismissal (✕, Esc, Delete, eviction of the key thumbnail) needs it and no other event carries it. (cost if wrong: none; one event.)
- **P9 — The ignored-decoration log line is `decoration ignored <case>`**, without `from <provider>`: `ThumbnailDecorations` hands out its decorations without provider names (Facts), and a contract amendment for a debug log line isn't worth a frozen-file change. Logged once per capture and case. (cost if wrong: low; a log line.)
- **P10 — A suggested action that isn't drawn rings nothing.** `suggestedAction(id)` rings Copy, Save (for `quickAccess.save` and `quickAccess.saveAs`) or the primary when id names them; else, if the ⋯ menu shows that id, ⋯ is ringed and the item gets `★ `; if the menu doesn't show it (no handler, hidden, other kind), nothing is ringed. (cost if wrong: low.)
- **P11 — Double-click on a disabled primary does nothing**, as with none registered (Q2): `disabled` greys the button, and a double-click shouldn't do what the greyed button refuses. (cost if wrong: low.)
- **P12 — The selection empties the same way whichever path empties it.** Toggling off the last selected thumbnail with ⇧-click also restarts every timer (rule 7 lists plain click, Esc, a `.selection` action and dismissal; ⇧-click off is the fifth way to empty it). (cost if wrong: low.)
- **P13 — A clipboard write that throws posts `Couldn't copy` / `<name> is missing or unreadable.`** The spec has no notice for it; the pasteboard adapter doesn't throw in practice, and the Copy notice is the closest settled text. (cost if wrong: low.)
- **P14 — Unwritable save folder:** Save first ensures the folder exists, then checks it is writable (`FileManager.isWritableFile`); either failing gives the "is unavailable" notice. Any error from `move` gives `<error>`. (cost if wrong: low.)
- **P15 — `PerformedQuickAccessAction`** is `{ actionID, captureID, kind, trigger }`; `QuickAccessActivity` (`@MainActor`) has `record(_:)`, `observe(_:)` and `recent` (the last 50). The habits epic reshapes it when it promotes it (K3). (cost if wrong: low.)
- **P16 — The controller queues events.** An effect that publishes on the bus reaches the controller's own subscription synchronously; the controller appends such events to a queue and handles them after the current effects run, so effects always run in the order the model returned them. (cost if wrong: none.)
- **P17 — Fades and the ticker are injectable.** The controller takes `animated: Bool` (false in tests: fade-out completes at once) and a ticker factory, so leak tests close panels deterministically without spinning the run loop. (cost if wrong: none.)
- **P18 — Thumbnails without a preview** draw an SF Symbol for the kind (`photo`, `film`, `square.stack`) on the night gradient (the spec's "generic icon", contracts §4.1.1). (cost if wrong: low; a look detail for the manual pass.)

## Steps only the user can do

- **The Mac batch** (Task 21) on the wiring PR, once Capture's wiring PR is on `main`; until then the ledger says `Waiting on: Capture` and the work goes on.
- **The manual pass** (`docs/checklists/wave-1-quick-access.md`, Task 22) and the merge of every PR.

## Tasks

Each code task: write the tests, run the stated command and see them fail (a compile failure on a new name counts), write the code, see them pass, then `make test-core lint guards`. Linux test command: `swift test --filter 'QuickAccessCoreTests\.'` unless stated. Tasks marked **macOS** can't compile here: test and code are committed together and the `macos` job is the result.

### Slice 1: building blocks (`feat/wave1-quick-access-core`)

1. **Plan and ledger.** This file and `docs/ledgers/wave-1-quick-access.md`. Draft PR after Task 2.
2. **Strings and ids** (`QuickAccessStrings.swift`, `QuickAccessActionID.swift`). Every string of §5 character for character: `Copy`, `Save`, `Save As…` (U+2026), `Reveal in Finder`, `Delete`, `Dismiss`, `More`, `★ ` (U+2605 + space), `<title> (N)`, the five notices (§5.3), pane `Quick Access`, `Auto-dismiss`, `Never`, `5 seconds`, `10 seconds`, `30 seconds`, `60 seconds`, `Position`, `Bottom left`, `Bottom right`; ids `quickAccess.copy` … `quickAccess.delete`. Tests: each literal; `folderUnavailableBody(path:)`, `copyFailedBody(name:)`, `selectionButtonTitle("Combine", 3) == "Combine (3)"`.
3. **Settings** (`QuickAccessSettings.swift`). Keys `quickAccess.autoDismissSeconds` (Int, default 5, valid 0/5/10/30/60) and `quickAccess.position` (`bottomLeft` / `bottomRight`, default `bottomLeft`); `load(from:)`, `duration` (0 → nil), `store(_:in:)` per key; the pane's option lists (seconds ↔ title, position ↔ title). Tests: missing, valid, invalid ints, wrong types, invalid strings, round trip, option lists in order.
4. **`DismissTimer`** (`DismissTimer.swift`). `init(duration:startedAt:)` running; `pause(at:)` banks; `resume(at:)`; `restart(duration:at:)` running; `isExpired(at:)`; `isRunning`; nil never expires; pause/resume idempotent. Tests: expiry at exactly duration; banking across two pauses; restart from paused; nil.
5. **Stack and layout** (`QuickAccessStack.swift`, `QuickAccessLayout.swift`). `fitting(height:) = max(1, floor((h − 32 + 10) / 186))`; `limit(height:) = min(5, fitting)`; `QuickAccessStack<Item: Identifiable>.push(_:limit:sparing:) -> [Item]` evicting oldest-first, skipping the spared id and the new item, stopping when it fits or only those remain; `QuickAccessLayout.frames(for: [CaptureID], anchor:, position:)`. Tests: `stackLimitFollowsTheVisibleHeight` (850 → 4, 176 → 1, 0 → 1, 2000 → 5), `hoveredThumbnailIsNotEvictedByANewCapture`, eviction order, one-slot screen keeps hovered + new, frames bottom-left and bottom-right on a primary display and on a second display with a negative origin.
6. **Selection** (`QuickAccessSelection.swift`). `toggle`, `remove`, `clear`, `isEmpty`, `ids` (click order), `host` (last ⇧-clicked still selected), `ordered(byStack:)`. Tests: host moves back when the host is toggled off; stack order for a `.selection` action.
7. **Thumbnail state and builder** (`ThumbnailState.swift`, `ThumbnailStateBuilder.swift`). `ThumbnailState { id, kind, preview, isSelected, strip: [StripButton], menu: [MenuEntry], moreHasRing, sourceChip, mediaBadge, warningBadge }`; `StripButton { slot (.copy/.save/.primary/.selection), actionID, title, isAccent, hasRing, isEnabled }`; `MenuEntry { actionID, title, isEnabled, subitems }`. `ThumbnailStateBuilder.build(...)` (`@MainActor`) per §5.1, rule 10, P10. Tests: primary absent (Copy · Save only); primary present (third, accent); kinds filter; spec without handler not shown; hidden/disabled/submenu; primary never hidden, disabled greys it; `Save` vs `Save As…` by `isSaved`; menu order by `order` with Reveal 800 and Delete 1000; ring on Copy, Save (save and saveAs), primary; ★ and ⋯ ring for a menu id; no ring for an undrawn id; `Combine (3)` only on the host with ≥ 2 selected and a `.selection` spec with a handler; first decoration of each case wins and the rest are reported.
8. **Module and activity** (`QuickAccessModule.swift`, `QuickAccessActivity.swift`). Module id `quickAccess`; pane `SettingsSectionSpec(id: "quickAccess", title: "Quick Access", order: 20)`; `.menu` specs `quickAccess.reveal` (`Reveal in Finder`, 800) and `quickAccess.delete` (`Delete`, 1000) for every kind; no menu items, hotkeys or main-menu items. `FeatureRegistry([QuickAccessModule()])` has no conflicts. Activity: record, observers called, `recent` capped at 50.
9. **File actions** (`QuickAccessFileActions.swift`). `Sendable` struct over `CaptureFileWriter`; `run(_ action:) -> QuickAccessFileResult`: copy read (screenshot: PNG bytes + URL; others: URL; missing/unreadable → `.copyFailed(name)`), Save (`ensureExists`, writable check, `move` → `.saved(item)` with new URL, `isSaved`; failures `.saveFolderUnavailable(path)` / `.saveFailed(description)`), Save As… (`copy(…, identity: .new(id))` → `.savedCopy(item)`; `SameFile` → `.saveAsUnchanged`; else `.saveAsFailed(description)`), and `deleteIfPresent(url)` for temp files (missing → done). Tests against `TempDirectory` and `FakeFileMetadataStore`: `saveKeepsTheSourceExtension` (`.mov` stays `.mov`), Save keeps the id attribute, Save into a missing folder creates it, Save onto a clash gives ` (2)`, folder path is a file → unavailable, Save As… new id and source untouched, Save As… onto itself unchanged, the writer's error descriptions reach the result text (Q20).

### Slice 2: the model (`feat/wave1-quick-access-model`)

10. **Events, effects, entries** (`QuickAccessModel.swift`, `QuickAccessEvent.swift`, `QuickAccessEffect.swift`, `WindowToken.swift`). The §6 shapes plus P5's `stripTapped(id, slot, saveFolder:)` and P8's `appActiveChanged`. Tests start with rule 1.
11. **Rules 1–4** (show, fit, layout, timers): each rule a named test; `lateEventFollowsTheMovedFile`; settings read fresh per `created`; `created` from `quickAccess` / `editor` ignored; a repeated `created` ignored; ticker start and stop.
12. **Rules 5–8** (hover, Esc, selection, dismiss): `keyFocusReturnsWhenThePointerLeaves` (restore remembered window when active, else activate the frontmost app); `escapeAsCancelOperationDismissesAndClosesTheGap` (model part); Esc clears a selection first; selection pauses every timer and clearing restarts all but hovered and editing; ⇧-click on a recording ignored; plain click clears; dismissal paths and their log reasons; `fadeOutFinished` closes; no effects for dismissed ids.
13. **Rules 9–11** (bus, strip and menu, actions): saved/moved/edited/deleted/editingStarted/editingEnded/unknown change; Copy, Save, Save As… (Q11, Q17 every branch), Reveal, Delete saved vs temp, failures and their notices with the timer left as it was; handlers' `perform` with the right context and trigger; `recordActivity` before acting; `no handler for <id>`; P6, P7.
14. **Debug snapshot** (`QuickAccessStackSnapshot.swift`): the model's stack as JSON lines for the `quickAccess.stack` debug command (contracts K23): `[{"id","file","kind","saved","hovered","selected","editing"}]`, newest last.

### Slice 3: macOS (`feat/wave1-quick-access-mac`) — **macOS**, not compiled here

15. **Panel** (`QuickAccessPanel.swift`): the §4 properties; `keyDown` 53 and `cancelOperation(_:)` call `onEscape`. Tests (`Tests/BugeyeAppTests/QuickAccess/`): every property; both Esc paths.
16. **View** (`ThumbnailView.swift`): draws `ThumbnailState` only (P18), ✕ `Dismiss`, ⋯ `More`, strip widths, ring, selection border and ✓, badges; gestures (double-click, ⇧-click, plain click), hover, drag (`NSItemProvider(contentsOf:)` with the URL asked from the controller at drag start). `ThumbnailActions` closures capture only the id and a weak controller (rule 12).
17. **Controller** (`QuickAccessController.swift`): bus subscription, display under the pointer, settings read fresh, the 0.5 s ticker, the effect executor (P16, P17), file work off the main actor, Trash, Reveal, `NSSavePanel`, focus, logging (`os.Logger`, category `quickAccess`). Tests: render replaces `rootView`; the drag provider's URL after Save; leak tests (an evicted, a dismissed and an Esc-dismissed panel and their hosting views deallocate); Esc through `keyDown` 53 and `cancelOperation` dismisses and closes the gap.
18. **Settings pane** (`QuickAccessSettingsPane.swift`): the two pickers through `SettingsStore`. Test: it writes the keys.
19. **Debug command** (`DebugQuickAccess.swift`, `#if DEBUG`): registers `quickAccess.stack`. Test: the answer for a two-thumbnail stack.

### Slice 4: wiring (`feat/wave1-quick-access-wiring`)

20. **Wiring** (`QuickAccessWiring.swift`): `modules = [QuickAccessModule()]`; `install` builds the controller (no panel or timer until a `created`), registers the built-in handlers, the pane and the debug command, retains the controller. Tests: install with `AppContext.testing` registers `quickAccess.reveal`, `quickAccess.delete`, the pane and the debug command; a `created` on the bus shows one panel. PR description ends with the `CLAUDE.md changes` block; label `needs-mac-check` once Capture's wiring PR is on `main`.
21. **Mac batch** (spec §8.4), through the debug channel: drag-out copies the current file; focus returns to the fixture's `Type here` field; thumbnails never appear in a full-screen capture.
22. **Checklist** `docs/checklists/wave-1-quick-access.md` (spec §8.5).

## Review Focus

- Late results: a file action finishing after its thumbnail was dismissed, after a `deleted`, or after a `moved` (the result must not resurrect an entry or overwrite a newer item).
- Q17: every way the thumbnail can go while the save panel is open, and the `pendingSaveAs` item following `saved` / `moved`.
- Timers: the running predicate (not hovered, not editing, selection empty) after every event that changes one of the three; banking across many pauses.
- Focus: the key thumbnail dismissed while key (✕, Esc, Delete) returns focus once and only once.
- Rule 12 and leaks: no closure held by a panel or view captures an entry or the model strongly.
- Strings: §5 character for character, including U+2026 and U+2605.
- Main thread: no file read, move, copy or trash on the main actor.
