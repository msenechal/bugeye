# Wave 1 Recording ledger

Plan: `docs/plans/2026-11-28-wave-1-recording.md` · Spec: `docs/specs/2026-11-27-wave-1-recording.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, `44a44d9`)

Trust this file and `git log` over memory.

## PRs

| Slice | Branch | PR | Status |
|---|---|---|---|
| 1 core | `feat/wave1-recording-core` | https://github.com/msenechal/bugeye/pull/4 | ready, CI running |
| 2 flow | `feat/wave1-recording-flow` (stacked on core) | https://github.com/msenechal/bugeye/pull/13 (draft) | in progress |

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
| 12–14 | done | 64636ab | options, settings, `effectiveOptions`, strings, disk guard; seen failing (compile) first |
| 15 | done | dc5554d + next | `RecordingFlow`; table and regression tests seen failing (compile) first; the R1–R9 random-sequence test found one real bug (below) and fails on a planted one (dropping the countdown's `end(recordingSetup)`: 60 of 60 seeds) |
| 16 | done | (next) | `RecordingModule`, seen failing (compile) first |

## Final review of PR #4

- I1 a hung AX reader overlapped lookups → the reader call stays "in flight" until it really returns; later clicks are `skipped`; discard cancels it. Test `aReaderStuckPastItsDeadlineStillCountsAsInFlight`.
- I2 the cursor-rate filter dropped jittered samples → the gap is ¾ of the period (25 ms at 30 Hz). Test `aJitteredSamplerKeepsEverySample`. The earlier ruling's "cost: none" was wrong.
- I3 `finish` was re-entrant → input is refused from the start of `finish` (`acceptsInput`); `waitForLookup` loops. Test `inputDuringFinishIsRefused`.
- I4 a `trunc` could carry a late element line's earlier `t` → `trunc` uses the latest non-element `t`. Test `aTruncLineNeverGoesBackInTime`.
- I5 `startedAt` milliseconds now rounded by hand (no reliance on each platform's formatter); the Bool check and the date are verified by the `macos` job once the PR is ready (until then, unverified on Darwin).
- I6 tests added: late lookup after discard, write error (`/dev/full`), cursor cap falling through to size, pause flushing a scroll group.
- Minor fixed in the same pass: M1 (flush loop ends when the recorder is gone), M2 (header written at once), M3 (open clicks forgotten at pause), M4 (`AXElementInfo` fields `private(set)`; the `AXSecureTextField` subrole forces secure), M5 (timer cancelled when the reader answers), M7 (header `hasElements` false without a reader), M8 (gate wait bounded), M9 (dates without milliseconds read).
- claude-review on #4 (2703ee8): 0 Critical, 0 Important, 2 Minor, both fixed with a failing test first: (1) a decoded element line with the `AXSecureTextField` subrole kept its title: `TimelineElement`'s field initializer is now failable for that subrole and the reader writes `withheld`; (2) `TimelineStore.observe` deleted on the main actor: deletions now run detached, and `waitForDeletions` reports them done.

## Final review of PR #13 (slice 2)

Fresh reviewer: 1 Critical, 5 Important, 7 Minor. Each fix has a test in `RecordingFlowReviewTests` that was seen failing first (13 failures before the fix).
- C1 a Pause before the first frame dropped `takeStarted`: the timer read 00:00, Restart and Discard didn't ask, and delivery had no date. `takeStarted` in paused now starts the clock paused at the first frame. The writer (slice 5) follows the same rule.
- I1 losing Screen Recording mid-take posted an invented "Recording stopped / Screen Recording was declined." notice: it now stops the take and shows Capture's alert (§5.7).
- I2 the bubble's double-click size was refused once the bar closed: `option(.bubbleSize)` is taken from the countdown to the end of the take, saved, and kept across Restart.
- I3 the alert bookkeeping: an alert survives a pause; a second Restart or Discard while one is up is ignored; a take that ends another way emits `dismissConfirm(s)` (new effect).
- I4 the stale-ready cancel was dead code: a late `recorderReady` for any prepared session is cancelled again (idempotent in the shell), never for a stopped one. Found on the way: without that last rule, a late ready after Stop would cancel, and delete, a take being finished.
- I5 the invariant checker gained: stop-after-cancel and cancel-after-stop, a discarded take never delivered, a monotonic ● timer that doesn't move while paused, failure paths in the drain, no `Date()`. R1 per attempt is structural (leaving and returning alternate), noted rather than tested.
- Minor fixed: M1 (final punctuation, empty error), M2 (camera loss with Cam off is silent), M3 (`failedToStart` built explicitly), M7 (dead lines, table tests for quit, targetGone and restart from paused). `recordingHotkeyIsIgnoredDuringAScreenshotSelection` stays beside its twin: the spec names it.
- Minor as rulings or backlog: M4, M5, M6 below.

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
- Ruling (slice 2): `pause`, `resume`, `restart` and `discard` carry the host time they happened at (`hostNow`), so the ● timer freezes at the right moment and the 10 s confirmation rule needs no stale tick. (cost if wrong: none; the shell reads the host clock when the menu is chosen.)
- Ruling (slice 2): `toggle` carries `lastArea`, and `selected` carries the options, permissions and devices read when the selection returns, so the reducer stays pure and the bar shows fresh settings (§4). `permissionAnswered` updates them; `effectiveOptions` is recomputed at `record` (R8). (cost if wrong: low.)
- Ruling (slice 2): `bubble(BubbleWish?)` states the bubble the flow wants (camera, size) or none; the shell's `BubbleChange.decide` (slice 3) turns it into create / resize / recreate / remove against the live bubble. The bubble stays through a Restart's countdown (it is shown during set-up). (cost if wrong: low.)
- Ruling (slice 2): an extra event `conversionProgress(s, fraction)` drives the ● menu's `Finishing… <n> %`, which the spec's event list didn't have. The finishing entry's id is `recording.finishing` (disabled); the menu ids are `recording.pause|resume|stop|restart|discard`. (cost if wrong: none.)
- Ruling (slice 2): the reducer keeps the set of live recorders: each `prepareRecorder(s)` gets exactly one `stopRecorder(s)` or `cancelRecorder(s)` (R3), and a late `recorderReady` for a moved-on session is cancelled only if that session's recorder was never ended. The shell's `cancelRecorder` must also cancel a recorder still preparing. (cost if wrong: low.)
- Ruling (slice 2): bug found by the invariant test: with `recording.timeline` off, Stop emitted `timeline(finish)` for a timeline never started. The flow now tracks an open timeline and emits `finish` / `discard` only after a `start`. (cost if wrong: none.)
- Ruling (slice 2, review M4): a permission answer arriving after Record is ignored: the countdown records what was effective at Record (R8), and the next recording picks the new permission up. (cost if wrong: low.)
- Ruling (slice 2, review M5): `stopKey` stays a property the controller sets before each event; slice 6 tests that the ● menu's Stop shows the current binding after a change. (cost if wrong: low.)
- Ruling (slice 2, review I4): the shell's `cancelRecorder(s)` is idempotent and tears down a recorder still preparing; the reducer cancels a late ready for any prepared, unstopped session. (cost if wrong: low.)
- Ruling (slice 2, review C1): a take paused before its first frame starts paused: its clock begins and pauses at the first frame's host time. (cost if wrong: low.)
- Ruling (slice 2): disk thresholds are decimal (1 GB = 10⁹ bytes, 300 MB, 50 MB), as Finder shows free space. (cost if wrong: low; 7 % either way.)
- Ruling (slice 2): `cameraUnavailable` is handled from configuring to paused (the bubble shows during set-up): bubble removed, `recording.camera` false, notice. In configuring the bar updates too. (cost if wrong: none.)
- Ruling (slice 2): a stopped recording keeps its stop notice (disk full, failure) until delivery, then posts it after the `.mov` notice if any; "Nothing was recorded" replaces it when no frame was written. (cost if wrong: low.)
- Ruling (superseded by claude-review #4 minor 2): `TimelineStore.observe` now deletes off the main actor.

## Waiting on

## Backlog

- 2026-11-28, PR #13 review M6: no deadline on `stopping` / `delivering`. The controller (slice 6) guarantees `stopped` and `delivered` always arrive (a `defer`, as `design/04` §2.9), tested with a recorder that throws, so ⌘Q never waits forever.

- 2026-11-28, PR #4 review M6: `TimelineRecorder.init` creates the folder and file synchronously in the caller's context; the controller (slice 6) must create it off the main actor, or the recorder gains an async factory.
- 2026-11-28, PR #4 review I1: slice 4's `AXPointReader` must set `AXUIElementSetMessagingTimeout` (≤ 250 ms) and run off the cooperative pool.
