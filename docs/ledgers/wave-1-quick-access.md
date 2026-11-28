# Wave 1 Quick Access ledger

Plan: `docs/plans/2026-11-28-wave-1-quick-access.md` · Spec: `docs/specs/2026-11-27-wave-1-quick-access.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, PR #3, `44a44d9`)

Trust this file and `git log` over memory.

## Slices

| Slice | Branch | PR | State |
|---|---|---|---|
| 1 core | `feat/wave1-quick-access-core` | | in progress |
| 2 model | `feat/wave1-quick-access-model` | | |
| 3 mac | `feat/wave1-quick-access-mac` | | |
| 4 wiring | `feat/wave1-quick-access-wiring` | | waits for Capture's wiring PR (contracts §9) |

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | (this commit) | |

## Rulings

Plan rulings P1–P18 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

## Waiting on

- Capture's wiring PR, for the wiring PR's merge, its Mac batch and the manual pass (contracts §9).

## Backlog

- Q12: a new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). Kept as documented.
