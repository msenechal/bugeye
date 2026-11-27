# 01 · Architecture, toolchain and app shell

Scope: how Bugeye is built, packaged, signed and launched; the targets and their language modes; the test architecture; and the app shell (AppDelegate wiring, global hotkeys, menu bar, Settings, night chrome, folder migration, temp purge, disk guard, notifications, login item, permissions, logging).

Everything here was checked against the code on `feat/m11-collections` (commit 771bcd1). Commit hashes cite the change that introduced a fix.

---

## 1. What it does (user-visible)

### 1.1 Identity

| Item | Value |
|---|---|
| Product name (every user-visible string) | **Bugeye** (formerly "CleanShot Copy") |
| Bundle | `/Applications/Bugeye.app`, executable `Contents/MacOS/Bugeye` |
| Bundle identifier | `dev.msenechal.cleanshotcopy` (kept from the old name on purpose) |
| Signing identity | `CleanShotCopy Dev` (self-signed, own keychain) |
| SwiftPM package / app target | `CleanShotCopy` (never renamed) |
| Minimum OS | macOS 26 (`platforms: [.macOS(.v26)]`, `LSMinimumSystemVersion 26.0`) |
| App type | Menu-bar agent (`LSUIElement`), no Dock icon unless a document window is open |
| Version | `0.1.0` (build `1`), shown in Settings' header |

### 1.2 Global hotkeys

Registered with Carbon `RegisterEventHotKey` at launch. The user must turn off the macOS screenshot shortcuts.

| Shortcut | Action ID | Action |
|---|---|---|
| ⇧⌘3 | 1 `fullscreen` | Full screen of the display under the mouse |
| ⌥⇧⌘3 | 2 `fullscreenAll` | Every display, one file each |
| ⇧⌘4 | 3 `area` | Area capture (Space → window mode) |
| ⇧⌘5 | 4 `record` | Start recording set-up; again = stop |
| ⇧⌘6 | 5 `scrolling` | Scrolling capture |
| ⇧⌘7 | 6 `text` | Capture Text (OCR to clipboard) |
| ⇧⌘8 | 7 `findCapture` | Find Capture palette (toggle) |
| ⇧⌘9 | 8 `recordGuide` | Record Guide; again = Done |

Temporary hotkeys (registered only while needed, unmodified keys):

| ID | Key | When |
|---|---|---|
| 100 / 101 / 102 | Esc / Return / keypad Enter | During a scrolling capture, and only while no Bugeye window or modal has the keyboard |
| 103 | Esc | While any selection overlay is up (screenshot, recording, scrolling, text) |

All hotkeys use the signature `'CSC!'` (`0x43534321`).

**Routing rules** (`HotkeyRoute.of`, pure and unit-tested):

- ⇧⌘8 always works (it captures nothing).
- ⇧⌘9: if a guide is running → Done. Otherwise only when recording is idle, no screenshot is in progress and no scrolling capture runs.
- ⇧⌘5: allowed unless the recording phase is idle *and* a screenshot selection is in progress (no second overlay over a screenshot selection). Stopping is always allowed.
- Screenshot hotkeys (⇧⌘3/4/6/7) are ignored while the recording set-up is on screen (`selecting`, `configuring`, `countingDown`).
- ⇧⌘7 is also ignored while recording or paused (OCR spec §2.3). ⇧⌘3/4/6 still work during a recording.
- `CaptureCoordinator.begin()` additionally drops any capture while another is in progress (`isCapturing`).

**Launch check.** If any binding failed to register, or the system shortcuts are still on, Bugeye posts:
- Title: `macOS screenshot shortcuts are still on`
- Body: `Disable ⇧⌘3, ⇧⌘4, ⇧⌘5 and ⇧⌘6 in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, and free ⇧⌘7, ⇧⌘8 and ⇧⌘9 if another app uses them, so Bugeye receives them.`

### 1.3 Menu bar

Status item: a square item with a template glyph (brackets + bug, drawn in code at 18×18 pt by `BugeyeArtwork.drawGlyph`). While recording it becomes text: red `● ` (or `❙❙ ` when paused) plus `mm:ss` in monospaced digits; while finishing it shows the `hourglass` SF Symbol.

Idle menu, in order (shortcuts shown are display-only; the real hotkeys are global):

| Item | Shown shortcut | Notes |
|---|---|---|
| Capture Area | ⇧⌘4 | |
| Capture Scrolling Area | ⇧⌘6 | |
| Capture Text | ⇧⌘7 | |
| Capture Window | — | Opens the area overlay already in window mode |
| Capture Fullscreen | ⇧⌘3 | Display under the mouse |
| Record Screen | ⇧⌘5 | |
| Record Guide | ⇧⌘9 | Enabled only when `HotkeyRoute` allows it |
| — | | |
| Open Last Capture | — | Disabled when there's no last capture or its file is gone (checked in `menuNeedsUpdate`) |
| Find Capture… | ⇧⌘8 | |
| Duplicates… | — | |
| New Collection | — | |
| Open Recent ▸ | — | Recent `.bugeye` collections; disabled when empty |
| — | | |
| Settings… | ⌘, | |
| Quit Bugeye | ⌘Q | |

Recording menu: Pause/Resume, Stop (⇧⌘5), separator, Restart, Discard.

Menu actions follow the same rules as the hotkeys: screenshots are ignored while `phase.blocksScreenshots`; Record only when `allowsRecordingHotkey`.

Open Last Capture opens a screenshot in the editor, a recording in plain playback (Trim one click away), a GIF in the default viewer, a collection in its window.

### 1.4 Main menu (only while a document window is open)

`MainMenu.install()` builds Bugeye / File / Edit / View. Items target the first responder by selector; the editor and collection windows implement them.

- **Bugeye:** Quit Bugeye ⌘Q.
- **File:** Save ⌘S, Save As… ⇧⌘S, Export… ⌘E (`collectionExport:`), Open Source, Find Similar, Close ⌘W.
- **Edit:** Undo ⌘Z, Redo ⇧⌘Z, Cut, Copy, Copy Text ⇧⌘C, Copy for AI ⌥⌘C, Copy as Markdown, Paste, Delete, Select All, Find… ⌘F, Snap to Elements.
- **View:** Zoom In ⌘=, Zoom Out ⌘−, Actual Size ⌘1, Zoom to Fit ⌘0.

### 1.5 Settings window

Title `Bugeye Settings`. A SwiftUI `Form` (`.grouped`) in an `NSHostingController`. Resizable; minimum and initial content size 480 × 600 pt; frame remembered under autosave name `BugeyeSettings`. It opens by itself at launch when `needsSetup` (Screen Recording missing, or a system shortcut conflict).

