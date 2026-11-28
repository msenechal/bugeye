# Wave 1 Quick Access ledger

Plan: `docs/plans/2026-11-28-wave-1-quick-access.md` · Spec: `docs/specs/2026-11-27-wave-1-quick-access.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, PR #3, `44a44d9`)

Trust this file and `git log` over memory.

## Slices

| Slice | Branch | PR | State |
|---|---|---|---|
| 1 core | `feat/wave1-quick-access-core` | #8 (draft) | done, awaiting review |
| 2 model | `feat/wave1-quick-access-model` | | in progress, stacked on #8 |
| 3 mac | `feat/wave1-quick-access-mac` | | |
| 4 wiring | `feat/wave1-quick-access-wiring` | | waits for Capture's wiring PR (contracts §9) |

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

## Waiting on

- Capture's wiring PR, for the wiring PR's merge, its Mac batch and the manual pass (contracts §9).

## Backlog

- Q12: a new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). Kept as documented.
