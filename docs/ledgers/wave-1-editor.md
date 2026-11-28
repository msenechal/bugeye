# Wave 1 Editor ledger

Plan: `docs/plans/2026-11-28-wave-1-editor.md` · Spec: `docs/specs/2026-11-27-wave-1-editor.md` · Contract: `docs/specs/2026-11-27-wave-1-contracts.md`

Trust this file and `git log` over memory.

## Pull requests

| Slice | Branch | PR | State |
|---|---|---|---|
| A executor | `feat/wave1-editor-executor` | https://github.com/msenechal/bugeye/pull/7 | draft; final review done |
| B core | `feat/wave1-editor-core` | https://github.com/msenechal/bugeye/pull/14 | draft; final review done, fix pass below |
| C app | `feat/wave1-editor-app` | https://github.com/msenechal/bugeye/pull/18 | draft; final review done, fix pass below |
| D wiring | `feat/wave1-editor-wiring` | | |

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 065188c | plan and ledger; draft PR #7 |
| 2 | done | edd00d2, 12783ca | not compiled here; macOS run 46121444277 failed to compile a nested `#require` (fixed 12783ca); run 46121832947 green |
| A review | done | 9373695 | fresh final review: 0 Critical, 1 Important, 9 Minor; fix pass below; PR #7 marked ready |
| 3–4 | done | 009f641 | tests first, seen failing to compile |
| 5–7 | done | 55bb992 | tests first, seen failing to compile |
| 8 | done | 4244cc6 | tests first, seen failing to compile; passed at once after the code (see ruling) |
| 9 | done | 621cbe2 | one test expectation was wrong (σ = 10 boxes); see ruling |
| 10 | done | 2113672 | code written before its tests (see ruling); goldens recorded on Linux and checked by eye |
| 11–13 | done | 560aaa6 | tests first, seen failing to compile |
| 14–16 | done | 69d98c5 | tests written after the code (see ruling) |
| 17–21 | done | 3cb0e49, ed354f1 | not compiled here; macOS runs 46123425797 and the run on ed354f1 green; draft PR #18 |
| C review | done | (next commit) | fresh final review: 1 Critical, 6 Important, 10 Minor; fix pass below |

## Rulings

Plan rulings P1–P13 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: the contracts' §3 names were checked against `main` at `44a44d9` before the first PR (spec §9 item 1); all exist with the shapes the spec lists. (cost if wrong: none.)

- Ruling (final review A, Important 1): a probe test draws into a context set up like a flipped `NSView` (y down, at 1× and 2×) with `contextIsFlipped: true`: fill, image, text and shadow land the right way up, and the text matrix is restored. (cost if wrong: none.)
- Ruling (final review A, Minors 1, 2, 3, 4, 7): fixed in the fix pass because the executor's API freezes once merged (E11): `execute` restores the text matrix and text position; `contextIsFlipped` has no default, so a flipped caller can't forget it, and the doc states the list must span a y-up context's height; `render` returns nil for non-finite or over-65 536 px sizes and falls back to sRGB for a non-RGB or non-output space (tested); a `clip` outside a group is documented as ignored. (cost if wrong: none.)
- Ruling (final review A, Minor 5): the text probe keeps its loose width bound (ink between 0.8 × and the measured width + 1 px) instead of the plan's "within 1 px": ink bounds exclude the side bearings that `CTLineGetTypographicBounds` includes, so an exact match would test Core Text, not the executor. Font agreement is by construction: both call `CoreTextFonts.font(for:)`. (cost if wrong: low.)
- Ruling (final review A, Minor 8): the executor calls the blur provider synchronously; slice C's canvas provider returns a cached result or nil and computes off the main actor. (cost if wrong: none.)