Sections and exact labels:

1. **Header:** app icon at 64 pt, "Bugeye", "Version 0.1.0".
2. **Setup** (each row: green ✓ or orange ⚠, plus a button only when not OK):
   - `Screen Recording permission` → `Open Settings…` (calls `CGRequestScreenCaptureAccess` then opens the Privacy pane).
   - `macOS screenshot shortcuts disabled` / `Disable: <names>` → `Keyboard Shortcuts…`.
   - `Microphone allowed (optional, for recordings)` / `Microphone (optional, for recording your voice)` → `Allow…` (not determined) or `Open Settings…`.
   - `Camera allowed (optional, for the webcam bubble)` / `Camera (optional, for the webcam bubble)` → `Allow…` / `Open Settings…`.
   - `Accessibility allowed (keystrokes, auto-scroll and exact text)` / `Accessibility (optional: keystrokes, auto-scroll and exact text)` → `Open Settings…` (`AXIsProcessTrustedWithOptions` with prompt).
   - `Browser URLs (Arc, Chrome)`: one row per installed browser, `Arc: Allowed | Not asked | Not allowed`, with `Allow` or `Open Settings`.
   - Buttons `Re-check` and `Relaunch App`.
3. **After capture:** `Copy to clipboard`, `Save to folder`, folder path + `Choose…`, `Downscale Retina captures to 1×`.
4. **Quick Access:** `Auto-dismiss` (Never, 5, 10, 30, 60 seconds), `Position` (Bottom left / Bottom right).
5. **Recording:** `Video format` (H.264 / HEVC) with note `H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304.`; `Show all keystrokes (not just shortcuts)` with note `Off: only presses with ⌘ or ⌃ appear, so what you type (including ⌥ symbols) stays private.`
6. **Scrolling capture:** stepper `Maximum height: 30,000 px` (10,000–60,000, step 5,000), note `Very wide areas get a lower limit, so an image never passes 150 million pixels.`
7. **Text & snapping:** `Read exact text with Accessibility`; `Turn on Accessibility in Electron apps and Chromium browsers (VS Code, Cursor, Arc, Chrome)` (disabled when exact text is off) with note `Those apps do a little more work while it's on.`; `Snap annotations to UI elements`.
8. **Privacy:** the sweep master toggle, then one indented toggle per `SensitiveKind` (disabled while the sweep is off), and a note (strings in `SweepText`).
9. **Search:** `Index captures for search`, `Add captures to Spotlight` (disabled while indexing is off), orange `Spotlight isn't accepting Bugeye's captures` when it failed, slider `Duplicates: how close` from `Identical only` to `Loosely similar`, counts line `Indexed: N screenshots, M recordings`, `Rebuild Index`.
10. **General:** `Launch at login`; when approval is pending, orange `Needs approval in System Settings → General → Login Items` + `Open Login Items`; else a red error line if register/unregister threw.

### 1.6 Other launch-time behaviour

- One-time capture-folder move from `~/Pictures/CleanShotCopy` to `~/Pictures/Bugeye` (see §2.10). Notices:
  - renamed or merged: `Captures moved` / `Your captures are now in ~/Pictures/Bugeye.`
  - failed after moving some: `Captures only partly moved` / `<n> captures are in ~/Pictures/Bugeye, the rest stay in ~/Pictures/CleanShotCopy, where Bugeye keeps saving (<reason>).`
  - failed with nothing moved: `Captures not moved` / `Bugeye keeps saving to ~/Pictures/CleanShotCopy (<reason>).`
- Temp captures older than 24 h are deleted (launch only, not periodically).
- Launch at login is registered once on a fresh install in `/Applications`.
- Collection drafts older than 7 days are cleaned in a detached utility task.
- The search index's launch pass is armed (waits for a quiet moment).

### 1.7 Dock icon policy

- `main.swift` sets `.accessory`; `Info.plist` has `LSUIElement = true`.
- `DocumentWindows` counts open editors and collection windows. The first one switches to `.regular` (Dock icon, main menu, ⌘Tab); the last close switches back to `.accessory`.
- Opening an editor calls `NSApp.activate()` and makes the canvas first responder.

---

## 2. How it's built

### 2.1 Toolchain constraints (Command Line Tools only)

The machine has Swift 6.4 from the Command Line Tools (`/Library/Developer/CommandLineTools`), **no Xcode**. Consequences:

| Constraint | Detail |
|---|---|
| No XCTest | Every test uses Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`, `Issue.record`, `.enabled(if:)` traits). |
| Macro plugins | Only `libObservationMacros.dylib`, `libSwiftMacros.dylib` and `testing/` ship in `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/`. |
| SwiftUI `@State` | Fails to compile ("SwiftUIMacros plugin not found"). Keep view state in an `ObservableObject` with `@Published`; hold it with `@StateObject` or `@ObservedObject` (both compile). `@Environment` and `@Binding` also compile. |
| `@Observable` | Avoided (the plan rule is "no `@Observable`"). Use `ObservableObject`. |
| `#Preview` | Not used; previews need Xcode anyway. |
| Other macros | Before using any, check its plugin is in the folder above. |
| Debugging | `lldb` can't attach to the installed, self-signed app. Use the unified log (§2.14). |

**The testing plugin path.** `Package.swift` defines:

```swift
let testingPlugins: [SwiftSetting] = [
    .unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"]),
]
```

Every test target gets `swiftSettings: testingPlugins`. Why: with CLT only, SwiftPM's build intermittently omits the Swift Testing macro plugin from test compiles, so `@Test`/`#expect` fail to expand (dc7c60c). Pointing the compiler at it explicitly fixed it. `unsafeFlags` is fine because this package is never a dependency of another package.

### 2.2 Targets and language modes (`Package.swift`, tools 6.2)

| Target | Kind | Language mode | Depends on | Role |
|---|---|---|---|---|
| `CSCore` | library | Swift 6 | — | Pure, unit-tested logic (settings, routing, naming, geometry, stacks, timers, policies, text layout, rules, models) |
| `CSEditor` | library | Swift 6 | CSCore | Editor and collection models, renderer, exporter, snapping, `BugeyeArtwork` |
| `CSCapture` | library | **Swift 5** | CSCore | ScreenCaptureKit stills, scroll frames, Vision (OCR, faces, rectangles, feature prints), guide frame buffer |
| `CSRecording` | library | **Swift 5** | CSCore | `SCStream` recorder, `AVAssetWriter`, finaliser, trimmer, GIF encoder, thumbnails |
| `BugeyeIconTool` | executable | **Swift 5** | CSEditor, CSCore | Renders the icon set for `make icon` |
| `CleanShotCopy` | executable | **Swift 5** | all four libraries | The app (AppKit + SwiftUI) |
| `CSCoreTests` | test | Swift 6 | CSCore | |
| `CSEditorTests` | test | Swift 6 | CSEditor, CSCore | Includes golden PNGs in `Golden/` |
| `CSCaptureTests` | test | Swift 6 | CSCapture, CSCore | |
| `CSRecordingTests` | test | **Swift 5** | CSRecording, CSCore | |
| `CleanShotCopyTests` | test | Swift 6 | CleanShotCopy | `@testable import CleanShotCopy` (an executable target) |

