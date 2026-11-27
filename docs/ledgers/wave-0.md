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
| 4 | done | 75b8e5e | macos job on xcode-27; versions: pending first run |
| 5 | done | 365e2f4 | review workflow; guard caught the missing same-repo condition first; proof run waits on the Actions blocker |
| 6 | done | feb2072 |  |
| 7 | done | a2f5b94 | 6 BugeyeCore tests |
| 8 | done | fcc05fe |  |
| 9 | done | c671cfc |  |
| 10 | done | 490d43f |  |
| 11 | done | 8657d2b |  |
| 12 | done | 3d807f7 |  |
| 13 | done | b28a87b |  |
| 14 | done | d07226b |  |
| 15 | done | a641b6b |  |
| 16 | done | acf7f83 |  |
| 17 | done | 10ce7b0 |  |
| 18 | done | d2d4b92 | wire format against hand-written fixtures; facts re-checked with the claude-api skill |
| 19 | done | 25ad613 |  |
| 20 | done | 927d324 |  |
| 21 | done | 52c088e |  |
| 22 | done | 864231c |  |
| 23 | done | ebdc505 | not compiled here; waits on the macos job (blocked) |
| 24 | done | 7f8877a | not compiled here |
| 25 | done | 44bfe66 | not compiled here |
| 26 | done | 4d4f658 | not compiled here |
| 27 | done | 42c11a9 | not compiled here |
| 28 | done | c31f93a | not compiled here |
| 29 | done | 7a78313 |  |
| 30 | done | (this commit) | strings checked against spec and sources |

## Rulings

Every deviation from the plan, as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 0 reset the session's pre-existing local `feat/wave-0` (which held the spec and plan commits on top of `main`) to `origin/main` and copied the two files in, exactly as the plan's Step 1 does; the remote branch did not exist yet. (cost if wrong: none; the original commits stay on `claude/bold-davinci-spj824`.)
- Ruling: the draft PR was opened, and GitHub is read, through the session's GitHub MCP tools instead of `gh api`, because this cloud session only allows `gh` for search. Same request, same result. (cost if wrong: none.)

## Waiting on user

- Add `linux` and `macos` as required checks in the `main` ruleset once both are green (plan, "Steps only the user can do").

## Blockers

- Resolved, 27 Nov 2026 ~23:19 UTC, with no change from this session: every run from Task 15 (a641b6b) on starts and passes. Earlier commits (Tasks 3–14) have only `startup_failure` runs; their code is covered by the later green runs. Original note: every run of `linux` and `macos` from Task 3 to Task 14 ended in `startup_failure` with no jobs; the YAML parsed, `actions/checkout@v6` existed, and pinning it to a full SHA (88c74c2, reverted in 75b8e5e) changed nothing.
