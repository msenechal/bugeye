# Wave 1 Quick Access ledger

Plan: `docs/plans/2026-11-28-wave-1-quick-access.md` · Spec: `docs/specs/2026-11-27-wave-1-quick-access.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, PR #3, `44a44d9`)

Trust this file and `git log` over memory.

## Slices

| Slice | Branch | PR | State |
|---|---|---|---|
| 1 core | `feat/wave1-quick-access-core` | #8 | green (linux, macos, review), ready to merge |
| 2 model | `feat/wave1-quick-access-model` | #10 | done, stacked on #8 |
| 3 mac | `feat/wave1-quick-access-mac` | #11 | macOS run pending, stacked on #10 |
| 4 wiring | `feat/wave1-quick-access-wiring` | | draft pushed; waits for Capture's wiring PR (contracts §9) |

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 5d15cd0 | |
| 2 | done | 71938f6 | |
| 3 | done | 0394a15 | |
| 4 | done | fab2308 | code written before the first red run; seen failing by moving the code aside, see ruling |
| 5 | done | 886777e | |
| 6 | done | d6b6db6 | |
| 7 | done | 49f39d3 | `QuickAccessModule`'s two specs landed here because the builder tests use them |
| 8 | done | fe9d77f | |
| 9 | done | ae58b1d | |
| 10–14 | done | 6bafdd5 | one commit: the tests of every rule were written first and seen failing to compile; two failures after the first run (a test literal; Delete after expiry, P7) fixed before commit |

## Rulings

Plan rulings P1–P18 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 4's `DismissTimer` code was written before its tests were first run; the tests were then seen failing (compile failure) with the file moved aside, and passing with it back. (cost if wrong: none.)
- Ruling: `QuickAccessFileResult.saved` carries the moved item and its `previousURL`, so the model publishes `saved` without recomputing the item; `QuickAccessFileActions.delete(_:using:)` is a static helper the controller calls with Trash (saved) or remove (temp), so "already gone counts as done" is tested on Linux although Trash is macOS-only. (cost if wrong: none.)
- Ruling: the unwritable-folder branch of P14 (`isWritableFile` false) has no Linux test: tests run as root in the `linux` job, where every folder is writable. The folder-is-a-file branch, which takes the same notice, is tested. (cost if wrong: low.)

- Ruling: the clock is a parameter of `handle(_:at:)`, not a field of each event (spec §6 lists `now` on some events only). Every event can change a timer (a dismissal empties the selection and restarts timers), so every event needs the time. (cost if wrong: none.)
- Ruling: P5 changed: the save folder comes from a `saveTarget` closure given at init and read at each Save, instead of riding on `stripTapped`. A Save from a decoration or the ⋯ menu needs it too, and the closure keeps "read fresh" in one place. `QuickAccessFileAction.save` still carries the folder and its display path. (cost if wrong: none.)
- Ruling: a failed Save, Save As… or Delete posts its notice even when the thumbnail went away meanwhile (§5.2 drops late results of gone entries; a failure the user caused shouldn't vanish silently). A late Copy result, success or failure, is dropped. (cost if wrong: low.)
- Ruling: a `deleted` event from another module while Quick Access's own Delete runs means Quick Access publishes no second `deleted` when its Delete finishes. Test failed first. (cost if wrong: none.)
- Ruling: Save As… tapped while its panel is open is ignored (P6 covers the panel's lifetime too), so one thumbnail never has two save panels. (cost if wrong: low.)
- Ruling: the `.selection` action runs only while its handler's state for the host is `enabled` or a submenu; `disabled` and `hidden` do nothing, as the builder greys or drops the button. (cost if wrong: low.)
- Ruling (final review of #8, M1, treated as Important): a paused `DismissTimer` is never expired. A timer that ran out between two 0.5 s ticks and was then paused by a hover, an editor or a selection banked a negative remainder and stayed expired, so the model's `tick` would have dismissed a thumbnail under the pointer. It now expires at the first tick after it resumes. Test failed first. (cost if wrong: none.)
- Ruling (final review of #8, M3): a primary whose handler answers `.submenu` is an enabled button that runs the action without a subitem (the strip has no submenus); a `.disabled` suggested action still gets its ring or ★, since the ring shows a habit, not availability. (cost if wrong: low; one line in the builder each.)
- Ruling (process, 28 Nov 2026): the final-review subagent for #8 ran a `git checkout` in the shared working tree while slice 3 was being committed, so the macOS commit (`d6391b0`) landed on the core branch and reached #8. Repaired without rewriting history: reverted on core (`8ad1c52`), merged up, and re-applied on the mac branch with a revert of the revert. Every later review agent runs in its own worktree (`isolation: worktree`). (cost if wrong: none; #8's history shows the commit and its revert, its diff is clean.)
- Ruling (final review of #10, I1, Important): every path that releases a thumbnail from `busy` (P6) now has a test: Cancel, the same file, `savedCopy`, `saveAsUnchanged`, `saveAsFailed`, `saved`, `saveFolderUnavailable`, `deleteFailed`, `deleted`, and a Save As… cancelled by `deleted`. Each was shown to fail by deleting that path's `busy.remove` line. (cost if wrong: none.)
- Ruling (final review of #10, M2, treated as Important): a finished Save takes only `fileURL` and `isSaved` from the result and publishes the entry's current item, so an `edited` that arrived while the move ran isn't lost (contracts §4.1.1: never publish a stale copy). Test failed first. (cost if wrong: none.)
- Ruling (final review of #10, M1 and M3): a Save As… cancelled by `deleted` releases `busy` when the panel answers; an `edited` preview arriving while the panel is open becomes the copy's preview. Tests failed first. M5's test gaps are filled (the same-file test now taps Save As… again; leaving a thumbnail that isn't key; Delete of the key thumbnail returns focus once). (cost if wrong: none.)

## Waiting on

- Capture's wiring PR, for the wiring PR's merge, its Mac batch and the manual pass (contracts §9).

## Backlog

- Final review of #10, M4 (28 Nov 2026): a `created` for an id whose panel is still fading out would show a new panel that the old `fadeOutFinished` then closes. Unreachable in Wave 1 (no publisher re-creates an id). Fix: ignore `created` while the id is fading, or close it first.
- Final review of #10, M6 (28 Nov 2026): `loggedDecorations` keeps one short string per capture that had a duplicate decoration; prune it on dismissal.

- Final review of #8, M2 (28 Nov 2026): `QuickAccessFileActions.run` is synchronous; only the controller's `Task.detached` keeps it off the main actor. Making it `@concurrent async` would enforce that in the type.
- Final review of #8, M4 (28 Nov 2026): small test gaps: a `.selection` handler answering `.hidden` or `.disabled`; a second `.suggestedAction` reported; Save As… of a recording; Save As… over an existing different file.

- Q12: a new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). Kept as documented.