- Ruling (slice B): the interaction controller's 37 tests and the sessions' 23 tests passed on their first run after the code. They were each written to the spec's rules before or with the code, and they were seen failing only at compile time. The renderer's and the sessions' code was drafted before their tests. Each test asserts spec values, not values read back from the code; the renderer goldens were checked by eye against §7's numbers (pad 96 at 2×, image origin 46, text baseline 154.4, group bounds + 32 px). (cost if wrong: low: a test that can't fail would show up as an always-green check in the final review.)
- Ruling (slice B, task 9): my first test expected `boxSizes(sigma: 10) == [19, 19, 19]`. The formula gives `[19, 19, 21]` (m = round(1.5) = 2), so I fixed the test, not the code. A separate test checks the gaussian against three naive box passes, byte for byte. (cost if wrong: none.)
- Ruling (slice B, E23): a Strong blur of a full 5K region (5120 × 2880, radius 30) takes 620 ms in a release build on this Linux x86 container, after moving to division-free, row-ordered passes (the first draft took 2.9 s). The user's Apple Silicon Mac should be about two to three times faster. The 300 ms threshold is checked in the manual pass (§9 J); if it's missed, E5's swap to Core Image applies. (cost if wrong: medium: a pause on large Strong blurs.)
- Ruling (slice B): golden JSON is compared as decoded `DisplayList` values, not as text, so float formatting can't differ between Linux and macOS. `BUGEYE_RECORD_GOLDENS=1` rewrites them; recording JSON goldens on Linux is allowed (E21 governs pixel goldens only). (cost if wrong: none.)
- Ruling (slice B): `EditorSessions` checks `fileExists` before a save. A file deleted in Finder, or a session marked gone by a `deleted` event, goes straight to the gone alert with no render; the writer's `TargetMissing` covers the race after the check (E19). (cost if wrong: none.)
- Ruling (slice B): a gone-file Save As writes with `attributesFrom:` the old URL (which no longer exists, so it contributes nothing) and `identity: .new(item.id)`. Provenance on the lost file can't be recovered. (cost if wrong: low; Wave 2's provenance would be missing on such a file.)
- Ruling (slice B): the text view's commit runs through `EditorHost.commitPendingEdits` at the start of save, Save As, copy, the drag file, close and quit, so the document holds the typed text before any of them reads it (§5.4). (cost if wrong: none.)
- Ruling (claude-review A, Important): nested group opacities now multiply. The executor keeps a stack of effective alphas, and an isolated group's children start again from 1 inside its layer, as Core Graphics resets alpha in a transparency layer. A nested group's shadow replaces its parent's for the drawing inside it (documented). Probe tests cover 0.5 inside 0.5 (non-isolated and isolated inner group) and an isolated parent. They can't be seen failing on Linux; the macOS job is the check. (cost if wrong: none.)

- Ruling (final review B, I1, Important): Save As… onto the capture's own file is a Save: `.keep`, `requireExisting: true`, `markSaved`, `edited`. It used to replace the capture's ID. Paths are compared standardised, with symlinks resolved. Test failed first. (cost if wrong: none.)
- Ruling (final review B, I2, Important): `didClose` marks the session closed. A save still running then shows no alert (gone or failed) and no retitle, and doesn't mark the closed document. If its write succeeds it still publishes `edited`, because the file did change and Quick Access's thumbnail should follow it; this amends plan P9, which said "only if still open". Tests failed first. (cost if wrong: low; an `edited` event after `editingEnded` for that capture.)
- Ruling (final review B, I3, Important): close and quit wait for a save in flight before deciding. If the save left the document clean, they ask nothing. Tests failed first. (cost if wrong: none.)
- Ruling (final review B, I4, Important): quit skips an editor that was closed while another editor's prompt was up. Test failed first. (cost if wrong: none.)
- Ruling (final review B, Minors 1, 3, 4, 6): fixed.
  - Minor 1: `applyFrame` makes each discrete frame edit (a fill swatch, the Shadow toggle) one step; slice C uses it.
  - Minor 3: a file put back at its path saves again, because a `deleted` flag only counts once the bus has also forgotten the capture.
  - Minor 4: neither events nor a second open reach the host while a capture is still loading.
  - Minor 6: the drag file throws `EditorSessionError.noEditor`.

  (cost if wrong: none.)
- Ruling (final review B, Minors 2, 5, 7): not changed in code.
  - Minor 2: the shell commits or cancels text before every tool change and mouse-down; the controller ignores clicks while an entry is open, so its side stays safe.
  - Minor 5: the missing tests came with the fixes above.
  - Minor 7: the `saved … in N ms` log line times the write only, not the render; §8.4 doesn't say which. The snapping hook lives in the controller only, because `EditorState` is a value and holds no closures (§8.3 says "keep a snapping hook").

  (cost if wrong: low.)

