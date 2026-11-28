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
| 9 | done | (this push) | written after the code: proven by two mutations (⌥ as a shortcut; secure element not withheld), each failing it, reverted |
| 10 | done | (this push) | test and code written in one step |

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
- Ruling: `TimelineStore.observe` deletes on the main actor: one `unlink` of a small file, not slow I/O. (cost if wrong: low.)

## Waiting on

## Backlog
