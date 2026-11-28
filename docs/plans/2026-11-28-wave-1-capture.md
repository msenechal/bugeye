# Wave 1 Capture: plan

**Goal:** implement the Wave 1 Capture epic: full screen, every display, area and window captures, the selection overlay as a portable state machine with one owner, the `AreaSelector` for Recording, output (save, copy, announce), the temp janitor, the Screen Recording alert, the Carbon registrar, the Shortcuts pane and the Capture pane, then wire it.
**Spec:** `docs/specs/2026-11-27-wave-1-capture.md` (approved 28 Nov 2026), on the merged contracts (`docs/specs/2026-11-27-wave-1-contracts.md`). Where this plan and the specs differ, the specs win unless a ruling below or in the ledger says otherwise.
**Branches:** `feat/wave1-capture-<slice>` from `main`, one draft PR per slice (§ Slices). Later slices stack on earlier ones; each targets `main` and says which PR it builds on.
**Ledger:** `docs/ledgers/wave-1-capture.md`. Backlog items go there under `Backlog:` (K39). Commit trailers: the session's Co-Authored-By and Claude-Session lines.
**Process:** written and executed by the same session without approval (`design/14` R11). Ambiguities are decided and ledgered as `Ruling:` with their cost if wrong. While a PR is a draft, `make test-core lint guards` is the check and pushes are batched (R10). macOS-only tasks are reached through the `macos` job (a manual `workflow_dispatch` run on the branch, or the PR marked ready).

## Facts checked

