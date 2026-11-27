# Wave 0 ledger

Plan: `docs/plans/2026-11-27-wave-0-skeleton.md` · Spec: `docs/specs/2026-11-27-wave-0-skeleton.md` · Branch: `feat/wave-0` · PR: https://github.com/msenechal/bugeye/pull/2

Trust this file and `git log` over memory. Update it at the end of every task, and commit it with the task.

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 0 | done | ca06dd6 | |
| 1 | done | ea0a6ea | 14 portable test targets, 14 tests on Linux |
| 2 | done | 1fd390d | guards ok, test-guards ok (20 cases) |
| 3 | done | 37e074a | linux workflow; version guard caught 6.4.2 first |
| 4 | done | (this commit) | macos job on xcode-27; versions: pending first run |

## Rulings

Every deviation from the plan, as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 0 reset the session's pre-existing local `feat/wave-0` (which held the spec and plan commits on top of `main`) to `origin/main` and copied the two files in, exactly as the plan's Step 1 does; the remote branch did not exist yet. (cost if wrong: none; the original commits stay on `claude/bold-davinci-spj824`.)
- Ruling: the draft PR was opened, and GitHub is read, through the session's GitHub MCP tools instead of `gh api`, because this cloud session only allows `gh` for search. Same request, same result. (cost if wrong: none.)

## Waiting on user

- Add `linux` and `macos` as required checks in the `main` ruleset once both are green (plan, "Steps only the user can do").

## Blockers

None yet.
