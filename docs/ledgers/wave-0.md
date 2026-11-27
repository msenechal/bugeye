# Wave 0 ledger

Plan: `docs/plans/2026-11-27-wave-0-skeleton.md` · Spec: `docs/specs/2026-11-27-wave-0-skeleton.md` · Branch: `feat/wave-0` · PR: (link once opened)

Trust this file and `git log` over memory. Update it at the end of every task, and commit it with the task.

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 0 | done | ca06dd6 | |
| 1 | done | ea0a6ea | 14 portable test targets, 14 tests on Linux |
| 2 | done | 1fd390d | guards ok, test-guards ok (20 cases) |
| 3 | done | (this commit) | linux workflow; version guard caught 6.4.2 first |

## Rulings

Every deviation from the plan, as `Ruling: <what and why> (cost if wrong: …)`.

## Waiting on user

- Add `linux` and `macos` as required checks in the `main` ruleset once both are green (plan, "Steps only the user can do").

## Blockers

None yet.