- Toolchain here: Swift 6.4.3 on Linux, matching `.swift-version` and the `linux` image.
- The contracts PR (#3) is on `main` (`44a44d9`). Every name of Capture spec §3 exists: `CaptureEventBus`, `CaptureItem`, `CaptureEvent.previewMaxWidth`, `CaptureFileWriter.create`, `CaptureFileNamer`, `CaptureFolders.temp`, `OutputSettings`, `OutputStrings`, `Notifier`, `ScreenCapturePermission`, `WindowID`, `PixelBufferImages` (macOS), `AreaSelector`, `SelectionRequest`, `SelectionResult`, `StoredArea`, `AreaSelectorRelay`, `ScreenActivity`, `FakeAreaSelector`, `HotkeySpec.title`, `MenuItemSpec.hotkeyID`, `HotkeyBindings`, `KeyCombo(description:)`, `ActionRouter`, `SettingsLayout.shortcutsPane`, `CaptureWiring`, `AppContext` (`router`, `settingsPanes`, `screenRecordingAlert`, `areaSelector`, `screenActivity`, `hotkeyStatus`, `captureEvents`, `debugCommands`, `onLaunch`, `retain`), `AppContext.testing`, and the moved `ScreenSource` / `FakeScreenSource`.
- `BugeyeTestSupport` sees only `BugeyeCore` (K18): every Capture port and fake uses `BugeyeCore` types only. `KeyCombo` is in `BugeyeFeatures`, so the registrar port takes its own `GlobalKey` value (P4).
- `CaptureCore` depends on `BugeyeCore` and `BugeyeFeatures` (`Package.swift`), so `CaptureModule` and the controller can use `KeyCombo`, `HotkeySpec` and `ActionRouter`-free logic; `BugeyeFeatures/Shortcuts/` can use the registrar port.
- `scripts/guards.sh` forbids Apple frameworks, `Darwin` and `os` in portable targets: the portable controller logs through a `CaptureShell` callback, not `os.Logger`.
- Nothing else uses `ScreenSource` or `FakeScreenSource` (grep), so reshaping them breaks no other epic.

## Plan rulings

- **P1 — The plan lists shapes and tests, not every line.** As in the contracts plan (its P1): the same session writes and executes it at once (R11); code is drafted in the branch with each test seen failing first, and the committed code is the reviewable artefact. (cost if wrong: low.)
- **P2 — Most of the controller is portable.** Spec §7 puts the `AreaSelector` implementation in `BugeyeApp`. Here `CaptureController` (in `CaptureCore`, `@MainActor`) owns `CaptureFlow`, performs every effect through ports and one `CaptureShell` protocol (overlays, key, beep, app activation, alert, logging), runs the output order, and implements `AreaSelector`. `BugeyeApp/Capture/` holds only the overlay windows and views (which render the controller's `OverlayState` and translate `NSEvent`s into flow events) and the `CaptureShell` adapter. So I1–I9, the selector rows and the output order are tested end to end on Linux, and Recording's selector contract lands in the first PRs. (cost if wrong: low; it moves code from a macOS folder to a portable one Capture also owns.)
- **P3 — Frozen frames cross the port as `CapturedImage`**, a `Sendable` value with `pixelWidth`, `pixelHeight` and an opaque `storage: any Sendable` (a `CGImage` box on macOS, a `PixelBuffer` in fakes). The core never reads pixels from it except through `ImagePipeline.pixelBuffer` (window shadow) and `preview` (C7). (cost if wrong: low.)
- **P4 — `HotkeyRegistrar` takes a `GlobalKey`** (`key` character, four modifier booleans) because ports can't see `KeyCombo` (K18). `BugeyeFeatures/Shortcuts/` converts. Bare Esc is `GlobalKey.escape`. (cost if wrong: none.)
- **P5 — View events carry the display id and a view-local point** (bottom-left, points, the overlay view covers the display frame). The flow converts to display-local (top-left) and to Quartz for the window hit test. (cost if wrong: none.)
- **P6 — Selector answers carry a ticket.** `select` gets a ticket; `answer(ticket, result)` effects resolve exactly that call, so a `.busy` answer never resolves the running selection (I9). (cost if wrong: none.)
- **P7 — Full-screen kinds deliver in one effect:** `deliver(session, [Delivery])` in display order (primary first, then `ScreenSource` order), delivered sequentially so `create` suffixes ` (2)`, ` (3)` in that order; one `delivered` event returns the notices. (cost if wrong: none.)
- **P8 — The size readout and loupe are positioned by `SelectionGeometry` in display-local points;** the readout sits off the selection's bottom-right corner (top-left coordinates: `maxX + 8`, `maxY + 24`). Damage rects from the flow are old ∪ new selection, outset by the 1 pt border; the view adds its old and new label frames (it measures the text). (cost if wrong: low; a visual detail for the manual pass.)
- **P9 — ⇧ lock:** when ⇧ is down and the selection has width and height, the ⇧ point is the pointer at that moment; once the pointer is more than 2 pt from it, the axis that moved less since then is locked at the ⇧ point's value until ⇧ is released. (cost if wrong: low.)
- **P10 — Touch Bar models for C13** (entry 181 missing counts as on): `MacBookPro13,2`, `13,3`, `14,2`, `14,3`, `15,1`–`15,4`, `16,1`–`16,4`, `17,1`, `Mac14,7`. A missing entry 28–31 or 184 counts as on with its default key. (cost if wrong: low; checked in the Mac batch, §9.4.5.)
- **P11 — Temp janitor in three steps** (C28): list files older than 24 h with their identity xattr (off the main actor), drop those whose id the bus still knows (main actor, hourly purge only), delete the rest (off the main actor). (cost if wrong: none.)

## Steps only the user can do

- The Mac batch on the wiring PR (`needs-mac-check`, contracts §9): real ScreenCaptureKit, permission, the old app's keys, `symbolichotkeys` numbers. Needed after the wiring PR is ready; until then the session continues and ledgers `Waiting on user`.
- Merging each PR, in order.

## Slices (one PR each)

| # | Branch | Content | Platform |
|---|---|---|---|
| 1 | `feat/wave1-capture-core` | Plan, ledger; Capture ports and fakes; coordinate types; `SelectionGeometry`; `WindowHitTest`; `WindowShadow`; `CaptureFlow` with I1–I9 and the selector rows | Linux |
| 2 | `feat/wave1-capture-controller` | `CaptureSettings`, `CaptureStrings`, `LastAreaStore`, `OutputRouter`, `TempJanitor`, `CaptureModule`, `CaptureController` (implements `AreaSelector`, holds `ScreenActivity`), the Shortcuts model | Linux |
| 3 | `feat/wave1-capture-mac` | `MacAdapters/Capture/`: ScreenCaptureKit source, window list, ImageIO pipeline, Carbon registrar, `symbolichotkeys` reader | macOS CI |
| 4 | `feat/wave1-capture-app` | `BugeyeApp/Capture/` overlay windows and views, shell adapter, alert and relaunch, Capture pane; `BugeyeApp/Shortcuts/` pane view and registrar wiring; not yet wired | macOS CI |
| 5 | `feat/wave1-capture-wiring` | `CaptureWiring.modules` and `install`, purge timer, debug commands; `needs-mac-check`; `CLAUDE.md changes` block; manual checklist | macOS CI + Mac batch |

## Tasks

Each code task: write the tests, run `swift test --filter <suite>` and see them fail (a compile failure on the new names counts), write the code, see them pass, then `make test-core lint guards`. Tasks marked **macOS** can't compile here: test and code are committed together and the `macos` job is the result.

### Slice 1

1. **Plan, ledger, draft PR.**
2. **Ports (C8)** in `Sources/BugeyeCore/Ports/Capture/`: `ScreenSource` (`displays()`, `freeze(displays:)` → `[FrozenDisplay]`, `captureWindow(_:pixelSize:)` → `CapturedImage`), `ScreenSourceError` (`permissionDenied`, `displayNotFound`, `windowNotFound`, `failed(String)`), `CapturedImage`, `FrozenDisplay`; `WindowInfo` + `WindowListReader` (front to back, Quartz bounds); `ImagePipeline` (crop, downscale, PNG, pixel buffer, preview); `GlobalKey` + `HotkeyRegistrar`; `SymbolicHotkey` + `SystemShortcutReader`. Fakes in `Sources/BugeyeTestSupport/Capture/` with self-tests in `Tests/BugeyeTestSupportTests/Capture/`: `FakeScreenSource` counts `freeze` calls (one fetch per freeze) and can fail or delay; `FakeWindowListReader`; `FakeImagePipeline` (crops `PixelBuffer` storage, records calls, can fail encoding); `FakeHotkeyRegistrar` (taken keys, live registrations, `press(id)`); `FakeSystemShortcutReader`.
3. **Coordinates (§4)** `Sources/Core/CaptureCore/Geometry/Coordinates.swift`: `CocoaPoint/CocoaRect`, `QuartzPoint/QuartzRect`, `ViewPoint/ViewRect`, `DisplayPoint/DisplayRect`, `PixelRect`; bridges `toQuartz(primaryHeight:)`, `toCocoa(primaryHeight:)`, `displayLocal(displayHeight:)`, `pixelRect(scale:imageWidth:imageHeight:)`. Tests: round trips, negative-origin displays left of and above the primary, 1×/2×/mixed, outward rounding, intersection with the image, nil below 1 px.
4. **`SelectionGeometry`**: drag rect from anchor and current (from-centre, axis lock, clipped to the display), `isCapturable` (≥ 4 × 4), `loupeFrame` (120 pt, 20 pt below-right, flips, stays on screen), `loupeSample` (15 × 15 slid inside the image, marker offset), `readoutFrame` (P8), `readoutText` (`W × H`, rounded).
5. **`WindowHitTest`**: `topmost(at:in:excludingPID:)` (layer 0, alpha > 0, another pid, front-to-back), `display(containingCentreOf:frames:)`.
6. **`WindowShadow`**: `body(in:)` (alpha ≥ 128, ¼ ½ ¾, agree within 2 px, else nil) and `atFullScale(windowSize:scale:capture:measure:)` (one recapture when `body.width / window.width < scale × 0.99`). Synthetic squeezed images.
7. **`CaptureFlow`** (§6, §6.1): states, events, effects; every row of both tables as a named test; the five regression tests by name; I1–I9 as a property test over random event sequences (seeded generator); selector rows for `.recording` requests.

### Slice 2

8. **`CaptureSettings`, `CaptureStrings`, `LastAreaStore`**: keys and defaults of §5.7; every string of §5 character for character; `capture.lastArea` JSON round trip, bad JSON ignored.
9. **`OutputRouter`** (§5.4): save → copy → item; folder unusable (missing and not creatable, a file, `NoFreeName`) → temp + notice with the `~/…` path; saving off → temp; temp write fails → clipboard PNG alone + notice, no item; copy off variants; names via `CaptureFileNamer`.
10. **`TempJanitor`** (C11, C28, P11).
11. **`CaptureModule`**: ids, titles, orders, hotkey ids and setting keys of §5.1 and §5.7; pane spec `Capture` order 10.
12. **`CaptureController`**: performs the flow's effects; `request(kind)`; `select` / `cancel` (`AreaSelector`); `ScreenActivity.screenshotSelection` held exactly while a screenshot job is out of `idle`; output order and the `created` event (origin `capture`, preview ≤ 480 px); downscale; notices; Esc hotkey through the registrar; `OverlayState` for the views. Tests with every fake, end to end.
13. **Shortcuts model** (`BugeyeFeatures/Shortcuts/`): `ShortcutStrings`; `ShortcutConflicts` (C13, P10); `ShortcutsModel` (register all, typed combo, Esc keeps, Delete clears, duplicate and invalid messages, Try Again, Restore Defaults, row message priority, registration callback for `HotkeyStatus`); launch notices with the `A`, `A and B`, `A, B and C` join.

### Slice 3 (macOS)

14. **ScreenCaptureKit `ScreenSource`**: one `SCShareableContent` fetch per freeze, task group, own-pid exclusion, scale from the image, error mapping. Tests: error mapping only (hosted runners can't record the screen); the real freeze is Mac batch §9.4.1.
15. **`CGWindowListReader`**, **`ImageIOPipeline`** (crop, downscale in the image's colour space, PNG; round trip with a P3 image keeps P3), **`CarbonHotkeyRegistrar`** (signature `'BgEy'`), **`SystemShortcutDefaultsReader`** (`com.apple.symbolichotkeys`, `hw.model`).

### Slice 4 (macOS)

16. **Overlay**: `SelectionOverlayWindow` (properties of §5.2, close on finish, leftover sweep), `SelectionOverlayView` (frozen image, dim, border, crosshair and loupe as moved subviews, readout, hint (C22), window highlight; `NSEvent` → flow events; damage accumulation); tests for window properties, close on finish, a late `mouseEntered`, damage rects, event translation.
17. **`AppCaptureShell`**: implements `CaptureShell` (overlays per session, key, beep, activation and reactivation, `os.Logger` categories).
18. **Permission alert and relaunch** (§5.5), **Capture pane** (§5.7), **Shortcuts pane** (§5.6) views; registrar wiring helper.

### Slice 5 (macOS + Mac batch)

19. **`CaptureWiring`**: modules `[CaptureModule()]`; `install` registers menu items and hotkeys with the router, sets `areaSelector.target`, `screenRecordingAlert.presenter`, the panes, `onLaunch` (registrar, launch notices, janitor at launch and hourly), debug commands (`capture.state`). Tests against `AppContext.testing`.
20. **Checklist** `docs/checklists/wave-1-capture.md`; PR description with the `CLAUDE.md changes` block; `needs-mac-check`.

## Review Focus

- `CaptureFlow`: every path out of `freezing` and `finishing` returns to `idle` exactly once (I4), including a stale `frozen` after an external cancel, and a `select` while a screenshot's window capture is in flight.
- Async results in the controller: a freeze or window capture that finishes after a cancel must check the session before changing state (`design/11` §6).
- Coordinates: displays left of / above the primary, a selection dragged across a display edge, `Return` after the display changed size.
- The output fallbacks: an unwritable folder vs. a missing one vs. `NoFreeName`; the temp write failing with copy on and off.
- macOS code not compiled in this session: AppKit name clashes (`CocoaRect` etc. are ours), main-actor isolation of Carbon callbacks, `SCShareableContent` called once per freeze.
