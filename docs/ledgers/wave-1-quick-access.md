# Wave 1 Quick Access ledger

Plan: `docs/plans/2026-11-28-wave-1-quick-access.md` · Spec: `docs/specs/2026-11-27-wave-1-quick-access.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, PR #3, `44a44d9`)

Trust this file and `git log` over memory.

## Slices

| Slice | Branch | PR | State |
|---|---|---|---|
| 1 core | `feat/wave1-quick-access-core` | #8 | final review done, fix pass done |
| 2 model | `feat/wave1-quick-access-model` | | |
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

## Rulings

Plan rulings P1–P18 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 4's `DismissTimer` code was written before its tests were first run; the tests were then seen failing (compile failure) with the file moved aside, and passing with it back. (cost if wrong: none.)
- Ruling: `QuickAccessFileResult.saved` carries the moved item and its `previousURL`, so the model publishes `saved` without recomputing the item; `QuickAccessFileActions.delete(_:using:)` is a static helper the controller calls with Trash (saved) or remove (temp), so "already gone counts as done" is tested on Linux although Trash is macOS-only. (cost if wrong: none.)
- Ruling: the unwritable-folder branch of P14 (`isWritableFile` false) has no Linux test: tests run as root in the `linux` job, where every folder is writable. The folder-is-a-file branch, which takes the same notice, is tested. (cost if wrong: low.)

- Ruling (final review of #8, M1, treated as Important): a paused `DismissTimer` is never expired. A timer that ran out between two 0.5 s ticks and was then paused by a hover, an editor or a selection banked a negative remainder and stayed expired, so the model's `tick` would have dismissed a thumbnail under the pointer. It now expires at the first tick after it resumes. Test failed first. (cost if wrong: none.)
- Ruling (final review of #8, M3): a primary whose handler answers `.submenu` is an enabled button that runs the action without a subitem (the strip has no submenus); a `.disabled` suggested action still gets its ring or ★, since the ring shows a habit, not availability. (cost if wrong: low; one line in the builder each.)

## Waiting on

- Capture's wiring PR, for the wiring PR's merge, its Mac batch and the manual pass (contracts §9).

## Backlog

- Final review of #8, M2 (28 Nov 2026): `QuickAccessFileActions.run` is synchronous; only the controller's `Task.detached` keeps it off the main actor. Making it `@concurrent async` would enforce that in the type.
- Final review of #8, M4 (28 Nov 2026): small test gaps: a `.selection` handler answering `.hidden` or `.disabled`; a second `.suggestedAction` reported; Save As… of a recording; Save As… over an existing different file.

- Q12: a new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). Kept as documented.