**Why Swift 5 mode for some targets.** AppKit, Carbon, ScreenCaptureKit, AVFoundation and Vision callbacks are not Sendable-clean; Swift 6 strict concurrency produced a wall of errors at those boundaries. The rule from the M1–M4 plans: keep pure logic (`CSCore`, `CSEditor`) in Swift 6, put Apple-framework wrappers and the app in Swift 5 mode. Swift 6 targets must not declare global or static `let`s of non-Sendable types (create renderers locally in tests).

The app still uses `@MainActor` heavily (52 places) and `Task.detached` for off-main work; Swift 5 mode just turns the Sendable diagnostics into non-errors.

**Testing an executable target.** `CleanShotCopyTests` imports the app module with `@testable`. That works with SwiftPM on macOS. `main.swift` holds top-level code, so the app's entry point lives there and not in an `@main` type.

### 2.3 Source layout

```
Package.swift  Makefile  README.md  CLAUDE.md
Resources/Info.plist  Resources/Bugeye.icns
scripts/bundle.sh  scripts/make-signing-cert.sh
Sources/
  CSCore/        58 files, pure logic
  CSEditor/      24 files
  CSCapture/      8 files: ScreenCapturer, WindowShadow, ScrollFrameSource, TextRecognizer,
                           FaceDetector, RectangleDetector, FeaturePrinter, GuideFrameBuffer
  CSRecording/    7 files
  BugeyeIconTool/ main.swift
  CleanShotCopy/ (the app)
    main.swift AppDelegate.swift CaptureCoordinator.swift MenuBarController.swift MainMenu.swift
    HotkeyManager.swift HotkeyRoute.swift LoginItemSetup.swift Notifier.swift PermissionPrompt.swift
    NightChrome.swift BrandImages.swift PasteboardClipboard.swift NSScreen+Display.swift
    ActionHabitsStore.swift SourceLauncher.swift
    Selection/ QuickAccess/ Editor/ Recording/ Media/ ScrollCapture/ TextCapture/ Settings/
    Snapshot/ Provenance/ Sweep/ Search/ Collections/ Guide/
Tests/<Target>Tests/   mirrors the targets
docs/superpowers/specs/  docs/superpowers/plans/  docs/manual-checklist-*.md  docs/backlog.md
```

### 2.4 Makefile

| Target | What it does |
|---|---|
| `make cert` | `scripts/make-signing-cert.sh`: one-time signing identity |
| `make app` | `scripts/bundle.sh release`: build, assemble, sign `build/Bugeye.app` |
| `make install` | `app`, then: `pkill -x CleanShotCopy`, `pkill -x Bugeye`; `lsregister -u` the legacy `/Applications/CleanShotCopy.app` and `build/CleanShotCopy.app`; `rm -rf` them and the installed Bugeye; `cp -R build/Bugeye.app /Applications/`; `lsregister -f /Applications/Bugeye.app` |
| `make run` | `install`, then `open /Applications/Bugeye.app` |
| `make test` | `swift test` |
| `make smoke` | `CSC_INTEGRATION=1 swift test --filter "CSCaptureTests\|CSRecordingTests\|aRealAccessibilityRead\|theRealDisplaysAndWindows\|aRealCollectionExports"` |
| `make icon` | `swift run -c release BugeyeIconTool build/Bugeye.iconset`, then `iconutil -c icns … -o Resources/Bugeye.icns` (the `.icns` is committed) |
| `make clean` | `rm -rf .build build` |

`lsregister` is `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`.

**Why the LaunchServices cleanup.** The pre-rename bundles share Bugeye's bundle identifier. While LaunchServices still knows them, notifications, the login item and `open -b` can launch the old app. `make install` deletes them and unregisters them so only Bugeye can ever be launched for that identifier (7401f4e).

### 2.5 `scripts/bundle.sh`

1. `swift build -c release`, then `--show-bin-path` to find the binary.
2. Recreate `build/Bugeye.app/Contents/{MacOS,Resources}`.
3. Copy the binary `CleanShotCopy` → `Contents/MacOS/Bugeye`; copy `Resources/Bugeye.icns` and `Resources/Info.plist`.
4. Fail with "No signing keychain. Run: make cert" if `~/Library/Keychains/cleanshotcopy-signing.keychain-db` is missing.
5. `security unlock-keychain -p cleanshotcopy <kc>`.
6. `codesign --force --sign "CleanShotCopy Dev" --identifier dev.msenechal.cleanshotcopy build/Bugeye.app`.
7. Print the designated requirement (`codesign -d -r-`).

No entitlements, no hardened runtime (`--options runtime` is not passed), no sandbox. That is why mic, camera and Apple Events work with only the Info.plist usage strings.

### 2.6 `scripts/make-signing-cert.sh`

- Identity name `CleanShotCopy Dev`; keychain `~/Library/Keychains/cleanshotcopy-signing.keychain-db`, password `cleanshotcopy`.
- Exits early if the certificate already exists.
- Uses **`/usr/bin/openssl` (LibreSSL)**: its PKCS#12 output is importable by `security`. (A Homebrew OpenSSL 3 export uses algorithms `security import` rejects.)
- Certificate: self-signed RSA 2048, 10 years, `basicConstraints=critical,CA:false`, `keyUsage=critical,digitalSignature`, `extendedKeyUsage=critical,codeSigning`.
- PKCS#12 password `csc`; imported with `-T /usr/bin/codesign`.
- `security set-keychain-settings <kc>` (no auto-lock); `set-key-partition-list -S apple-tool:,apple: -s` so codesign can use the key without a prompt.
- Adds the keychain to the user search list if missing.

**Why a stable identity matters.** macOS TCC keys privacy grants (Screen Recording, Microphone, Camera, Accessibility, Automation) to the app's designated requirement: bundle identifier + signing certificate. An ad-hoc signature (`codesign -s -`) changes with every build, so every rebuild would re-prompt for Screen Recording and Accessibility. With a fixed self-signed leaf certificate and a fixed `--identifier`, grants survive `make run`. Keeping the old bundle id and identity through the rename to Bugeye kept every grant and every `UserDefaults` value (also keyed by bundle id).

