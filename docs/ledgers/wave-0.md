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
| 30 | done | 4d933c3 | strings checked against spec and sources |
| 31 | done | (this commit) | PR description rewritten; PR marked ready; five claude-review rounds: every Critical/Important fixed with a failing test (or ruled and asked, Keychain); last round no Critical or Important. `linux`, `macos`, `review` green on 0f8d1aa. |

## Rulings

Every deviation from the plan, as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: Task 0 reset the session's pre-existing local `feat/wave-0` (which held the spec and plan commits on top of `main`) to `origin/main` and copied the two files in, exactly as the plan's Step 1 does; the remote branch did not exist yet. (cost if wrong: none; the original commits stay on `claude/bold-davinci-spj824`.)
- Ruling: the draft PR was opened, and GitHub is read, through the session's GitHub MCP tools instead of `gh api`, because this cloud session only allows `gh` for search. Same request, same result. (cost if wrong: none.)
- Ruling: `Sources/BugeyeFixture/main.swift` imports `BugeyeTestSupport`. The plan's file used `FixtureContent` while importing only AppKit and SwiftUI; Xcode 27.2 (Swift 6.4) doesn't let a file use a module only another file imports (`macos` run 46082154668: `main.swift:12:20: error: cannot find 'FixtureContent' in scope`). A scan of every macOS-only file found no other gap. (cost if wrong: none; one import line.)
- Ruling (source: the user, 27 Nov 2026, relayed by the parent session and then asked directly): CI never runs on draft pull requests. `linux`, `macos` and `claude-review` trigger on `pull_request` to `main` (opened, synchronize, reopened, ready_for_review) with the job skipped while the PR is a draft, on `push` to `main` (linux, macos) and on `workflow_dispatch`; `linux` no longer runs on every feature-branch push (it ran twice per push before). Every workflow has a concurrency group per PR or ref with cancel-in-progress. This replaces spec §7's triggers (updated in the spec, CLAUDE.md and the execute-plan skill), P19's "review drafts when opened" and P22's "no concurrency group on macos". `scripts/guards.sh` now fails a pull-request workflow without the draft condition or a concurrency group (self-test cases added first, seen failing). While a PR is a draft, `make test-core lint guards` here is the check and pushes are batched; the PR is marked ready when the `macos` job is needed. Why: 116 runs from 26 commits in about 8 minutes. (cost if wrong: low; a draft push now gets no CI signal until the PR is ready, and draft pushes still list a skipped run each.)
- Ruling: the ~35 `startup_failure` runs (linux, macos, claude-review) all belong to commits pushed between 23:14 and 23:19 UTC (Tasks 3–14). Their workflow files were complete and valid; the identical files started normally from 23:19 on with no change from this session, so the cause was on GitHub's or the repository's side at the time, not in the workflows. None has happened since. (cost if wrong: low; the next run on the head would show it.)
- Ruling (review finding, Important): the key test now waits at most 15 s per attempt (`AIKeySettings.testTimeout`), so a stalled connection shows "Couldn't reach Anthropic." in under a minute instead of up to three 600 s tries. `LLMRequest.timeout` (default nil) is carried through `TransportRequest.timeout` to `URLRequest.timeoutInterval`; nil keeps the transport's 600 s default for real generation. Tests failed first. (cost if wrong: low; 15 s may be short on a very slow network, one constant.)
- Ruling (review finding, Minor, fixed with it): `LLMError.refused` maps to the "refused" status and `.truncated` to "Key works." instead of "Couldn't reach Anthropic.": Anthropic answered in both. Unreachable from `testKey` today (it calls `send`, which doesn't throw them), so this only keeps the mapping honest. Tests failed first. (cost if wrong: none.)
- Ruling (review finding, Minor): `scripts/guards.sh` ignores YAML comment lines when checking workflows, so a condition written only in a comment no longer passes. Full YAML parsing per job is in `docs/backlog.md`. Self-test cases failed first. (cost if wrong: low; a weakened `||` branch in code could still pass.)
- Ruling (second review, Important): `AnthropicClient` treats `URLError(.cancelled)` (what URLSession throws for a cancelled task) like `CancellationError`: `.transport("cancelled")` at once, never retried. Test `aCancelledRequestIsNotRetried` failed first. (cost if wrong: none.)
- Ruling (second review, Minor): saving a key while a test runs ends that test's busy state, and the stale test no longer clears the flag of the test that replaced it, so "Test key" works on the new key at once. Test `aNewKeyCanBeTestedWhileAnOldTestIsStillRunning` (with a per-call `SequencedLLM`) failed first and passed 20 runs in a row. (cost if wrong: low.)
- Ruling (second review, Minor): a manual `claude-review` run checks out `refs/pull/<pr>/head`, so the agent reads the PR's tree as its prompt says. Dispatch needs write access. (cost if wrong: low.)
- CI facts: the `macos` runner selects `/Applications/Xcode_27.2.app` (SDK MacOSX27.2), Swift 6.4 (checked by `select-xcode.sh`). First fully green `macos` run: aef1566.
- Ruling (third review, Important, part 2): a Keychain write that fails changes nothing: the status keeps describing the stored key, instead of claiming "Key saved. Not tested yet." for a key that wasn't stored. The spec has no "couldn't save" line, so none is shown; a new line is proposed under Waiting on user. Test `aFailedSaveOverAnOlderKeyDoesNotClaimTheNewOneWasSaved` failed first. (cost if wrong: low; the user gets no visible error on a failed save until a string is approved.)
- Ruling (third review, Important, part 1, not changed): `SecretStore` stays synchronous and `AIKeySettings` calls it on the main actor in Wave 0. Making it async changes the port, its fake, the Keychain adapter, the AI pane and the SwiftUI view. The item is a generic password the app itself created, signed with the stable "Bugeye Dev" identity, so reads and writes normally return at once without a prompt; the risk is a locked login keychain or an access prompt blocking the UI. Logged in `docs/backlog.md` and asked of the user. (cost if wrong: medium; the Settings pane can freeze while the Keychain waits on a prompt.)
- Ruling (third review, Minor, not changed): `CaptureFileWriter` doesn't keep the original's POSIX mode and doesn't fsync before the rename. Both are known limits of P11 (Review Focus #3); logged in `docs/backlog.md` for the final review. (cost if wrong: low.)
- Ruling (fourth review, Important): `RetryPolicy` compares a `retry-after` against the 60 s cap as a `Double` before converting it, so a huge or infinite header (`1e300`, `inf`) means "give up" instead of trapping in `Int64(_:)` and crashing the app. The parameterized test `anEnormousRetryAfterMeansGiveUpWithoutCrashing` crashed the test process first. (cost if wrong: none.)
- Ruling (sixth review, Important, security): a manual `claude-review` run first looks up the PR's head repository (`gh api … --jq .head.repo.full_name`) and stops unless it is this repository, so a fork's PR can't reach the agent or the token through `workflow_dispatch` (spec W6). The PR number input is typed `number` and reaches the script through `env:`, never interpolated. `scripts/guards.sh` now fails a workflow that runs the agent on a manual run without that check; its self-test case failed first. (cost if wrong: low; a manual run of a fork PR is refused instead of reviewed.)

## Waiting on user

- Decide on the third review's Keychain finding: move Keychain calls off the main actor in Wave 0 (an async `SecretStore`), or leave it for a later wave (current ruling). And approve a status line for a failed save, for example "Couldn't save the key to the Keychain." (spec §5.3 settles every string).

- Done by the user, 27 Nov 2026: `oven-sh/setup-bun@*` allowed; the `review` job on b810686 ran and posted its review (Task 5's proof; the `CLAUDE_CODE_OAUTH_TOKEN` secret works).

- Add `linux` and `macos` as required checks in the `main` ruleset once both are green (plan, "Steps only the user can do").

## Blockers

- Resolved, 27 Nov 2026 ~23:19 UTC, with no change from this session: every run from Task 15 (a641b6b) on starts and passes. Earlier commits (Tasks 3–14) have only `startup_failure` runs; their code is covered by the later green runs. Original note: every run of `linux` and `macos` from Task 3 to Task 14 ended in `startup_failure` with no jobs; the YAML parsed, `actions/checkout@v6` existed, and pinning it to a full SHA (88c74c2, reverted in 75b8e5e) changed nothing.
