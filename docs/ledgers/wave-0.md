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
| 14 | done | (this commit) |  |

## Rulings

Every deviation from the plan, as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 0 reset the session's pre-existing local `feat/wave-0` (which held the spec and plan commits on top of `main`) to `origin/main` and copied the two files in, exactly as the plan's Step 1 does; the remote branch did not exist yet. (cost if wrong: none; the original commits stay on `claude/bold-davinci-spj824`.)
- Ruling: the draft PR was opened, and GitHub is read, through the session's GitHub MCP tools instead of `gh api`, because this cloud session only allows `gh` for search. Same request, same result. (cost if wrong: none.)

## Waiting on user

- Add `linux` and `macos` as required checks in the `main` ruleset once both are green (plan, "Steps only the user can do").

## Blockers

- **GitHub Actions never start on this repository.** Every run of `linux` and `macos` since Task 3 (push and pull_request, e.g. https://github.com/msenechal/bugeye/actions/runs/46081329952) ends in `startup_failure` at once, with no jobs and no log. The YAML parses, `actions/checkout@v6` exists, and pinning it to a full SHA (88c74c2, reverted in 560011d) changed nothing, so the cause is a repository or account setting this session can't read: check Settings → Actions → General (Actions enabled, "Allow all actions", no SHA-pinning or allow-list policy that excludes `actions/checkout` / `anthropics/claude-code-action`), and the account's Actions billing / spending limit. Until it is fixed, no CI result exists for any task, and Task 5's review proof can't run. The portable tasks continue, verified locally.
