# Wave 1 Recording ledger

Plan: `docs/plans/2026-11-28-wave-1-recording.md` · Spec: `docs/specs/2026-11-27-wave-1-recording.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, `44a44d9`)

Trust this file and `git log` over memory.

## PRs

| Slice | Branch | PR | Status |
|---|---|---|---|
| 1 core | `feat/wave1-recording-core` | https://github.com/msenechal/bugeye/pull/4 (draft) | in progress |

## Tasks

| Task | Status | Commit | Notes |
|---|---|---|---|
| 1 | done | 6f29bb4 | draft PR #4 |
| 2–3 | done | 39c0163 | seen failing (compile) first |
| 4–5 | done | 501f5f1 | seen failing (compile) first; `millisecondsSurviveFloatingPointError` added later, seen failing |
| 6 | done | e02c6af | seen failing on the Bool decoding (see ruling) |
| 7 | done | bcc1fe8 | test and table written in one step (not seen failing first) |
| 8 | done | 1e9e43e | seen failing (compile), then 7 failures fixed: two test mistakes, one real (ms flooring) |
| 9 | done | 5317ab6 | written after the code: proven by two mutations (⌥ as a shortcut; secure element not withheld), each failing it, reverted |
| 10 | done | 51a23b4 | test and code written in one step |
| 11 | done | (see below) | fresh final review (subagent, no memory of writing): 0 Critical, 6 Important, 9 Minor. Fix pass in one commit with `TimelineRecorderEdgeTests`; the tests first failed to compile (new API), and the reviewer had reproduced I1–I4 in throwaway experiments before the fix |

## Final review of PR #4

- I1 a hung AX reader overlapped lookups → the reader call stays "in flight" until it really returns; later clicks are `skipped`; discard cancels it. Test `aReaderStuckPastItsDeadlineStillCountsAsInFlight`.
- I2 the cursor-rate filter dropped jittered samples → the gap is ¾ of the period (25 ms at 30 Hz). Test `aJitteredSamplerKeepsEverySample`. The earlier ruling's "cost: none" was wrong.
- I3 `finish` was re-entrant → input is refused from the start of `finish` (`acceptsInput`); `waitForLookup` loops. Test `inputDuringFinishIsRefused`.
- I4 a `trunc` could carry a late element line's earlier `t` → `trunc` uses the latest non-element `t`. Test `aTruncLineNeverGoesBackInTime`.
- I5 `startedAt` milliseconds now rounded by hand (no reliance on each platform's formatter); the Bool check and the date are verified by the `macos` job once the PR is ready (until then, unverified on Darwin).
- I6 tests added: late lookup after discard, write error (`/dev/full`), cursor cap falling through to size, pause flushing a scroll group.
- Minor fixed in the same pass: M1 (flush loop ends when the recorder is gone), M2 (header written at once), M3 (open clicks forgotten at pause), M4 (`AXElementInfo` fields `private(set)`; the `AXSecureTextField` subrole forces secure), M5 (timer cancelled when the reader answers), M7 (header `hasElements` false without a reader), M8 (gate wait bounded), M9 (dates without milliseconds read).
- claude-review on #4 (2703ee8): 0 Critical, 0 Important, 2 Minor, both fixed with a failing test first: (1) a decoded element line with the `AXSecureTextField` subrole kept its title: `TimelineElement`'s field initializer is now failable for that subrole and the reader writes `withheld`; (2) `TimelineStore.observe` deleted on the main actor: deletions now run detached, and `waitForDeletions` reports them done.
- claude-review on #4 (aabab8c): 0 Critical, 0 Important, 3 Minor, each fixed with a failing test first: (1) `MediaTime` and `RecordingClock.milliseconds` trapped on huge or NaN input (reproduced: a fatal error): both clamp now; (2) a header that can't be written didn't fail the recorder's creation: it throws now; (3) a text-entry element's title could be its typed value in some apps: dropped (see ruling).

## Rulings

Plan rulings P1–P8 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: the reader tells JSON `true`/`false` from numbers by `NSNumber.objCType == "c"`. On Linux, `value is Bool` and `as? Bool` also match the integers 0 and 1, which broke `version: 1`. (cost if wrong: low; Darwin's `__NSCFBoolean` is also `c`, checked by the `macos` job running the same tests.)
- Ruling: video-time milliseconds are `floor(seconds × 1000 + 0.001)` (`RecordingClock.milliseconds`): plain flooring turned 1000.15 − 1000 into 149 ms. (cost if wrong: none; a microsecond's allowance.)
- Ruling: `pause`, `resume` and `trunc` count as event lines in `end.events` ("the number of event lines": every line but the header and `end`). (cost if wrong: low; a reader can recount.)
- Ruling: the recorder also enforces the cursor rate (a `move` at least `1000 / cursorHz` ms after the last one) besides the 0.5 pt rule, so a faster sampler can't inflate the file. (cost if wrong: none.)
- Ruling: an `up` with no open `down` of its button is dropped (a press that began before the first frame or during a pause); `down`s of one button pair last-in first-out. (cost if wrong: low.)
- Ruling: every button's click gets an element lookup (left, right, other); `focus.window` and `focus.frame` may be `null` (an app with no window). (cost if wrong: low.)
- Ruling: `TimelineRecorder.waitForLookup()` is public: `finish` uses it, and tests use it instead of sleeping. (cost if wrong: none.)
- Ruling: the privacy test's "with `showAllKeys` on" is structural in slice 1: the timeline's API has no such switch, so the setting can't reach it. When `KeystrokeFormatter.label` lands (slice 3), the privacy test also asserts the badge labels the same typed presses with Show all keystrokes on, proving the two paths differ. (cost if wrong: low.)
- Ruling: a text-entry element (text field, area, combo box, search field) keeps no title in the timeline, only its role, subrole and frame: some apps put the typed value in AXTitle, and §7.4 forbids typed text. Captions lose a search field's name. (cost if wrong: low; Wave 3 captions can say "the text field".)
- Ruling: stacked branches take later fixes from the branch below by merging it in (no rebase): force-pushing was refused in this session. (cost if wrong: none; merge commits in a squash-or-merge PR.)
- Ruling (superseded by claude-review #4 minor 2): `TimelineStore.observe` now deletes off the main actor.

## Waiting on

## Backlog

- 2026-11-28, PR #4 review M6: `TimelineRecorder.init` creates the folder and file synchronously in the caller's context; the controller (slice 6) must create it off the main actor, or the recorder gains an async factory.
- 2026-11-28, PR #4 review I1: slice 4's `AXPointReader` must set `AXUIElementSetMessagingTimeout` (≤ 250 ms) and run off the cooperative pool.
