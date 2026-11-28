# Wave 1 Recording ledger

Plan: `docs/plans/2026-11-28-wave-1-recording.md` · Spec: `docs/specs/2026-11-27-wave-1-recording.md` · Contracts: `docs/specs/2026-11-27-wave-1-contracts.md` (merged, `44a44d9`)

Trust this file and `git log` over memory.

## PRs

| Slice | Branch | PR | Status |
|---|---|---|---|
| 1 core | `feat/wave1-recording-core` | https://github.com/msenechal/bugeye/pull/4 | ready, CI running |
| 2 flow | `feat/wave1-recording-flow` (stacked on core) | https://github.com/msenechal/bugeye/pull/13 (draft) | in progress |
| 3 layout | `feat/wave1-recording-layout` (stacked on flow) | https://github.com/msenechal/bugeye/pull/16 (draft) | in progress |
| 4 adapters | `feat/wave1-recording-adapters` (stacked on core) | https://github.com/msenechal/bugeye/pull/17 (draft) | manual macos run 46123514479 green |
| 5 recorder | `feat/wave1-recording-recorder` (stacked on layout) | https://github.com/msenechal/bugeye/pull/22 (draft) | macos run 46124727052 failed to build (NSLock in async code), fixed |
| 6 controller | `feat/wave1-recording-controller` (stacked on recorder) | (draft) | in progress |

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
| 17–20 | done | 5ad0136 | geometry, placement, follow, child windows, fallback, bubble; seen failing (compile) first |
| 21–22 | done | (next) | label, badge, rings (goldens generated, checked by hand: badge 94 × 38 pt at (353, 522) for "⇧ ⌘ 3"; rings at half and full alpha), take recovery; seen failing (compile) first. The privacy test gained `theBadgeShowsWhatTheTimelineNeverWrites` |

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

## Final review of PR #16 (slice 3)

Fresh reviewer: 0 Critical, 3 Important, 16 Minor. Fixed in one commit with `LayoutReviewTests` and `TakeRecoveryReviewTests` (new API names first failed to compile; the new behaviours were checked failing by their assertions on the old code paths the reviewer reproduced).
- I1 `ChildWindowFilter` mixed global window frames with a display-local rect: the parameter is now `followedGlobal`, with `WindowFollow.global(_:displayBounds:)`; tested on a display at (1512, −200).
- I2 the V23 fallback reset its count on every filter update (10 Hz) so it could never fire: only a delivered frame resets it; "dropped" is documented as a blank or suspended frame, `.idle` counts as delivered.
- I3 a recovered movie could hold no fragment: movies under 64 KiB are deleted with their timeline.
- Minor fixed: orphan timelines are left alone (1); a recovered `.mp4` takes its timeline's time (2); files changed in the last 10 s are left alone (4); `convertedName` / `timelineName` (5); recovery ordering and live-take tests (6); the self-exclusion test (7); edge tests (8); doc comment (10); too-wide bar and badge clamp to the left edge (11); Apple function-key characters and multi-letter uppercases (13); opacity rounded to 0.001 (14).
- Minor deferred to Backlog: 3, 15, 16. Minor 9 and 12 are rulings below.

## Final review of PR #17 (slice 4)

Fresh reviewer: 0 Critical, 2 Important, 4 Minor. Fixed in 83888b0; `macos` green (run 46126223265).
- I1 a text field's AXTitle or AXDescription can be what was typed: text-entry and secure elements get no title read at all (`AXPointReader.info` and the read path), tested with "hunter2".
- I2 the messaging timeout was per message, so a lookup could take several times 250 ms: one deadline for the whole lookup, the budget re-set before each message, attributes in two `AXUIElementCopyMultipleAttributeValues` calls.
- Minor fixed: M1–M4 (search-field subrole, injectable trust and deadline, a deadline test, test names).

## Final review of PR #22 (slice 5)

