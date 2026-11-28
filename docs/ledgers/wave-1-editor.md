# Wave 1 Editor ledger

Plan: `docs/plans/2026-11-28-wave-1-editor.md` · Spec: `docs/specs/2026-11-27-wave-1-editor.md` · Contract: `docs/specs/2026-11-27-wave-1-contracts.md`

Trust this file and `git log` over memory.

## Pull requests

| Slice | Branch | PR | State |
|---|---|---|---|
| A executor | `feat/wave1-editor-executor` | | |
| B core | `feat/wave1-editor-core` | | |
| C app | `feat/wave1-editor-app` | | |
| D wiring | `feat/wave1-editor-wiring` | | |

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | | plan and ledger |

## Rulings

Plan rulings P1–P13 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: the contracts' §3 names were checked against `main` at `44a44d9` before the first PR (spec §9 item 1); all exist with the shapes the spec lists. (cost if wrong: none.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before slice D merges and before the manual pass (contracts §9).

## Backlog

Nothing yet.
