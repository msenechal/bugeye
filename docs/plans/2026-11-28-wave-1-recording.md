# Wave 1 Recording: plan

**Goal:** build the Recording epic (`docs/specs/2026-11-27-wave-1-recording.md`, approved 28 Nov 2026) on the merged Wave 1 contracts (`docs/specs/2026-11-27-wave-1-contracts.md`, `44a44d9` on `main`), as several small PRs to `main`, one per slice.
**Ledger:** `docs/ledgers/wave-1-recording.md` (rulings, `Waiting on:`, `Backlog:`). Commit trailers: the session's Co-Authored-By and Claude-Session lines.
**Branches:** `feat/wave1-recording-<slice>` (contracts K24), each cut from `main` (or stacked on the previous slice's branch while it awaits merge, rebased once it lands).
**PRs:** each opens as a draft after its first push. While it is a draft, `make test-core lint guards` is the check and pushes are batched (R10). It is marked ready when it needs the `macos` job or is done; a fresh final review of the PR and one fix pass for Critical / Important follow before the user is told it is ready to merge.
**Process:** written and executed by the same session without approval (`design/14` R11). Ambiguities are decided and ledgered as `Ruling:` with their cost if wrong.

## Facts checked

- Swift 6.4.3 on Linux here, the same as `.swift-version` and the `linux` job.
- `RecordingCore` depends on `BugeyeCore` and `BugeyeFeatures`; its test target has `Fixtures/` as a resource folder (`Package.swift`, no manifest edit needed).
- Recording-owned paths (contracts §3): `Sources/Core/RecordingCore/`, `Tests/RecordingCoreTests/`, `Sources/BugeyeCore/Ports/{Recording,Accessibility}/`, `Sources/BugeyeCore/Timeline/`, `Tests/BugeyeCoreTests/{Recording,Accessibility,Timeline}/`, `Sources/BugeyeTestSupport/{Recording,Accessibility}/`, `Tests/BugeyeTestSupportTests/{Recording,Accessibility}/`, `Sources/Mac/MacAdapters/{Accessibility,Permissions}/`, `Tests/MacAdaptersTests/{Accessibility,Permissions}/`, `Sources/BugeyeApp/Recording/`, `Sources/BugeyeApp/Wiring/RecordingWiring.swift`, `Tests/BugeyeAppTests/Recording/`, `docs/*wave-1-recording*`.
- Contract names used, as merged: `SelectionRequest`/`SelectionResult`/`StoredArea`/`AreaSelector` (`Selection/AreaSelector.swift`), `ScreenActivity.Activity.{recordingSetup,recording}` and `.startRecording`, `StatusItemOverride` (`BugeyeFeatures`), `CaptureFolders.{recordingsInProgress,applicationSupport,temp}`, `CaptureEventBus` (main actor), `CaptureItem.duration`, `KeyCombo`, `HotkeySpec`, `MenuItemSpec(hotkeyID:)`, `SettingsSectionSpec`, `DisplayID`, `WindowID`, `AXElementInfo` and `AXReader` in `Ports/Accessibility/AXReader.swift` (moved unchanged, Recording-owned).

## Plan rulings

- **P1 — The plan lists tests and shapes, not every line of code** (as the contracts plan's P1): the same session writes and executes it at once, the spec fixes every public shape, and each test is seen failing before its code. (cost if wrong: low.)
- **P2 — Slices and merge order.** (1) `core`: the timeline, clock, `MediaTime`, AX fields, `MediaPermissions`, the base-key table and the privacy test. (2) `flow`: `RecordingFlow`, options, settings, strings, disk guard, module. (3) `layout`: geometry, bar placement, window follow and child windows, bubble layout, keystroke badge and click rings as display lists, take recovery. (4) `adapters`: `AXPointReader`, `SystemMediaPermissions`. (5) `recorder`: `StreamRecorder`, `MovieConverter`, `FirstFrame`, devices, disk space, input translation. (6) `windows`: border, options panel, countdown, bubble, pane, status override, `RecordingController`. (7) `overlay`: the overlay window through the Editor's executor, after the Editor's executor PR (K10). (8) `wiring`: `RecordingWiring.modules` + `install`, the `recording.state` debug command, after Capture's and Quick Access's wiring PRs (contracts §9), with `needs-mac-check` and a `CLAUDE.md changes` block. Slices 1–3 are portable and checked on Linux; 4–8 are macOS and checked by the `macos` job. (cost if wrong: low; slices can merge or split.)
- **P3 — `TimelineKey(key:modifiers:)` takes the key already reduced to its base** (`"S"`, `"3"`, `"Return"`), and validates it against §7.4; `KeystrokeFormatter.baseKey(keyCode:characters:)` (RecordingCore) does the reduction for both the badge and the timeline. The rule lives in the `BugeyeCore` type, so a later caller can't bypass it. (cost if wrong: low.)
- **P4 — The timeline's line encoder is hand-written** (fixed key order, one-decimal coordinates printed without a trailing `.0`, `t` as an integer); decoding uses `JSONSerialization` and re-runs the type initializers. `JSONEncoder` doesn't promise key order. (cost if wrong: none.)
- **P5 — `TimelineRecorder` keeps `t` non-decreasing** by clamping a line's `t` to the last written `t` (an input event captured just after a pause stamp can reach the actor before the pause call). Element lines keep their click's `t`. (cost if wrong: low; at most a few ms of skew on one event.)
- **P6 — Scroll coalescing:** a group starts at a scroll's `t`; scrolls within 100 ms of the group's first join it; any other line, a later scroll, a flush or `finish` writes the group at its first `t` and the last scroll's position. (cost if wrong: low.)
- **P7 — Size limits are injectable** (`TimelineLimits`, defaults 48 MiB / 64 MiB / 4 KiB) so the cap tests write kilobytes, not megabytes. (cost if wrong: none.)
- **P8 — The element lookup timeout races the reader against `Task.sleep`**; tests use a short timeout and `FakeAXReader`'s scripted delay, and a gate (`FakeAXReader.Gate`) to hold a lookup in flight for `skipped`. `finish` waits for an in-flight lookup (bounded by the timeout) so its line comes before `end`. (cost if wrong: low.)

## Steps only the user can do

- Merging each PR (never merged by this session).
- The Mac batch on the wiring PR (`needs-mac-check`, spec §9 item 4) and the manual pass (§9 item 5). Ledgered as `Waiting on user` when reached; work continues.

## Tasks

Each code task: write the tests, run `swift test --filter <Suite>` and see them fail (a compile failure on new names counts), write the code, see them pass, then `make test-core lint guards`. macOS tasks can't compile here: test and code go together and the `macos` job is the result.

### Slice 1 — `feat/wave1-recording-core`

1. **Plan, ledger, draft PR.**
2. **`AXElementInfo` gains `subrole` and `isSecure` (§3.1, V3).** `Sources/BugeyeCore/Ports/Accessibility/AXReader.swift`. Tests (`Tests/BugeyeCoreTests/Accessibility/AXReaderTests.swift`): `isSecure: true` forces `title` and `text` nil; old call sites compile (default `subrole: nil`, `isSecure: false`). `FakeAXReader` gains `delay: Duration` and an optional `Gate` (tests release it); self-tests in `Tests/BugeyeTestSupportTests/Accessibility/`.
3. **`MediaPermissions` (§3.1).** `Sources/BugeyeCore/Ports/Recording/MediaPermissions.swift`; `FakeMediaPermissions` (`Sources/BugeyeTestSupport/Recording/`): scripted states, `request` returns the scripted answer and records the call. Self-test.
4. **`MediaTime`.** `RecordingCore/MediaTime.swift`: `00:00`, `00:07` from 7.9, `12:34`, `59:59`, `1:00:00`, `1:02:03`, negatives and NaN → `00:00`.
5. **`RecordingClock` (V6, `design/04` §2.8).** Host seconds → output time with paused spans removed: nil before start and for a sample captured inside a pause (even after resume); `elapsed(at:)` frozen while paused; `milliseconds(at:)` for the timeline; a second `pause` while paused and a `resume` while running are no-ops.
6. **The timeline schema (§7.2, §7.4).** `Sources/BugeyeCore/Timeline/EventTimeline.swift`: `TimelineModifier` (`ctrl opt shift cmd`, ordered), `TimelineKey(key:modifiers:)` (nil unless §7.4 holds), `TimelineElement(info:origin:)` (nil for secure; title trimmed to 120 with `…`; frame relative to origin), `TimelineElement(role:subrole:title:frame:)`, `TimelineHeader`, `TimelineLine` (every kind), `TimelineLineEncoder` (fixed key order), `TimelineReader` (skips unknown kinds and keys, refuses an unknown version, drops a partial last line, re-runs the initializers), `EventTimeline.url(for:home:)`. Tests in `Tests/BugeyeCoreTests/Timeline/`: each kind's exact line text against §7.2; header text; round trip; `{"k":"key","key":"h","mods":[]}` dropped; `⇧A`, `⌥A`, `A` refused; `⌘S`, `⌃C`, `⇧⌘3`, `Return`, `Left`, `⌘Space`, `F12` accepted; `Space` alone refused; secure element nil.
7. **`KeystrokeFormatter.baseKey` (§5.4).** `RecordingCore/KeystrokeFormatter.swift`: the US base table by key code, the number row as digits, non-Latin letters as the US letter of the key, named keys (`Return` … `F12`, `Space`). Tests on US, AZERTY, German and Russian characters for the same key codes. (`label` and the badge come in slice 3.)
8. **`TimelineWriter` and `TimelineRecorder` (§7.1–7.3).** `RecordingCore/TimelineRecorder.swift`, `TimelineWriter.swift`: input events (`move`, `down`, `up`, `scroll`, `key`, `focus`, `area`) with host time; clock mapping; 30 Hz/0.5 pt move filter; ids pairing; scroll coalescing (P6); element lookups (P8) with `withheld`, `none`, `timeout`, `skipped`; caps (`trunc cursor`, `trunc size`, `end` always fits); `pause`/`resume` lines; `end` with duration and event count; buffered appends, `flush`, `fsync` at `finish`; `discard` deletes the file. Tests: every kind; sampling; coalescing; caps and `end` after a cap; a crash-truncated file reads back without its partial last line.
9. **The privacy test and the random-press property test (§7.4, V4).** `Tests/RecordingCoreTests/TimelinePrivacyTests.swift`, exactly as §7.4 lists, through `TimelineRecorder` and the file's bytes.
10. **`TimelineStore` (V5).** `RecordingCore/TimelineStore.swift`: moves a take's timeline to `Timelines/<CaptureID>.timeline.jsonl`, deletes it on a `deleted` event for a `.recording` item, ignores other kinds; discard deletes a take's timeline.
11. **Final review, fix pass, ready.**

### Slice 2 — `feat/wave1-recording-flow`

12. **Options and settings (§4, §5.2).** `RecordingOptions`, `RecordingSettings` (read with fallbacks, write one key), `effectiveOptions(options, permissions, devices)`.
13. **Strings (§4–§5).** `RecordingStrings`, every string character for character.
14. **`DiskGuard`.** 1 GB to start, 300 MB to stop, movie + 50 MB to convert; the conversion deadline (60 s + half the duration).
15. **`RecordingFlow` (§6).** States, events, effects, the table; the status override built from `MediaTime` and the current ⇧⌘5 binding; invariants R1–R9 as random-sequence tests; the seven named regressions.
16. **`RecordingModule`.** Menu item, hotkey spec, settings section (§3.1 Registrations).

### Slice 3 — `feat/wave1-recording-layout`

17. `RecordingGeometry` (output size, codec limits, even sizes, bitrate). 18. `OptionsBarPlacement`. 19. `WindowFollow`, `ChildWindowFilter`. 20. `BubbleLayout`, `BubbleChange`. 21. `KeystrokeFormatter.label`, `KeystrokeBadge`, `ClickRings` display lists (golden JSON). 22. `TakeRecovery`.

### Slices 4–8 (macOS)

Described in P2; each gets its own task list in this file when it starts, from spec §8 and §9 item 2's macOS list.

## Review Focus

- Typed text: any path from a key press or an AX element into the timeline that doesn't pass through `TimelineKey` / `TimelineElement` initializers.
- `t` ordering around pause/resume and the first frame; element lines written after `end` (must not happen).
- The size caps: `end` must always be written and the file must stay under the hard cap.
- Stale-session events in the reducer; every `prepareRecorder` paired with exactly one stop or cancel.
