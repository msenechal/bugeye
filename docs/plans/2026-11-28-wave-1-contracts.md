# Wave 1 contracts: plan

**Goal:** land the Wave 1 contracts PR: every shared shape, fake, small shared adapter and piece of shell plumbing the five Wave 1 epics need, the ownership check, the debug commands and the sequencing rules, and no feature behaviour.
**Spec:** `docs/specs/2026-11-27-wave-1-contracts.md` (approved 28 Nov 2026). Where this plan and the spec differ, the spec wins unless a ruling below says otherwise.
**Branch:** `feat/wave1-contracts`, cut from `origin/main` (Wave 0 merged, `a82a783`).
**Ledger:** `docs/ledgers/wave-1-contracts.md`. Commit trailers: the session's Co-Authored-By and Claude-Session lines.
**PR:** a draft PR to `main` after Task 1. While it is a draft, `make test-core lint guards` is the check and pushes are batched (R10). The `macos` job is reached with a manual `workflow_dispatch` run on the branch where possible, else by marking the PR ready (CLAUDE.md "Git and process").
**Process:** written and executed by the same session without approval (`design/14` R11). Ambiguities are decided and ledgered as `Ruling:`.

## Facts checked

- Toolchain here: Swift 6.4.3 on Linux (`swift --version`), the same as `.swift-version` and the `linux` job image.
- Swift's `Glibc` module on this image does **not** expose `renameat2` or `RENAME_NOREPLACE` / `RENAME_EXCHANGE` (scratch compile: `cannot find 'renameat2' in scope`). macOS exposes `renameatx_np` with `RENAME_EXCL` and `RENAME_SWAP` through Foundation's Darwin re-export (Wave 0's writer already calls `rename` and reads `errno` with only `import Foundation`).
- `BugeyeTestSupport` depends only on `BugeyeCore` (`Package.swift`), so every new fake is of a `BugeyeCore` type (K18). `BugeyeAppTests` depends on `BugeyeApp` and `BugeyeTestSupport`; a `Support/` subfolder needs no manifest change.
- Wave 0 code this plan reshapes: `Sources/BugeyeCore/{Files/CaptureFileWriter,DisplayList/DisplayList,Ports/Ports}.swift`, `Sources/BugeyeFeatures/{FeatureModule,FeatureRegistry,StatusMenu,DebugCommandHandler}.swift`, `Sources/BugeyeApp/{AppServices,AppDelegate,MainMenu,MenuBarController,SettingsWindowController,DebugChannel}.swift`.
- `scripts/guards.sh` forbids `import Darwin` / `import os` in portable targets, so the writer's platform calls are written under `#if canImport(Darwin)` / `#else` with only `import Foundation`.

## Plan rulings

- **P1 — The plan lists tests and shapes, not every line of code.** The write-plan skill asks for exact code drafted in a scratch package first. Here the same session writes the plan and executes it at once (R11), and the spec already fixes every public shape; the code is drafted directly in the branch with each test seen failing first, and the committed code is the reviewable artefact. Each task below names its files, its failing tests (name and assertion) and the commands. (cost if wrong: low; a reader of the plan alone sees less code, the final review reads the diff anyway.)
- **P2 — No-replace rename on Linux is `link(2)` then `unlink(2)`**; `renameat2` isn't reachable from Swift here (Facts). The `requireExisting` final step on Linux is a check-then-rename; on macOS it is `renameatx_np(RENAME_SWAP)` and then the swapped-out old file is removed. (cost if wrong: low; Linux is test-only, macOS gets the atomic primitives.)
- **P3 — The writer's test seam is internal** (`@testable import BugeyeCore` in the writer tests): `simulateCrossVolume` forces `move`'s `EXDEV` path. Failure injection uses `FakeFileMetadataStore.failSetting`. (cost if wrong: none.)
- **P4 — Cross-volume move and `copy` normalise attributes the same way on both platforms:** after `FileManager.copyItem` (which copies every xattr on macOS and none on Linux), attributes that aren't preserved (`CaptureFileWriter.isPreserved`) are removed from the temp file and the source's preserved ones (with the new identity, if any) are set. So quarantine and Finder tags never cross a copy, as P11 of Wave 0 says. (cost if wrong: low.)
- **P5 — `CaptureEventBus.item(_:)` stores `saved`, `moved` and `edited` only for an id it already knows;** `created` always stores. "A change for an unknown id is still delivered, not stored" (§4.1.1) read this way. (cost if wrong: low; a `saved` for a never-created id would otherwise invent an item.)
- **P6 — A dropped `CaptureSubscription` stops delivery through a weak reference** held by the bus, not a `deinit` (a main-actor class's `deinit` can't touch the bus safely). (cost if wrong: none.)
- **P7 — `ThumbnailDecorations` notifies its observers when a `deleted` event drops decorations,** as well as after every `set`, so a view never shows a dropped badge. (cost if wrong: none; an extra callback.)
- **P8 — Main-menu ids:** the shell's fixed items get ids `mainMenu.<name>` (e.g. `mainMenu.save`); a module main-menu item reusing a fixed id or another module's id is `duplicateMainMenuItem`. On a tie in `order` inside a group, the shell's item comes first, then module items in registration order. (cost if wrong: low.)
- **P9 — `KeyCombo(description:)` accepts zero or more modifier symbols in any order, each at most once, then exactly one character; the key is stored lowercased.** It round-trips `description` for every combo whose key is one character. (cost if wrong: low.)
- **P10 — `.accessory` keeps a main menu.** The spec says `.accessory` removes the main menu; Wave 0 installs one at launch because without it ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W don't work in Settings (a fixed Wave 0 bug, `fcb3ded`). So the shell installs the menu built from `MainMenu.entries` at launch and on `.regular` (then activates), and on `.accessory` sets the policy back and leaves that menu in place (an accessory app never shows it). The test checks `.regular` installs it, sets the policy and activates; `.accessory` sets the policy back and the Edit items still reach the first responder. (cost if wrong: low; the user sees no menu bar either way while no document window is open.)
- **P11 — `DebugCommandHandler` becomes a `@MainActor` class in `BugeyeFeatures`** that owns the built-in commands (it subscribes to the bus for `events`) and asks a lookup closure for registered commands; `DebugCommands` (the registry, `BugeyeApp/Debug/`) gives that lookup. `DebugChannel` hops to the main actor with `DispatchQueue.main.sync` for each line. (cost if wrong: low.)
- **P12 — Debug values as JSON:** `get` prints strings JSON-quoted, bools `true`/`false`, ints as digits and doubles with Swift's `description` (always with a `.` or exponent, so `2.0`); `set` reads `null` (removes the key), `true`/`false`, a JSON string, an integer (`Int`), else a `Double`; anything else is `error: invalid value <json>`. Missing arguments answer `error: usage: <command> …`. (cost if wrong: low; debug-only.)
- **P13 — The Wave 0 `MainMenu` enum in `BugeyeApp` is replaced** by `MainMenuInstaller`, built from `BugeyeFeatures.MainMenu.entries`, to avoid two `MainMenu` types in one module scope; `MainMenuTests` move to the new builder and keep their assertions (the new table keeps every Wave 0 key; Close moves from Window to File, as §4.2.5 says). (cost if wrong: none.)
- **P14 — `RenameFailed` keeps its `errno` field** for logs; only its `errorDescription` hides the number (K30). Portable code has no logger, so "logged" means callers log `String(describing:)`. (cost if wrong: none.)

## Steps only the user can do

None (K19). If the macOS job needs something only the user can give (a runner, a secret), it is ledgered under `Waiting on user` and the work goes on.

## Tasks

Each code task: write the tests, run the stated command and see them fail (compile failure for new names counts), write the code, run it again and see it pass, then `make test-core lint guards`. Tasks marked **macOS** can't compile here: test and code are committed together and the `macos` job is the result.

1. **Ledger, plan, draft PR.** `docs/ledgers/wave-1-contracts.md`, this plan. Push; open the draft PR.
2. **Ownership check (K16, K24, K25).** `scripts/ownership.sh`, `scripts/test-ownership.sh`, `Makefile` (`ownership` target with `BASE ?= origin/main`; `guards` also runs the self-test), `.github/workflows/linux.yml` (`fetch-depth: 0`; PR-only safe-directory + `make ownership BASE=origin/${{ github.base_ref }}` step). Self-test first (every case of §3), seen failing with no script.
3. **Captures and the bus (§4.1.1).** `Sources/BugeyeCore/Captures/CaptureItem.swift`, `CaptureEventBus.swift`; tests `Tests/BugeyeCoreTests/CaptureEventBusTests.swift`: prefixes and extensions; order; cancelled and dropped subscriptions get nothing; nested publishes FIFO to everyone; `item` follows created/saved/moved/edited, forgets on deleted, ignores editing and unknown changes; unknown id delivered not stored.
4. **Names and folders (§4.1.3).** `Captures/CaptureFileNamer.swift`, `Captures/CaptureFolders.swift`; tests for every kind's name in a fixed time zone, `.mov` override, candidates (`a.b.png` → `a.b (2).png`, no extension), folders for a home.
5. **The writer (§4.1.2, K8, K27, K28, K30).** `Files/CaptureFileWriter.swift`; tests in `CaptureFileWriterTests.swift`: every case listed in §4.1.2, the three descriptions character for character.
6. **Output settings and notice (§4.1.4).** `Captures/OutputSettings.swift`; defaults, bad values, keys, body string.
7. **Ports and docs (§4.1.5, §4.1.6).** `Ports/Notifier.swift`, `Ports/ScreenCapturePermission.swift`, `Ports/TextMeasuring.swift`, `WindowID` and `DisplayInfo` doc in `Ports.swift`, `PixelBuffer` doc.
8. **Display list (§4.1.7).** Reshape; tests: `isBalanced` cases, `ellipse` exact points, `roundedRect` clamp and 0, golden JSON covering every command, JSON round trip.
9. **Selection and gating (§4.1.8).** `Selection/AreaSelector.swift`, `Selection/ScreenActivity.swift`; relay with and without target; the full activity × request table.
10. **Moves (§4.1.9).** `Ports/Capture/ScreenSource.swift`, `Ports/Text/TextReader.swift`, `Ports/Accessibility/AXReader.swift`; fakes to `BugeyeTestSupport/{Capture,Text,Accessibility}/`; their tests move to the owners' test folders.
11. **Feature specs and conflicts (§4.2.1).** `FeatureModule.swift`, `FeatureRegistry.swift`, `QuickAccess/QuickAccessPlacement` in the module file; new conflicts and `mainMenuItems` order.
12. **Bindings (§4.2.2).** `HotkeyBindings.swift`; round trips for every Capture and Recording default (⇧⌘3, ⇧⌘4, ⇧⌘5, ⌥⇧⌘3, ⇧⌘2, ⇧⌘6, ⌥⇧⌘5, ⌥⇧⌘2…), invalid strings, `isValidHotkey`, `current` for missing/none/invalid/valid.
13. **Quick Access types and decorations (§4.2.3).** `QuickAccess/QuickAccessActions.swift`, `QuickAccess/ThumbnailDecorations.swift`.
14. **ActionRouter (§4.2.4).**
15. **MainMenu (§4.2.5)** and its strings; **DocumentWindows (§4.2.6)**, **StatusItemOverride (§4.2.7)**, **TerminationGate (§4.2.8)**, **Settings layout (§4.2.9)**.
16. **Fakes (§4.3).** `CaptureEventRecorder`, `FakeNotifier`, `FakeScreenCapturePermission`, `FakeAreaSelector`, `FakeTextMeasurer`, each with a self-test.
17. **Debug commands, portable part (§4.5, K23).** `DebugCommandHandler` against fakes: ping, modules, hotkey, menu, get, set, events (50, oldest first, JSON shape), registered prefix, usage and unknown errors.
18. **Small portable bits.** `Sources/Core/TextCore/TextServices.swift`; `FixtureContent` gains `passwordPlaceholder`, `playClickButton`, `windowMenu`, `smallWindowItem`, `smallWindowTitle`, `smallWindowSize`.
19. **macOS: shared adapters (§4.4).** `Sources/Mac/MacAdapters/Shared/*.swift` and `Tests/MacAdaptersTests/Shared/*`.
20. **macOS: app context and wiring (§4.5).** `Wiring/AppContext.swift` (with `SettingsPanes`, `ScreenRecordingAlert`, `StatusItemState`, `HotkeyStatus`), `Debug/DebugCommands.swift`, the five wiring stubs, `AppServices` rewired, `Tests/BugeyeAppTests/Support/AppContextTesting.swift`, tests.
21. **macOS: shell plumbing (§4.5).** `MenuBarController` delegate, keys, enabled state and override; `SettingsView` panes; `MainMenuInstaller`; `AppDelegate` (router, notifier authorization, `onLaunch`, termination); `DebugChannel` main-actor hop; `check-release-symbols.sh` pattern; `NightChrome`.
22. **Resources and fixture (§4.6).** `Info.plist` usage strings with a test; fixture app additions.
23. **PR description** with the "Uses from the contracts" table (§8 item 4), checked against the merged names.

## Review Focus

- The writer: the no-replace loop under a real clash, a failure in the middle of each new method (does a temp file survive? does the source survive?), symlinks and names near 255 bytes (backlog M2/M3 still apply), and that `requireExisting` on macOS really uses `RENAME_SWAP` and removes the swapped-out file.
- The bus: re-entrancy (a handler that cancels a subscription, or subscribes, during delivery).
- `TerminationGate`: a participant that never returns; a second `shouldTerminate` after the first finished.
- `DebugChannel`'s `DispatchQueue.main.sync`: called only from its own thread, never from the main thread.
- macOS code was not compiled in this session before the `macos` job: names that clash with AppKit/SwiftUI (`MainMenu`, `Shadow`, `LineCap`, `LineJoin` are all ours and live in modules that the app imports alongside AppKit: check every use site compiles unambiguously).
- K20: no contract test asserts the live module list.