- Ruling (slice C): the canvas's blur provider returns a cached result or nil, and computes a miss off the main actor before redrawing (`BlurCache.imageOrSchedule`). A blur being drawn or resized shows the plain image for a moment until its result is ready. Exports compute synchronously, off the main actor. (cost if wrong: low; a brief flash of the unblurred region on the canvas only, never in an export.)
- Ruling (slice C): the prompts (`EditorPrompts`) are sheets on the editor's window, falling back to app-modal without one. Tests inject scripted answers. (cost if wrong: none.)
- Ruling (slice C): the text view is an `NSTextView` with zero inset and zero line-fragment padding, a private `UndoManager` per entry (⌘Z undoes typing only), and no smart quotes or dashes. ⌥Return arrives as `insertNewlineIgnoringFieldEditor:` and inserts a newline. (cost if wrong: low; E6's model-rendered text is the next step if the field and the render differ visibly.)
- Ruling (claude-review on #14, two Minors): fixed, with tests that failed first.
  - Every successful write publishes `edited`, even when a newer save is queued. A queued save that then writes nothing (it fails, or the gone alert is cancelled) used to leave Quick Access's preview stale. Only the latest save marks the document saved. This replaces plan P9's "one `edited` instead of two".
  - Save As does nothing once its window closed while the panel or the render was in progress.

  (cost if wrong: none; at most one extra `edited` event.)

- Ruling (final review C, core part):
  - I3: an editor has at most one unsaved-changes prompt at a time. A second close, or a quit, awaits the one already up instead of queueing another sheet.
  - I5: the render-failure message `The image couldn't be rendered.` is settled in `EditorStrings.renderFailed` and tested; the spec gave no text for it.
  - Edited dot: `EditorHost.documentSaved` tells the shell after every `markSaved`, so a save from the close or quit prompt, or a gone-file Save As, clears the dot.

  Tests failed first, at compile time for the new names. (cost if wrong: none.)

- Ruling (final review C, C1, Critical): ⌘Z, ⇧⌘Z and Edit ▸ Undo and Redo now reach the document. `NSWindow` answers `undo:` and `redo:` itself with its own empty undo manager, ahead of its delegate, so the canvas now answers and validates them: while typing they go to the text's undo manager, otherwise to the controller. A responder-chain test (`tryToPerform`) covers it; it can't be seen failing on Linux. (cost if wrong: none.)
- Ruling (final review C, Important):
  - I1: committing or cancelling text gives the canvas back its focus before the text view hides.
  - I2: opening an editor activates Bugeye every time.
  - I3: a second ⌘W while the close prompt is up doesn't start another; this works with the core's one-prompt-per-editor rule.
  - I4: the active annotation's blur comes from the cache only. The base is re-rasterised only when a blur it was drawn without is ready; a result that can't be computed never triggers a redraw.
  - I5: the render-failure message is the settled `EditorStrings.renderFailed`.
  - I6: added tests for the responder-chain undo, Return, Esc and ⌥Return with focus and the typing undo manager, the base-cache count, zoom through the clip view's bounds, Zoom to Fit after layout, the double-close guard, the edited dot after a save from a prompt, and a leak test that types while a second editor is open.

  (cost if wrong: none.)
- Ruling (final review C, Minors): fixed:
  - layout before Zoom to Fit;
  - the edited dot after every save (`documentSaved`);
  - `unmarkText` before a commit (IME);
  - the text view's min and max size, with spell checking and autocorrection off;
  - redraw only when the magnification changes;
  - focus back to the canvas after a tool change;
  - a logged fault if a window can't be shown.

  Not changed:
  - the drag handle's stale-task race. A stale result can only start a drag of an older render of the same capture during a later press; noted in the backlog.
  - the redundant ⌥Return check (harmless).

  (cost if wrong: low.)

- Ruling (macos run 46124668545): that run failed on the contract test `DebugChannelTests.answersTheWaveOneCommandsOnTheMainActor`, which got no answer within its 5 s timeout. The cause was I2's `NSApp.activate()` in `show()`. Activating the unbundled test runner stalled its main thread on the hosted runner: `saveKeepsTheIDAndTheOtherAttributes` went from 0.29 s to 8.25 s and starved the debug channel, which answers on the main thread. Activation is now injected into `EditorManager` (`NSApp.activate()` in the app, a counter in tests). The opening test checks that every editor activates, not only the first. The contract test is unchanged. (cost if wrong: none.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before slice D merges and before the manual pass (contracts §9).

## Backlog

- Executor tests: a non-isolated group's single-fill alpha, line joins, a vertical gradient (final review A, Minor 6).
- Drag handle: cancel the export on mouse-up and ignore a stale result by generation (final review C, Minor).