Caveat seen on device: moving the app from `CleanShotCopy.app` to `Bugeye.app` produced at most one Screen Recording "Allow" confirmation, because macOS also keys that approval by path (M6 branding checklist).

### 2.7 `Resources/Info.plist`

| Key | Value | Why |
|---|---|---|
| `CFBundleIdentifier` | `dev.msenechal.cleanshotcopy` | TCC grants and UserDefaults survive (kept through rename) |
| `CFBundleName`, `CFBundleDisplayName` | `Bugeye` | Name in menus, notifications, Login Items |
| `CFBundleExecutable` | `Bugeye` | bundle.sh renames the SwiftPM binary |
| `CFBundleIconFile` | `Bugeye` | `Resources/Bugeye.icns` |
| `CFBundlePackageType` | `APPL` | |
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `1` | Settings header |
| `LSMinimumSystemVersion` | `26.0` | User is on macOS 26 only (raised from 15 in 3ace1ad; unlocks newer Vision APIs) |
| `LSUIElement` | true | Menu-bar agent, no Dock icon |
| `NSHighResolutionCapable` | true | |
| `NSMicrophoneUsageDescription` | `Bugeye records your microphone when you turn on Mic for a screen recording.` | Required for mic access |
| `NSCameraUsageDescription` | `Bugeye shows your camera in a bubble when you turn on Cam for a screen recording.` | Webcam bubble |
| `NSAppleEventsUsageDescription` | `Bugeye reads the address of the browser tab you capture, so you can open it again later.` | Automation of Arc/Chrome (M7) |
| `NSUserActivityTypes` | `[com.apple.corespotlightitem]` | Spotlight result continuation opens a capture (M10) |
| `UTExportedTypeDeclarations` | `dev.msenechal.bugeye.collection`, conforms to `com.apple.package` + `public.composite-content`, extension `bugeye` | Collections are packages (M11) |
| `CFBundleDocumentTypes` | "Bugeye Collection", role Editor, rank Owner, `LSTypeIsPackage` | Finder double-click opens collections |

Screen Recording and Accessibility need no Info.plist key.

### 2.8 Permissions

| Permission | Needed for | How checked / requested |
|---|---|---|
| Screen Recording | Every capture and recording | `CGPreflightScreenCaptureAccess()`; `CGRequestScreenCaptureAccess()` registers the app in the list and prompts once. Missing → `PermissionPrompt.showScreenRecordingMissing()` |
| Accessibility | Keystroke overlay, auto-scroll, exact text (AX snapshot), guide recorder | `AXIsProcessTrusted()`; request with `kAXTrustedCheckOptionPrompt` then open the pane |
| Microphone | Mic in recordings | `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess` |
| Camera | Webcam bubble | Same, `.video` |
| Automation (Arc, Chrome) | Reading the tab URL for provenance | `AEDeterminePermissionToAutomateTarget` (bundle id descriptor, wildcard class/ID, no prompt); request by running a harmless probe script off the main thread |
| Notifications | All notices | `UNUserNotificationCenter.requestAuthorization([.alert, .sound])` at launch |

