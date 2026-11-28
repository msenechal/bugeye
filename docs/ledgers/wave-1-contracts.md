# Wave 1 contracts ledger

Plan: `docs/plans/2026-11-28-wave-1-contracts.md` · Spec: `docs/specs/2026-11-27-wave-1-contracts.md` · Branch: `feat/wave1-contracts` · PR: https://github.com/msenechal/bugeye/pull/3 (draft)

Trust this file and `git log` over memory. Contract amendments (K2) add their ruling here only (K39).

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | f3d095d | draft PR #3 |
| 2 | done | ecfe15d | self-test 17 cases, seen failing with no script |
| 3 | done | 13b7499 | |
| 4 | done | 8169678 | tests and code written in one step (not seen failing first); both checked by hand, see ruling |
| 5 | done | dd7cdf5 | 19 new writer tests, seen failing on the missing names |
| 6 | done | 6bc2f63 | |
| 7 | done | 8730927 | |
| 8 | done | f0c51af | golden JSON generated from the encoder and checked by eye |
| 9 | done | 76a2234 | |
| 10 | done | 5c1fbc1 | no fake had a test to move; the AX test moved to `Tests/BugeyeCoreTests/Accessibility/` |
| 11 | done | 703ff4c | |
| 12 | done | f0d64fa | |
| 13 | done | 3afd498 | |
| 14 | done | b0ae2f6 | |
| 15 | done | 6f13356 | |
| 16 | done | dbb19cd | |
| 17 | done | 21c049a | |
| 18 | done | 4df3302 | |
| — | done | 0611edf | `DocumentWindows(onUnderflow:)`, see ruling |
| 19 | done | 5ad916c | not compiled here; macOS run 46092621392 found a missing `import Foundation` (fixed ad1fd82) |
| 20 | done | 1a02357 | not compiled here |
| 21–22 | done | b4e36a4 | not compiled here; macOS run 46092736765 failed one test (`performActionForItem` needs a running NSApp), fixed 7b34a14 |
| macOS | green | 7b34a14 | manual run https://github.com/msenechal/bugeye/actions/runs/46092982896: build, all tests, bundle, release symbols |

## Rulings

Plan rulings P1–P14 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: the branch was cut fresh from `origin/main` (`a82a783`) and the six Wave 1 specs and `design/14` copied from `claude/bold-davinci-spj824` at `8192f4a`, as instructed. (The local checkout showed a stale `origin/feat/wave1-contracts` ref at `8192f4a`; the first push created the remote branch, so nothing was overwritten.) (cost if wrong: none; those commits stay on `claude/bold-davinci-spj824`.)

- Ruling: Task 4's namer and folder tests were written together with their code instead of being run red first. The expected strings come from the spec, the fixed date was converted by hand (27 Nov 2026 14:03:12 Paris = 1 795 784 592 s), and every later task ran its tests red first. (cost if wrong: low; a test that can't fail would show as an always-green check, and each assertion here compares against a spec literal.)
- Ruling: `MainMenu` (the type, its fixed table and `shellItemIDs`) landed with Task 11, not Task 15, because `FeatureRegistry` needs the shell's ids for `duplicateMainMenuItem` (plan P8); `MainMenu.entries` and its table test stayed in Task 15. Each main-menu key is a `KeyCombo` constant in `ShellStrings` next to its title, as §4.2.5 asks. (cost if wrong: none.)
- Ruling: `ThumbnailDecorations` and `CaptureEventRecorder` capture `self` weakly in their bus subscriptions, so neither keeps itself alive through the bus. (cost if wrong: none.)
- Ruling: the debug `registered` lookup returns a `@MainActor (String) -> String`, so an epic's command runs on the main actor like the built-ins. (cost if wrong: none.)

- Ruling: `DocumentWindows.init` gains `onUnderflow: @MainActor () -> Void = {}` (additive, default empty). K37 says the shell logs a fault on an underflow, but §4.2.6's shape gave the shell no way to see one; `AppContext` passes a closure that logs it. Test failed first. (cost if wrong: none; one defaulted parameter.)
- Ruling: `UserNotificationNotifier()` uses the system center only for an `.app` bundle with a bundle id, not merely "a bundle id": under `swift test` the runner can have an id without an app bundle, and `UNUserNotificationCenter` traps there. (cost if wrong: low; a bundled Bugeye is always an `.app`.)
- Ruling: `AppServices.init` throws `LaunchError` (`.conflicts` or `.duplicates(router:settingsPanes:debugCommands:)`) instead of `FeatureRegistryError`, and takes an `extraInstall` closure (tests only) so the duplicate-id launch failures can be tested while every wiring is empty. It also takes `requestNotificationAuthorization`, which `AppDelegate` calls at launch, because `AppContext.notifier` is the port, not the adapter. (cost if wrong: none.)
- Ruling: `MenuBarController` draws through a `StatusItemDisplay` protocol (the real one wraps `NSStatusItem`), so the override's badge, label, menu and restore are tested without a status item, as §4.5 asks. (cost if wrong: none.)
- Ruling: the `macos` job was reached with manual `workflow_dispatch` runs on the branch while the PR was a draft (CLAUDE.md allows it), so `claude-review` didn't re-run on every compile fix. (cost if wrong: none.)

## Waiting on user

Nothing yet.

## Backlog

Nothing yet.