Fresh reviewer: 1 Critical, 8 Important, 11 Minor. Fixed in a935da2 and its follow-up (the first `macos` run trapped in the converter's new progress code: `Int(NaN)` for a sample without a time; fixed at its root).
- C1 `cancel()` during `prepare` left a live stream: an `isCancelled` flag set in `detach`, checked by the install step (`installIfLive`) and after `startCapture`; `prepare` throws `.cancelled`. Tested at the install seam.
- I1 writer failures are reported once through `MovieWriter.onFailure` to the recorder's failure latch.
- I2 a still screen starts the take: the last complete frame is cached and written at the first `.idle` frame after `arm()`. Tested with synthetic status attachments.
- I3 audio retiming shifts every timing entry and keeps per-sample durations; a 1 s take has 1 s of audio (test).
- I4 a window gone before Record throws `.noWindow` instead of recording the display.
- I5 filter updates are chained and generation-checked; the fallback starts counting only once the filter applied.
- I6 the converter's deadline is hard (an unstructured job raced against a timer, first result wins); reader and writer are registered only after `startWriting`; an aborted job's `.mp4` is deleted when it ends. Tested with a pump blocked for 2 s against a 300 ms deadline.
- I7 tests: 30 frames dropped in the pause and read back; one `process(_:of:)` for the delegate and tests; idle, blank and started statuses; pause and resume stamps and `noFrames` through `StreamRecorder`.
- I8 `InputMonitor.resendFocus()` (the controller calls it when the timeline starts) and `didActivateApplicationNotification`.
- Minor fixed: all of M1–M11 (stop stamped in `detach`; callbacks on the main queue in order; `MovieWriter.Failure` is `LocalizedError`; one window list per tick with `followedGlobal`; whole-percent progress; `now` injected; `displaySize` removed; frame statuses named; `HostClock`; Bugeye's own focus skipped; test renamed; the session starts only with a frame the input takes).

## Final review of PRs #23, #24 and #25 (slices 6–8)

Fresh reviewer: 1 Critical and 7 Important (6 on #23, 1 on #24), and minors.
- #23 C1 a recorder cancelled while preparing was never stopped: when `prepare` returns, the controller cancels it if it is no longer the session's recorder (with the recorder's own C1 fix, `prepare` also throws `.cancelled`). Tested with a held `prepare`.
- #23 I1 `areaMoved` checks the session, and the border is red only in recording or paused.
- #23 I2 a followed window's latest rect (clamped like the stream's) is the target's frame for the border, overlays, bubble, countdown, restart and the timeline header.
- #23 I3 Stop and the preview are raced against `stopDeadline` (10 s); a throw or a timeout falls back to the fragments rule, with the asset's duration (backlog M6 done). Tested with a recorder that throws and one that never returns.
- #23 I4 + PR #22's controller note: the timeline gets everything through one ordered `AsyncStream` consumer; pause and resume stamps that come before the timeline exists are replayed into it, clamped to its start.
- #23 I5 the options bar lays out before reading `fittingSize` and is placed again after SwiftUI's pass.
- #23 I6 tests: cancel while preparing, stale and countdown window moves, a throwing and a hanging stop, a display with a negative origin.
- #24 I7 the ring's area point is tested on two displays (one with a negative origin), and the timer's self-stop on an empty last frame; `windowIDs` only while the window is shown.
- #25 minors: recovery skips this instance's live takes and deletes off the main actor; the checklist's corrections (branch note, Accessibility re-read, the ● menu's Stop, bubble cycle, no " (2)" by hand, no unquoted log line).
- Minors deferred to Backlog below.

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
- Ruling (slice 4): `AXPointReader` runs each query on a GCD queue with `AXUIElementSetMessagingTimeout(0.25)`, reads only AXRole, AXSubrole, AXTitle, AXDescription, AXPosition and AXSize, and treats text field, text area, combo box and search field as text entry. macOS has no "not determined" for Accessibility: untrusted reads as denied. (cost if wrong: low.)
- Ruling (slice 5): the writer takes a pause asked before the first frame as "start paused": the first frame is written at 0 and nothing more until the resume (same rule as the flow's C1 fix). (cost if wrong: low; one frame.)
- Ruling (slice 5): a line-based scroll wheel's deltas are multiplied by 10 to approximate points; precise (trackpad) deltas are points already. (cost if wrong: low; Wave 3 scales scrolls anyway.)
- Ruling (slice 5): host time is the CoreMedia host clock (what ScreenCaptureKit stamps); input uses `NSEvent.timestamp` and `systemUptime`, the same mach-based clock. Checked in the Mac batch's item 5 (a click's `t` matches its ring's frame within 50 ms). (cost if wrong: medium; a constant offset in the timeline.)
- Ruling (slice 6): `RecordingDelivery` is portable (writer, namer, bus, decorations, ports, `TimelineStore`) and tested on Linux; file moves run off the main actor. (cost if wrong: none.)
- Ruling (slice 6): a writer that fails at stop leaves its 2 s fragments: the take is delivered as a `.mov` when at least 64 KiB is there (`TakeRecovery.minimumMovieBytes`), else "Nothing was recorded". (cost if wrong: low.)
- Ruling (slice 6): the controller's countdown, ticker, sampler and focus timers run in `.common` modes; tests drive ticks as events and never wait on the run loop. (cost if wrong: none.)
- Ruling (slice 6): the overlay window is a protocol (`OverlayPresenting`) the controller already calls; slice 7 implements it with the Editor's executor, and until then the controller runs with no overlay (so V2's exception windows are just the bubble). (cost if wrong: none.)
- Ruling (slice 3): the codec limit applies to the long and short sides (H.264 4096 × 2304, HEVC 8192 × 4320), so a portrait display is limited to 2304 × 4096, not squeezed into a landscape box. (cost if wrong: low.)
- Ruling (slice 3): the source rect grows to whole points (floor the origin, ceil the far edges), then is clamped into the display; at least 2 × 2 pt. (cost if wrong: none.)
- Ruling (slice 3): bar placement: centred on the selection and kept on the screen horizontally; "inside the bottom edge" puts the bar 12 pt above the selection's (or screen's) bottom. (cost if wrong: low; the Mac batch shows it.)
- Ruling (slice 3): the rings' "14 → 28 pt" are diameters; ease-out is quadratic; left is systemYellow (1, 0.8, 0), right systemPink (1, 0.176, 0.333), other buttons don't ring. (cost if wrong: low; a constant.)
- Ruling (slice 3): the badge's padding is 14 × 8 pt; its text uses the semibold weight 0.3 (contracts' font mapping). (cost if wrong: low.)
- Ruling (slice 3): the badge shows named keys only with ⌘ or ⌃ unless Show all keystrokes is on (↩ alone is typing a newline). (cost if wrong: low.)
- Ruling (slice 3): take recovery also delivers an `.mp4` left without its `.mov` (a crash after a finished conversion) and deletes a partial `.mp4` beside its `.mov` and a timeline whose movie is gone. (cost if wrong: low.)
- Ruling (slice 3, revised after review I2): the child-window fallback (V23) counts blank or suspended frames after a filter update until a frame is delivered (complete or idle); more than 2 in a row drops back to the window alone for the rest of the take. (cost if wrong: low.)
- Ruling (slice 3, review minor 9): sheets and popovers that the window server lists at layer 0 aren't caught by the child filter (V10 names sheets); the Mac batch's item 4 opens a sheet as well as a menu to see it. (cost if wrong: low; a sheet missing from a window recording.)
- Ruling (slice 3, review minor 12): an area partly off its display is shifted inside it, not cropped, so the size stays what was selected (and a followed window keeps its size). (cost if wrong: low.)
- Ruling (slice 3, review I3): a leftover movie under 64 KiB holds no complete fragment and is deleted with its timeline rather than delivered broken. (cost if wrong: low; at most the first second of a crashed take.)
- Ruling: a text-entry element (text field, area, combo box, search field) keeps no title in the timeline, only its role, subrole and frame: some apps put the typed value in AXTitle, and §7.4 forbids typed text. Captions lose a search field's name. (cost if wrong: low; Wave 3 captions can say "the text field".)
- Ruling: stacked branches take later fixes from the branch below by merging it in (no rebase): force-pushing was refused in this session. (cost if wrong: none; merge commits in a squash-or-merge PR.)
- Ruling (fix pass, PR #22 C1): `StreamRecorder.Failure` gains `.noWindow` ("The window to record isn't available.") and `.cancelled`; both reach the flow as `.other(...)` like the others. (cost if wrong: none; a cancelled session's failure is ignored by the reducer.)
- Ruling (fix pass, PR #22 I1): the writer-failure test stands in for a full disk through `MovieWriter.reportFailure`; detecting `.failed` is one status check read on every append. (cost if wrong: low; the Mac batch can fill a disk image.)
- Ruling (fix pass, PR #23 I3): the stop deadline is 10 s; past it the take is delivered from its fragments (or nothing) while the stuck stop keeps running unobserved. (cost if wrong: low; a slow finish loses at most its last 2 s fragment.)
- Ruling (fix pass, PR #23 I4): inputs that arrive before the timeline exists are dropped (they precede its origin); only pause and resume stamps wait for it. (cost if wrong: none.)
- Ruling (fix pass, PR #22 M9): one `HostClock.now()` for the sampler, the focus watcher and the recorder; the overlay's animation clock stays `systemUptime` (it only measures its own durations). (cost if wrong: none.)
- Ruling (superseded by claude-review #4 minor 2): `TimelineStore.observe` now deletes off the main actor.

## Waiting on

## Backlog

- 2026-11-28, PR #16 review minor 3: a take kept after "Couldn't save the recording" would be "recovered" at the next launch with "Bugeye quit while recording". The controller (slice 6) marks such takes (e.g. `Take-<uuid>.undelivered`) and recovery skips or words them differently.
- 2026-11-28, PR #23 review minors: the countdown's Esc by `keyDown` 53 in the test; drive the Recording pane's binding in its test; the notice's folder from `GeneralSettings.displayedFolder`; a `NoFreeName` delivery test (V24); `pixelsPerPoint` from the stream's pixel scale; the timeline's `end` at Stop's host time; §8 log details (`converted in` ms, `discarded <take>`, unknown disk); a confirm for a session already over is not shown; events raised during `execute` queued, not nested; the bubble corner reset on `.create`.
- 2026-11-28, PR #25 review minors: the wiring tests drive quit through `context.termination` and recovery's delete list, quiet period and timeline move.

- 2026-11-28, PR #4 review M6: `TimelineRecorder.init` creates the folder and file synchronously in the caller's context; the controller (slice 6) must create it off the main actor, or the recorder gains an async factory.
- 2026-11-28, PR #4 review I1: slice 4's `AXPointReader` must set `AXUIElementSetMessagingTimeout` (≤ 250 ms) and run off the cooperative pool.