Click rings need no permission (global mouse monitors don't require Accessibility; M4 clarification).

**Screen Recording missing alert:** title `Screen Recording permission needed`, text `Enable Bugeye under Privacy & Security → Screen & System Audio Recording, then relaunch the app.`, buttons `Open System Settings` / `Relaunch` / `Cancel`. The capture permission is only re-read by a new process, hence Relaunch.

**Relaunch** (`PermissionPrompt.relaunch`): spawns `/bin/sh -c` with a loop that polls `kill -0 <pid>` every 0.1 s for up to 5 s, then `open "<bundle path>"`; then `NSApp.terminate`. A fixed sleep (the old 0.5 s) could start the new instance while the old one still held the Carbon hotkeys (50cb419).

Settings deep links used:
- `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`
- `…?Privacy_Accessibility`, `…?Privacy_Microphone`, `…?Privacy_Camera`, `…?Privacy_Automation`
- `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`
- `SMAppService.openSystemSettingsLoginItems()`

### 2.9 App start-up (`main.swift` → `AppDelegate`)

`main.swift`:

```swift
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
```

`assumeIsolated` lets the `@MainActor` delegate be built from top-level code. `withExtendedLifetime` keeps the delegate alive (`NSApplication.delegate` is weak).

`applicationDidFinishLaunching`, in order:

1. `FolderMigration.run` (before anything reads settings).
2. `TempJanitor.purge(OutputRouter.defaultTempDirectory)`.
3. `Notifier.requestAuthorization { post migration notice }`: the notice waits for the authorization answer, so it isn't swallowed on first launch (f22c1b0).
4. `SettingsWindowController(store:)`.
5. `OutputRouter`, `QuickAccessController`, `MainMenu.install()`, `EditorManager`.
6. `CaptureCoordinator` with `SensitiveSweep`, `AXSnapshotter`; `startSearchIndex()` (Indexer + `CaptureIndex` + `SpotlightDonor`).
7. `CollectionManager`, `GuideSession`, draft cleanup, pending Finder opens.
8. Wire hotkey callbacks into the coordinator (session keys, selection Esc) and `RecordingCoordinator`.
9. Chain `quickAccess.onItemChanged` so the coordinator, editors, media windows and indexer all follow a moved file.
10. `MenuBarController` with closures for every menu action.
11. Dozens of closure hand-offs between Quick Access, editors, text copier, source launcher, settings model and indexer.
12. `hotkeys.onAction` → `HotkeyRoute.of(...)` → coordinator / recording / guide / Find Capture.
13. `hotkeys.start()` + conflict check → notice.
14. Login item plan (§2.12).
15. Open Settings if `needsSetup`.

Other delegate methods:
- `application(_:continue:restorationHandler:)`: a `CSSearchableItemActionType` activity whose `CSSearchableItemActivityIdentifier` is a UUID opens that capture.
- `application(_:open:)`: `.bugeye` URLs open as collections; URLs that arrive before launch finishes are queued in `pendingCollections` (a2bb26c).
- `applicationShouldTerminate`: guide, editors and collections may cancel (unsaved changes); scrolling capture is cancelled; a running recording is stopped and saved first (`.terminateLater` then `reply(toApplicationShouldTerminate:)`).

The wiring style is closures (`var onX: ((…) -> Void)?`) set by AppDelegate, with `[weak self]` everywhere. This keeps every controller testable without the app, at the cost of a 460-line delegate.

### 2.10 Settings storage

`AppSettings` (CSCore) is a value type; `SettingsStore` reads and writes `UserDefaults.standard` key by key. A missing or invalid value falls back to the default. `SettingsModel` (`ObservableObject`) holds `@Published var settings` and saves on every `didSet`, then calls `onChange(old, new)`.

| Key | Type | Default | Validation |
|---|---|---|---|
| `copyToClipboard` | Bool | true | |
| `saveToFolder` | Bool | true | |
| `saveFolder` | String path | `~/Pictures/Bugeye/` | |
| `autoDismissSeconds` | Int | 5 | must be one of 0, 5, 10, 30, 60 (0 = never) |
| `quickAccessPosition` | String | `bottomLeft` | `bottomLeft` / `bottomRight` |
| `downscaleToPoints` | Bool | false | |
| `recordingCodec` | String | `h264` | `VideoCodec` raw value |
| `showAllKeystrokes` | Bool | false | |
| `scrollMaxHeight` | Int | 30,000 | clamped to 10,000–60,000 |
| `sweep.enabled` | Bool | true | |
| `sweep.kind.<kind>` | Bool | on for `secret`, `connectionString`, `highEntropy`, `card`, `face` | one key per `SensitiveKind` |
| `textSnap.exactText` | Bool | true | |
| `textSnap.enableInElectron` | Bool | true | |
| `textSnap.snap` | Bool | true | |
| `search.indexEnabled` | Bool | true | |
| `search.spotlight` | Bool | true | |
| `search.duplicatesThreshold` | Double | `SimilarityThresholds.duplicatesDefault` (0.03) | clamped to the slider range |
| `guide.mode` | String | `window` | `window` / `display` |

Other `UserDefaults` keys in the app:

| Key | Owner | Meaning |
|---|---|---|
| `recording.fps`, `.quality`, `.systemAudio`, `.microphone`, `.microphoneID`, `.clicks`, `.keystrokes`, `.webcam`, `.webcamSize`, `.cameraID`, `.format`, `.gifWidth`, `.gifFps` | `RecordingOptionsStore` | Options-bar choices persist between recordings |
| `actionHabits` | `ActionHabitsStore` | Encoded per-app usual Quick Access action |
| `collections.recent` | `RecentCollections` | Open Recent list |
| `didMigrateSaveFolderToBugeye` | `FolderMigration` | Migration ran (once, whatever happened) |
| `didConfigureLaunchAtLogin`, `didReregisterLoginItemForBugeye` | AppDelegate | Login item set-up done |
| `NSWindow Frame BugeyeSettings` | AppKit | Settings window frame |

`SettingsStore.saveFolder(_:)` writes only the folder key, so a migration doesn't freeze every other setting at its current default (4b951c9).

Several places call `settingsStore.load()` freshly at the moment of use (router settings before each delivery, Quick Access timeout per thumbnail, scroll cap per session). The editor's snap toggle goes through the Settings model so the Settings UI and the Edit menu stay in sync.

**Settings window details** (`SettingsWindowController`): `NSWindow(contentViewController: NSHostingController)`, style `[.titled, .closable, .resizable]`, `isReleasedWhenClosed = false`. `contentMinSize` and the initial size are set from `host.view.fittingSize` *before* showing, because the hosting controller applies its sizes only at its first layout. `setFrameAutosaveName("BugeyeSettings")` restores the last frame. `show()` refreshes every permission status first. The browser Automation lookup is done only when Settings is shown, not in every `SettingsModel.init` (f490df7), and off the main thread.

### 2.11 Folder migration (`CSCore/FolderMigration`)

Runs once (`didMigrateSaveFolderToBugeye` set first, whatever happens):

1. Stored folder (missing key = the old default) must equal `~/Pictures/CleanShotCopy`, else `.notNeeded` (a chosen folder is never touched).
2. Old folder missing → store the new folder → `.pointedToNew`.
3. New folder missing → `moveItem` (atomic rename on one volume) → `.renamed`.
4. Both exist → move each entry (sorted, skipping `.DS_Store`) with a `name (2).ext` suffix on collision → delete the old folder if only `.DS_Store` is left → `.merged(moved:)`.
5. Any error → keep the old folder as the save folder → `.failed(reason, moved:)`; not retried.

Unit-tested against temp directories for every case.

### 2.12 Launch at login (`LoginItemSetup` + `SMAppService.mainApp`)

`LoginItemSetup.plan(didConfigure:didReregister:inApplications:registered:)`:

| Condition | Plan |
|---|---|
| Not running from `/Applications/` | `.nothing` |
| First launch from `/Applications` | `.register` |
| Configured before, not yet re-registered, currently registered (enabled or requiresApproval) | `.reregister` (unregister then register, so the BTM entry points at `Bugeye.app` instead of `CleanShotCopy.app`) |
| Otherwise | `.nothing` |

Both flags are set after the step when in `/Applications`. Settings' toggle calls `register()`/`unregister()` and shows `.requiresApproval` (8e99b67). `SMAppService` sits behind `LoginItemService` so tests use `FakeLoginItem`.

Note seen on device: System Settings → Login Items may keep showing the old name "CleanShotCopy" for a while (cached); the entry points at Bugeye.app.

### 2.13 Notifier

`Notifier.shared` (`UNUserNotificationCenterDelegate`):
- `requestAuthorization(then:)` sets itself as the centre's delegate (without this, banners are suppressed while Bugeye is frontmost: 4229429), asks for `.alert` and `.sound`, then calls `then` on the main queue.
- `post(title:body:)` adds a request with a UUID identifier and no trigger (immediate).
- `willPresent` returns `[.banner, .sound]`.
- **Guard:** if `Bundle.main.bundleIdentifier == nil` (unit tests, `swift run`), it logs with `NSLog("[Bugeye] …")` instead: `UNUserNotificationCenter.current()` throws an exception in a process without a bundle.

### 2.14 Logging

`os.Logger` with subsystem `dev.msenechal.bugeye`:

| Category | Where | What |
|---|---|---|
| `selection` | `AreaSelectionController`, `SelectionOverlayWindow` | `begin <purpose> overlays [windowNumbers]`, `finish <result> overlays […]`, error `closing a leftover overlay <n>` |
| `search` | `CaptureIndex` and the search glue | index open/repair, launch pass |
| `guide` | `GuideRecorder` | guide steps and failures |

Read it with `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'` or `log stream --predicate …`. Recording code logs missing overlay window IDs (226d9cd).

### 2.15 Night chrome (`NightChrome.swift`)

Always-dark style for Bugeye's floating panels: recording options bar, Quick Access thumbnails, countdown, Export GIF panel, scrolling bar, guide bar. Editors, Settings, the trim window and alerts stay native and follow the system appearance.

| Token | Value |
|---|---|
| Panel gradient | `#2B3242` (top) → `#1B1F29` (bottom), 1 px inner border white @ 8 % |
| Text | `#E8EAF0`; secondary @ 60 % |
| Accent | `#FFC93C`, hover `#FFD666`, text on accent `#1F2430` |
| Control fill | white @ 7 %, hover white @ 12 % |
| Record button | `systemRed` with white text (unchanged) |

API:
- `NightChrome.apply(to: window)` sets `NSAppearance(named: .darkAqua)` so system controls inside match.
- `View.nightPanel(cornerRadius:)` draws the gradient + border and sets the text colour.
- `NightToggleStyle`: on = accent fill with dark text, off = control fill; hover via a `NightHover: ObservableObject` held in `@StateObject` (no `@State`); disabled opacity 0.4; adds `.isToggle` trait and an "On"/"Off" accessibility value (7c326e4).
- `NightButtonStyle(primary:)`: neutral or accent; pressed opacity 0.85; disabled 0.4.
- `NightSegmentedPicker`: a row of `NightToggleStyle` toggles; the selected one is yellow.
- Colours are defined as `NSColor(srgbRed:…)` from hex and bridged to SwiftUI `Color(nsColor:)`.

Icon and glyph: `BugeyeArtwork` (CSEditor) draws both in Core Graphics. Icon = rounded square (radius 23 % of side) with a `#2B3242`→`#161A23` gradient, four white corner brackets (stroke 4.5 % of side), a `#FFC93C` bug with a `#E5A515` seam and a blue lens eye. Menu-bar glyph = template image, lens as a cut-out ring at least 2 px wide at 1× (b1c6149). Golden test at 256 px in `Tests/CSEditorTests/Golden/bugeye-icon.png`.

### 2.16 Temp folder and disk guard

- **Temp folder:** `OutputRouter.defaultTempDirectory` = `~/Library/Caches/dev.msenechal.cleanshotcopy/Captures/`. The path is a hard-coded string, not derived from `Bundle.main` at runtime (the branding spec says "derived from the bundle id", which is only true by coincidence).
- **`TempJanitor.purge(directory:olderThan: 86_400)`** deletes top-level files whose content-modification date is more than 24 h old. Runs at launch only. A long-running Bugeye never purges.
- **`DiskGuard`** (used by recording): start needs ≥ 1 GB free; a recording stops below 300 MB; MP4 conversion only when free ≥ movie size + 50 MB. An unknown free size never blocks. Free space is read with `volumeAvailableCapacityForImportantUsageKey` on the nearest existing ancestor of the target path.

Other app-owned locations (owned by other features, listed here for the full picture):
- `~/Library/Application Support/Bugeye/index.sqlite` (search index)
- `~/Library/Caches/Bugeye/Drafts/` (guide drafts, removed after 7 days)
- `<save folder>/Collections/<Name>.bugeye/`
- xattrs on capture files: `dev.msenechal.bugeye.provenance`, `dev.msenechal.bugeye.uisnapshot`, `dev.msenechal.bugeye.id`, `com.apple.metadata:kMDItemWhereFroms`

### 2.17 HotkeyManager (Carbon) in detail

- `start()` installs one `kEventClassKeyboard / kEventHotKeyPressed` handler on `GetApplicationEventTarget()`, passing `self` unretained as user data. The C callback reads the `EventHotKeyID` with `GetEventParameter(kEventParamDirectObject, typeEventHotKeyID)` and dispatches to the main queue: `Action(rawValue:)` → `onAction`; `SessionKey` → `onSessionKey`; ID 103 → `onSelectionEscape`.
- Bindings use `kVK_ANSI_3…9` with `cmdKey | shiftKey` (`| optionKey` for ⌥⇧⌘3).
- `start()` returns the actions whose `RegisterEventHotKey` didn't return `noErr`.
- **Session keys (scrolling capture):** `registerSessionKeys()` observes `NSWindow.didBecomeKey/didResignKey` and `NSApplication.didBecomeActive/didResignActive`. On each, after one more main-queue hop (the key window is settled only after the notification), `refreshSessionKeys()` registers Esc/Return/Enter only when `NSApp.keyWindow` (if active) and `NSApp.modalWindow` are both nil. So Return answers a Bugeye alert instead of ending the session (4546416).
- **Selection Esc (ID 103):** `registerSelectionEscape(handler)` registers bare Esc; `unregisterSelectionEscape()` releases it. It has its own ID so it never clobbers the session keys.
- `registerKey`/`unregisterKey`/`bugeyeWindows` are swappable closures; tests use `FakeHotKeys`.

A bare-Esc Carbon hotkey takes Esc away from **every** app while registered. That's why both temporary hotkeys are registered only for the exact span they're needed and always released in `finish`/`unregister`.

### 2.18 PasteboardClipboard (`ClipboardWriting`)

Protocol in CSCore (`writePNG`, `writeImage(png:fileURL:)`, `writeImageAndText`, `writeFileReference`, `writeText`) with default implementations so simple fakes only need three methods.

`writeImage(png:fileURL:)` writes **one** `NSPasteboardItem`:
- `public.png` data (eager)
- `public.file-url` string when the capture is on disk
- TIFF through a lazy `NSPasteboardItemDataProvider` (`TIFFFromPNG`), produced only if an app asks (2adb4dd: encoding TIFF up front for a 5K capture was slow)
- HTML through a lazy provider (`HTMLFromPNG`): `<img src="data:image/png;base64,…">`, so Mail and Notes embed the image rather than pointing at a local file

`writeImageAndText` (Copy for AI): PNG + lazy TIFF + `.string` on one item. `writeFileReference` writes the URL object (recordings paste as attachments). `writeText` writes a plain string.

### 2.19 Test architecture

- ~1,050 tests: CleanShotCopyTests 457, CSCoreTests 324, CSEditorTests 196, CSRecordingTests 47, CSCaptureTests 23 (`@Test` counts).
- **Pure logic first.** Anything that can be a function of values lives in CSCore/CSEditor and is tested directly (geometry, routing, stacks, timers, naming, migration, shortcut conflicts, login-item plan, hotkey routing, phases).
- **One seam per Apple API.** Each OS dependency is a protocol or a closure property with a live default; tests substitute fakes:

| Apple API | Seam | Fake |
|---|---|---|
| NSPasteboard | `ClipboardWriting` | `FakeClipboard`, `NullClipboard`, `TextClipboard`, `AIClipboard`, … |
| SMAppService | `LoginItemService` | `FakeLoginItem` |
| Apple Events (Automation) | `BrowserAutomation` | test double in `BrowserAutomationTests` |
| Carbon hotkeys | `HotkeyManager.registerKey/unregisterKey/bugeyeWindows` | `FakeHotKeys` |
| Vision OCR | `TextRecognizing` | `FakeTextReader`, `FakeRecognizer` |
| Vision faces / rectangles | `FaceDetecting`, `RectangleDetecting` | `FakeFaces`, `FakeRectangles` |
| Vision feature prints | `FeaturePrinting` | `FakeFeaturePrinter` |
| Core Spotlight | `SpotlightDonating` | `FakeSpotlight` (actor) |
| Search index | `CaptureSearching` | `FakeCaptureSearching` |
| Accessibility | `AXTreeReading`, `AXPointReading` | `FakeAXTree`, `FakeAXElement`, `FakeAXApp`, `FakeAXPoint` |
| SCStream frames (scroll, guide) | `ScrollFrameSourcing`, `GuideFrameSourcing` | `FakeSource`, `FakeFrameSource` |
| CGEvent scrolling | `AutoScrolling` | `FakeScroller` |
| Global input (guide) | `GuideInputSource` | `FakeGuideInput` |
| VisionKit Live Text | `LiveTextEngine` | `FakeLiveText` |
| NSWorkspace (open source) | `SourceWorkspace` | `FakeWorkspace` |
| Permission checks | `CaptureCoordinator.accessibilityTrusted` closure | `{ false }` |
| UserDefaults | `SettingsStore(defaults:)` | `UserDefaults(suiteName: "csc-…-<uuid>")` |
| Files | injected `FileManager`, temp dirs | `TestSupport.makeTempDir()` |

- **Real hardware only behind `CSC_INTEGRATION=1`** (`@Test(.enabled(if: integration))`): real display and window captures, `WindowShadow` on each real display, scroll frames, OCR, rectangle detection, feature prints, the guide frame buffer, the real recorder, Spotlight donation, a real AX read (also needs `AXIsProcessTrusted()` for the terminal), real displays/windows, collection export. The terminal needs Screen Recording (and Accessibility for the AX smoke test).
- **App-target tests** run real AppKit objects (`_ = NSApplication.shared` first), with frozen-screen images built in memory and synthetic `NSEvent.mouseEvent(...)`s. Tests that open windows must pick out their own window (`Set(NSApp.windows)` before/after) because parallel tests open windows too.
- **Leak tests** keep `weak` references inside `autoreleasepool` and poll for deallocation (not a fixed delay: f9d15b4).
- **Golden images** for the renderer and icon in `Tests/CSEditorTests/Golden/`.

Test hygiene learned the hard way:
- Never spin `RunLoop.main` synchronously in a test; it stalls main-queue waits in other parallel tests (442baf2).
- A test that waits for a main-queue delivery needs a generous budget (≈10 s): the parallel suite saturates the main thread with `@MainActor` tests.
- A full-suite hang was seen once with 65 threads in `-[NSAnimation _runBlocking]`, also on a known-green commit: machine load (another heavy app open), not code. Workaround: `--skip` the window/animation tests and run them alone.
- Known flaky smoke: `scrollingAWindowStitchesTheWholeDocument` depends on what's on screen; the recording-overlay colour smoke tests and M9's AX smoke test can fail on a busy screen. Rerun alone and compare with `master`.

---

## 3. Gotchas and bugs we hit

| Symptom | Root cause | Fix |
|---|---|---|
| Test compiles sometimes failed to expand `@Test`/`#expect` | CLT-only SwiftPM intermittently omits the Swift Testing macro plugin | `-plugin-path …/host/plugins/testing` via `unsafeFlags` on every test target (dc7c60c) |
| `@State` → "SwiftUIMacros plugin not found" | SwiftUI macro plugin not shipped with CLT | `ObservableObject` + `@Published`, held in `@StateObject`/`@ObservedObject` (e.g. `NightHover`, `EditorViewModel`) |
| Swift 6 strict-concurrency errors around AppKit/SCK/AVFoundation callbacks | Frameworks not Sendable-clean | Swift 5 mode for CSCapture, CSRecording, the app, the icon tool and CSRecordingTests; pure logic stays Swift 6 |
| Re-prompt for Screen Recording after each rebuild (would happen with ad-hoc signing) | TCC keys grants to the designated requirement | Stable self-signed identity + fixed `--identifier` |
| Notifications, login item or `open -b` launched the old CleanShotCopy.app | Old bundles with the same id still registered in LaunchServices | `make install` unregisters (`lsregister -u`) and deletes them, then `lsregister -f` the new bundle (7401f4e) |
| Login item still pointed at CleanShotCopy.app after rename | BTM entry keyed to the old bundle path | One-time unregister/register (`LoginItemSetup.reregister`) |
| A fresh install didn't get the login item / got it repeatedly | No "configured" flag | `didConfigureLaunchAtLogin`: register once, only from `/Applications` (f22c1b0) |
| "Captures moved" notice never seen on first launch | Posted before notification authorization was answered | Post from `requestAuthorization`'s completion (f22c1b0) |
| Notification banners didn't show while Bugeye was frontmost | No `UNUserNotificationCenterDelegate` | `Notifier` is the delegate; `willPresent` → `[.banner, .sound]` (4229429) |
| Crash posting a notification in tests | `UNUserNotificationCenter` needs a bundle | Guard on `Bundle.main.bundleIdentifier`, fall back to `NSLog` |
| Migration moved `.DS_Store` and counted it as a capture; wrote every setting | Iterated every entry; saved the whole `AppSettings` | Skip `.DS_Store`; `SettingsStore.saveFolder` writes one key (4b951c9) |
| A half-done migration wasn't reported | Only success/failure outcomes | `.failed(reason, moved:)` with a "partly moved" notice (7401f4e) |
| Relaunch sometimes left Bugeye without hotkeys | New instance started while the old one still held the Carbon hotkeys (`sleep 0.5`) | Poll the old PID for up to 5 s (50cb419) |
| Launch at login silently waiting for approval | `.requiresApproval` status not shown | Settings shows it with "Open Login Items" (8e99b67) |
| Opening Settings or building any `SettingsModel` was slow | Apple Events browser lookup ran in `init` | Lookup only in `refreshStatus()` (Settings shown), off main (f490df7) |
| Settings window not resizable / forgot its size | Fixed-size window | `.resizable`, `contentMinSize = fittingSize` set before the first layout, frame autosave (M6 part 4) |
| Scrolling session: Return ended the capture instead of answering a Bugeye alert | Global Return hotkey active while a Bugeye modal had the keyboard | Session keys step aside while a Bugeye key or modal window exists (4546416) |
| Menu-bar timer froze while the ● menu was open | Timer only in the default run-loop mode | Schedule in `.common` modes (1e641b5) |
| "Shortcuts still on" missed on Touch Bar Macs | Entry 181 (⇧⌘6) is absent until changed, but on by default on Touch Bar models | `defaultEnabled(hasTouchBar:)` from a `hw.model` list (23dce4c) |
| Night buttons gave no feedback when disabled; VoiceOver didn't read toggle state | Plain styles | Disabled opacity 0.4, hover fill, `.isToggle` + "On"/"Off" (7c326e4) |
| Slow clipboard on large captures | Eager TIFF encode | PNG only up front; TIFF (and later HTML) via lazy providers (2adb4dd) |
| Open Last Capture opened a deleted file | Enabled state set at capture time | Checked in `menuNeedsUpdate` (60d29d1) |
| Collections opened from Finder at launch were lost | `application(_:open:)` arrives before `applicationDidFinishLaunching` | Queue in `pendingCollections` (a2bb26c) |

---

## 4. Known open issues (from `docs/backlog.md`)

Shell-related only (capture and Quick Access items are in file 02):

- A scrolling capture started while a Bugeye window (an editor) is key never registers the global Esc/Return: the session keys step aside for any Bugeye key window.
- `AreaSelectionController` has no `deinit` safety net: dropping a selection without `finish` would leave the global Esc registered. Unreachable today.
- Editor memory: after typing in one editor while another is open, closing the first keeps its canvas alive, held by an observer AppKit registers in `-[NSView _commonAwake]` (pre-existing).
- Launch-time costs from the search index (`PRAGMA quick_check`, one-at-a-time deletes, O(n²) enqueue on a first backfill, thumbnail re-render per indexed file).
- Temp captures are only purged at launch (not in the backlog, but true of the code).

---

## 5. Do it better next time

1. **Name things once.** Pick the product name before the first commit, and make the bundle id, signing identity, module names and folder match it. The rename cost a migration, a login-item re-registration, LaunchServices cleanup and a TCC path re-confirmation.
2. **Keep the toolchain rules in a checked-in file from day one** (CLT-only: Swift Testing, plugin path, no `@State`/`@Observable`, check macro plugins). Each one cost debugging time because the compile errors are misleading.
3. **Push more into Swift 6 targets.** Wrap each Apple framework in a thin Swift 5 (or `@preconcurrency import`) adapter that exposes Sendable values, and keep the app's controllers in Swift 6 where possible. Today the whole app target is Swift 5, which hides real cross-thread mistakes.
4. **Replace the 460-line AppDelegate closure web with a small composition root.** A `Services` struct (router, quick access, editors, indexer, sweep, …) and an event bus for "item changed / saved / deleted" would remove the manual chaining of `onItemChanged` and the many `[weak self]` hand-offs.
5. **One hotkey registry.** Model every global hotkey (permanent and temporary) as data with an owner and a lifetime. Assert in debug builds that no temporary bare-key hotkey outlives its owner (the missing `deinit` net above).
6. **Purge temp files periodically**, not just at launch (a timer or on each delivery).
7. **Derive paths from `Bundle.main.bundleIdentifier`** (or one constant) instead of repeating `dev.msenechal.cleanshotcopy` and `Bugeye` in several files.
8. **Make the Settings window SwiftUI-only state objects small.** `SettingsModel` mixes persisted settings, permission status, login item and index counts; split them so tests and refreshes are cheaper.
9. **Keep `make install`'s LaunchServices hygiene** even without a rename: unregister stale `build/` copies so `open -b` and notifications never pick a dev build.
10. **Log more categories** (capture, quick-access, hotkeys, recording) from the start. The unified log was the only way to debug the installed app, and it was added only after the stuck-overlay hunt.
11. **Test hygiene from day one:** no synchronous run-loop spinning in tests, generous main-queue timeouts, every window-opening test identifies its own window, and serialise (or tag) the AppKit-heavy tests.

### 5.1 Portable core vs macOS shell (for the Linux-first rebuild in `13-rebuild-strategy-agentic-ci-and-claude.md`)

What in this area can live in the portable core (Linux-testable, no AppKit/CoreGraphics drawing/ImageIO) and what must stay in the macOS shell:

| Portable core | macOS shell (thin adapters) |
|---|---|
| `AppSettings` value type, defaults, validation and clamping, behind a `KeyValueStore` port (UserDefaults adapter on macOS, in-memory fake on Linux) | `UserDefaults` adapter, Settings window (SwiftUI `Form` in `NSHostingController`), frame autosave |
| `HotkeyRoute` (routing table) and a hotkey **registry model**: bindings as data, temporary keys with an owner and a lifetime, "session keys allowed" rule as a pure function of (key window?, modal?) | Carbon `RegisterEventHotKey` adapter, event handler, main-queue hop, NotificationCenter observers |
| `RecordingPhase`, `LoginItemSetup.plan`, `ShortcutConflicts` (given the parsed symbolic-hotkeys dictionary and `hw.model` string), `FolderMigration` (behind a `FileSystem` port), `TempJanitor`, `DiskGuard` decisions (given free bytes) | `SMAppService`, `com.apple.symbolichotkeys` read, `sysctlbyname`, `volumeAvailableCapacityForImportantUsage`, real `FileManager` |
| Menu **model**: items, titles, display shortcuts, enabled rules (`canOpen(lastItem)`, `canRecordGuide`), the recording title text (`● mm:ss`, `❙❙`) | `NSStatusItem`, `NSMenu`, template glyph image |
| Notification **texts** (every title/body string above as functions of outcomes) behind a `Notifier` port | `UNUserNotificationCenter` adapter with the bundle guard |
| Permission **state model** and Setup-row texts (granted / not determined / denied → title + button) | TCC calls (`CGPreflightScreenCaptureAccess`, `AXIsProcessTrusted`, `AVCaptureDevice`, `AEDeterminePermissionToAutomateTarget`), deep links, relaunch script |
| Clipboard **payload model** (`png`, `fileURL`, lazy `tiff`, lazy `html` data URI, `text`) behind a `ClipboardWriter` port | `NSPasteboardItem` + lazy data providers |
| Night-chrome **tokens** (hex values, opacities) and the icon/glyph as a display list | SwiftUI styles, `NSAppearance(.darkAqua)`, Core Graphics execution of the display list, `iconutil` |
| `DocumentWindows` counter (open count → policy) | `NSApp.setActivationPolicy` |

Shell-only, by nature: `main.swift`, `Info.plist`, `bundle.sh`, the signing script and keychain, `lsregister` cleanup, `make install`. Keep signing with the stable "CleanShotCopy Dev" identity on the user's Mac (or a self-hosted runner there); CI builds can be ad-hoc signed because they never need TCC grants that must survive.

The composition root (today's AppDelegate) should also be split: a portable `AppCore` that wires view models, routing and the event bus (testable on Linux with fakes), and a macOS `AppDelegate` that only builds the adapters and hands them to it.
