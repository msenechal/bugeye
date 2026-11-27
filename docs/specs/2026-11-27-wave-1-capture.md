# Wave 1: Capture

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → Mac batch → manual pass

Capture rebuilds the first build's still captures (`design/02` §1.1–1.3): full screen, every display, area and window, the selection overlay, and output (save, copy, announce). It runs as one of the parallel Wave 1 sessions (`design/14` R1), on Wave 0's skeleton, and shares one contract with the Quick Access epic (§3).

## 1. Decisions

From the brainstorm (your answers):

| # | Question | Decision |
|---|---|---|
| B1 | Hotkeys | **The first build's defaults, each changeable.** ⇧⌘3 full screen, ⌥⇧⌘3 every display, ⇧⌘4 area (Space for a window). A Settings "Shortcuts" pane changes them. A key that fails to register at launch is shown there as unset, with the reason (§5.6). The old app keeps running side by side; you quit it when testing. The first build's handling of macOS's own screenshot shortcuts comes along (§5.6). |
| B2 | Behaviour | **Exactly as `design/02` §1.1–1.3 documents it**, plus the "do it better" items of §5: the overlay as a portable state machine with one owner, close not hide, begin/finish logging, all displays frozen concurrently from one `SCShareableContent` fetch (also for ⌥⇧⌘3), coordinate types that make a wrong flip fail to compile, the last area persisted per display, temp files purged periodically. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| C1 | **The contract with Quick Access lands first, alone.** PR 1 of this epic adds `CaptureItem`, `CaptureKind`, `CaptureEvent`, `CaptureEventBus`, the `Notifier` port, `HotkeySpec.title` and their fakes, nothing else (§3). The Quick Access session starts building against them only after PR 1 merges. After that, changing the contract needs a ruling in both ledgers. | Area cores can't depend on each other (Wave 0 P14), so the contract goes in `BugeyeCore`. A frozen contract is what lets the two sessions run in parallel. [Medium: a contract change after the merge costs both sessions a rework.] |
| C2 | **Capture stops at "announced".** Capture owns everything up to a saved and copied file and a `created` event on the bus. Quick Access owns thumbnails, Save, Save As, Delete, and the `saved`, `moved` and `deleted` events. Output step 3, "show Quick Access", becomes "publish `created`". | One owner per screen element. The bus replaces the first build's chained `onItemChanged` closures (`design/02` §5.9). [Low] |
| C3 | **Clipboard in Wave 1 is PNG + file URL**, on one item, through the existing `ClipboardPayload`. Lazy TIFF, lazy HTML and provenance come with the provenance and clipboard epic (`design/06`, Wave 2). | The rich clipboard has its own spec. [Low: apps that only paste TIFF get nothing until then. Mail and Notes attach the file instead of embedding it.] |
| C4 | **Screenshot purpose only.** The recording, scrolling and text overlay variants, their hints and their click rules are out of scope. The state machine still carries a `purpose`, and its tables mark where those purposes branch, so later epics add rows instead of rewriting it. | They belong to Wave 2 and later. [Low] |
| C5 | **The Shortcuts pane belongs to the shell, and this epic builds it.** Like the AI pane (Wave 0 P5), it lists every module's `HotkeySpec`, so it lives in `BugeyeFeatures` (model) and `BugeyeApp` (view). It sits before AI in Settings. Capture is the first module with hotkeys, so this epic writes it. Later modules get rows for free. `HotkeySpec` gains a `title` for the row label (part of PR 1). | No module should own a pane that serves all modules. [Low] |
| C6 | **Capture settings live in `CaptureCore`, not in `AppSettings`.** A `CaptureSettings` value is read through `SettingsStore` before each capture, under keys prefixed `capture.` (§5.7). Quick Access does the same with its own keys. | Two parallel sessions editing the shared `AppSettings` struct would collide. The old app uses a different bundle id, so there's nothing to migrate. [Low] |
| C7 | **Frozen frames stay native images in the shell.** The core works on geometry (rects, scales, pixel crops) and on decisions. A macOS `ImagePipeline` adapter crops, downscales and encodes PNG with ImageIO, keeping each display's colour space. Pixels reach the core as `PixelBuffer` only where it needs them: window-shadow measurement on the window capture's alpha channel. | `PixelBuffer` has no colour space, and colours drifted on P3 displays once already (`design/05` A3). Copying a 6K display into RGBA8 just to crop it wastes about 80 MB and time. [Medium: if a later epic needs whole frozen frames in the core, it adds a conversion.] |
| C8 | **Ports this epic changes or adds in `BugeyeCore`** (PR 2 onward, each with a ledgered ruling, Capture-only users): `ScreenSource` is reshaped to `freeze(displays:)` (one content fetch, concurrent, own windows excluded) plus `captureWindow(_:pixelSize:)`. New: `WindowListReader`, `ImagePipeline`, `ScreenCapturePermission`, `HotkeyRegistrar` and `SystemShortcutReader`. `DisplayInfo.frame` is documented as **Cocoa global** points. `CaptureFileWriter` gains `create(_:named:in:identity:)`, which never replaces an existing file (it uses `renameatx_np(RENAME_EXCL)` / `renameat2(RENAME_NOREPLACE)`, and on a clash the namer tries the next suffix). | Wave 0 allows port changes with a ruling. Without them `.withoutOverwriting` can't hold: the writer renames over its target. [Medium: these are shared files, so later waves inherit the shapes.] |
| C9 | **Return recaptures the last area of the display under the pointer.** Each display keeps its own last area, persisted under `capture.lastAreas` as JSON: display id → display-local rect + the display's size in points. Return beeps when that display has no stored area, its size has changed, or the crop is empty. Every area capture stores it, Return included. | "Persisted per display" (B2). With the laptop plus the 1080p external, Return on the external display keeps working after a capture on the laptop. [Low: if you want "the last area anywhere", the most recent entry is one lookup away.] |
| C10 | **One timestamp per press for ⌥⇧⌘3.** Every display is frozen at once, so all files share the press time. Names take ` (2)`, ` (3)` in display order (primary display first, then `ScreenSource` order). For every mode, a file's name and `createdAt` are the moment its pixels were taken: freeze time for full screen, every display and area; live-capture time for a window. | Follows from the concurrent freeze. The first build's files carried different seconds (`design/02` §4). [Low] |
| C11 | **Temp folder `~/Library/Caches/dev.msenechal.bugeye/Captures/`**, from one constant derived from the bundle id (`design/01` §5.7). Files older than 24 h are purged at launch and then every hour, off the main actor. | The documented path carries the old bundle id. Periodic purge is B2. [Low] |
| C12 | **One action router in the shell.** `FeatureModule` is pure values. `AppServices` gains a map from menu-item and hotkey ids to `@MainActor` closures, which `AppDelegate`'s default branch looks up. The capture module joins `AppServices.modules` only in the epic's last PR, so `main` never shows half a feature. No feature flag. | The first module with actions builds the hook once. [Low] |
| C13 | **macOS screenshot-shortcut conflicts are detected only for keys Bugeye binds.** The shell reads `com.apple.symbolichotkeys` and compares each enabled macOS screenshot entry's key with Bugeye's current bindings. These are entries 28 ⇧⌘3, 29 ⌃⇧⌘3, 30 ⇧⌘4, 31 ⌃⇧⌘4, 184 ⇧⌘5 and 181 ⇧⌘6, with 181 counted as on when missing only on Touch Bar models (`design/05` A2). A conflict is not a registration failure: Carbon succeeds, but macOS gets the key first. The Wave 1 notice names only the conflicting keys. | The first build's body text also lists ⇧⌘5–⇧⌘9, which Bugeye doesn't bind yet. [Low: the entry numbers are checked in the Mac batch.] |
| C14 | **No Settings "Setup" section in Wave 1.** The permission alert (§5.5) is the only permission UI. Settings doesn't open by itself at launch. Problems with shortcuts show as a notice and in the Shortcuts pane. | The Setup section serves the five permissions of later waves. It comes with the first epic that needs a second one. [Low] |
| C15 | **New strings the docs don't give**, settled in §5: the `Capture failed` bodies for a failed disk write, a closed window and a lost display, and every Shortcuts-pane string. | Every string is settled before implementation (`design/11` §7). [Low] |
| C16 | **A display change during selection cancels it.** Plugging, unplugging or rearranging a display while the overlay is up cancels the selection: overlays close and the result is `cancelled`. | Frozen frames and window lists go stale. The first build left this undefined. [Low] |
| C17 | **Testing split** (§8): the portable core on Linux; the AppKit wiring, ImageIO and pasteboard on hosted macOS CI; real ScreenCaptureKit, permission, hotkeys against the old app, and the overlay's look in the Mac batch and your manual pass. Every PR that touches capture gets the `needs-mac-check` label. | Hosted runners can't grant Screen Recording (`design/14` R8, R9). [Low] |

## 2. Scope

In scope:
1. The contract with Quick Access (§3), in its own first PR.
2. Capture modes: ⇧⌘3, ⌥⇧⌘3, ⇧⌘4 (area, Space for window, Return for the last area), and the menu items Capture Area, Capture Window, Capture Fullscreen.
3. The selection overlay for screenshots, and window captures at full scale with their shadow.
4. Output: save (with the temp fallback), copy (PNG + file URL), publish `created`; naming; temp folder and purge; downscale.
5. The Screen Recording permission alert and relaunch.
6. Global hotkeys: the Carbon registrar, the temporary Esc hotkey, the Shortcuts pane, macOS conflict detection, launch notices.
7. The Capture settings pane, notifications (the `Notifier` port and its adapter), logging.

Out of scope: Quick Access (its own epic); recording, scrolling and text capture and their overlay variants (C4); provenance, AX snapshot, sensitive sweep, indexing; Open Last Capture (it needs the editor); the rich clipboard (C3); the Settings Setup section (C14); `HotkeyRoute` rules for recording and guide; the disk guard; folder migration (the old app has its own bundle id).

## 3. The contract (PR 1)

Files: `Sources/BugeyeCore/Captures/CaptureItem.swift`, `CaptureEventBus.swift`, `Sources/BugeyeCore/Ports/Notifier.swift`, the `title` on `HotkeySpec` in `BugeyeFeatures`, `CaptureEventRecorder` and `FakeNotifier` in `BugeyeTestSupport`, and a `captureEvents` bus instance in `AppServices`. Exact shapes:

```swift
public enum CaptureKind: String, Hashable, Codable, Sendable, CaseIterable {
    case screenshot, recording, gif, collection
    /// "Screenshot", "Recording", "Recording", "Collection".
    public var namePrefix: String { get }
    /// "png", "mp4", "gif", "bugeye".
    public var fileExtension: String { get }
}

/// One capture as every module knows it. Provenance and snapshots stay on the file (xattrs), not here.
public struct CaptureItem: Hashable, Codable, Sendable, Identifiable {
    public var id: CaptureID
    public var fileURL: URL
    /// In the save folder. False: in the temp folder, until Quick Access saves it.
    public var isSaved: Bool
    public var kind: CaptureKind
    /// When the pixels were taken (C10).
    public var createdAt: Date
    /// 2 on Retina, 1 on a 1× display or after "Downscale Retina captures to 1×".
    public var pixelsPerPoint: Double
    public init(id: CaptureID, fileURL: URL, isSaved: Bool, kind: CaptureKind, createdAt: Date, pixelsPerPoint: Double)
}

/// What happened to a capture. An open set: later epics add values (provenanceAttached, snapshotAttached, …)
/// without breaking anyone's switch, so subscribers ignore changes they don't know.
public struct CaptureChange: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String)
    public static let created: CaptureChange   // a new capture's file exists
    public static let saved: CaptureChange     // moved from the temp folder into the save folder
    public static let moved: CaptureChange     // the file now lives at another URL, for any other reason
    public static let edited: CaptureChange    // the file's content was rewritten in place
    public static let deleted: CaptureChange   // trashed (saved) or removed (temp)
}

public struct CaptureEvent: Hashable, Sendable {
    public var change: CaptureChange
    /// The capture as it is after the change.
    public var item: CaptureItem
    /// For saved and moved: where the file was.
    public var previousURL: URL?
    /// For created only: the image at most 480 px wide, so no subscriber decodes the full file.
    public var preview: PixelBuffer?
    /// The publishing module's id ("capture", "quickAccess", …).
    public var origin: String
    public init(change: CaptureChange, item: CaptureItem, previousURL: URL? = nil, preview: PixelBuffer? = nil,
                origin: String)
}

/// The one "capture changed" channel (design/02 §5.9). Main actor, synchronous, deterministic.
@MainActor
public final class CaptureEventBus {
    public init()
    /// Handlers run in subscription order. An event published from inside a handler is queued and
    /// delivered after the current one has reached every subscriber, so all subscribers see one order.
    public func subscribe(_ handler: @escaping @MainActor (CaptureEvent) -> Void) -> CaptureSubscription
    public func publish(_ event: CaptureEvent)
    /// The latest item for a capture after every event so far; nil if never created or deleted.
    /// A late result (provenance, snapshot, sweep) looks the capture up here to find its current file.
    public func item(_ id: CaptureID) -> CaptureItem?
}

@MainActor
public final class CaptureSubscription {
    /// Stops delivery. Dropping the subscription also cancels it.
    public func cancel()
}

/// User notifications (UNUserNotificationCenter on macOS).
public protocol Notifier: Sendable {
    func post(title: String, body: String)
}

// BugeyeFeatures: HotkeySpec gains a label for the Shortcuts pane (C5).
public struct HotkeySpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var defaultKey: KeyCombo
    public var settingKey: String
    public init(id: String, title: String, defaultKey: KeyCombo, settingKey: String)
}
```

Contract rules, each a test in PR 1:
- `publish` delivers to every live subscriber, in subscription order. A cancelled or dropped subscription gets nothing.
- Nested publishes are delivered FIFO after the current event, to everyone.
- `item(_:)` follows `created`, `saved`, `moved` and `edited`, and forgets the capture on `deleted`. A change for an unknown id is still delivered, but not stored.
- `CaptureKind` prefixes and extensions are exactly as above.

## 4. Coordinates and geometry

Each `design/02` §2.2 space is a type in `CaptureCore` that wraps `Point2D`/`Rect2D` and carries its space and unit: `CocoaPoint`/`CocoaRect` (global, bottom-left of the primary display, points), `QuartzPoint`/`QuartzRect` (global, top-left, points), `ViewPoint`/`ViewRect` (one overlay view, bottom-left), `DisplayRect` (display-local, top-left, points), `PixelRect` (frozen image, top-left, pixels). There are no implicit conversions. The only bridges are named functions:
- Cocoa ↔ Quartz: `y' = primaryHeight − maxY`.
- View → display-local: `y' = displayHeight − maxY`.
- Display-local → pixels: × `scale`, rounded outward, intersected with the image; nil below 1 × 1 px.

Tests cover negative-origin displays (left of and above the primary), 1×, 2× and mixed setups. Scale is always `image pixel width / display point width`, from the captured image, never `backingScaleFactor` (`design/02` §2.3).

## 5. Behaviour

### 5.1 Modes

| Trigger (default) | Setting key | Menu item (slot `.capture`, order) | Result |
|---|---|---|---|
| ⇧⌘3 | `capture.hotkey.fullscreen` | Capture Fullscreen (40), shows the current binding | One PNG of the display under the pointer |
| ⌥⇧⌘3 | `capture.hotkey.allDisplays` | none | One PNG per display, all frozen at once (C10) |
| ⇧⌘4 | `capture.hotkey.area` | Capture Area (0), shows the current binding | Area overlay on every display |
| none | | Capture Window (30) | The same overlay, already in window mode |
| ⇧⌘4, then Space | | | Window mode (§5.3) |
| ⇧⌘4, then Return / keypad Enter | | | The last area of the display under the pointer, cropped from the new frozen frame (C9). Beeps if there is none |

Orders 10 and 20 stay free for Capture Scrolling Area and Capture Text. A request while another capture is in progress (any state but `idle`, §6) is dropped and logged. Bugeye's own windows never appear in full-screen or area captures: the freeze excludes them by process id.

### 5.2 The overlay (screenshot purpose)

Values from `design/02` §1.2, unchanged:
- **Freeze.** All displays are captured first, concurrently, from one `SCShareableContent` fetch. Each display shows its own frozen image. The capture is cropped from that frame.
- **Dim:** black at 40 % outside the selection. **Border:** 1 pt white around the selection.
- **Crosshair:** two white lines at 60 % opacity, 1 pt wide, across the whole display. Crosshair and loupe are shown at the pointer as soon as the overlay opens. The cursor is the crosshair cursor.
- **Loupe:** a 120 pt circle magnifying a 15 × 15-pixel square of the frozen image without smoothing. It has a white 2 pt ring and a red square on the pointer's pixel. It sits 20 pt below-right of the pointer, flips near the right and bottom edges, and stays fully on screen. The sample square slides inside the image at the edges and never shrinks.
- **Size readout:** `W × H` (U+00D7) in points, rounded, monospaced 12 pt medium white on a black 75 % rounded box. It sits 8 pt right of and 24 pt below the selection's corner and stays on screen.
- **⇧** locks the axis that moved less since the press. The lock starts once the selection has width and height and the pointer has moved more than 2 pt since the press. **⌥** resizes from the centre. Modifiers are re-read from every drag event.
- **Space** toggles window mode and resets the drag. **Esc**, **right-click** and the temporary global Esc hotkey cancel. **Return / keypad Enter**: §5.1.
- A click without a drag, or a selection under 4 × 4 pt, does nothing: the overlay stays.
- A selection stays on the display where the drag started, clipped to it.
- Hints: none for screenshots.
- Rendering: crosshair and loupe are moved subviews. A mouse move never redraws the frozen image. A drag invalidates only the old rect ∪ the new rect plus the label.

Window properties (`design/02` §2.8) are unchanged: borderless, `.screenSaver` level, `isReleasedWhenClosed = false`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. Finishing **closes** each window; it never only hides it (B2).

### 5.3 Window mode

- The whole display is dimmed. The hovered window is redrawn undimmed from the frozen image, with a blue 20 % fill and a 3 pt `systemBlue` border. There is no crosshair or loupe.
- Hover picks the frontmost window with layer 0, alpha > 0 and another app's process id, from the window list read when the request arrived (front-to-back). Overlays redraw only when the hovered window changes.
- Click on nothing beeps and the overlay stays. Click on a window: the overlay closes, then the window is captured **live** with its shadow on a transparent background, at the scale of the display holding its centre (fallback: the first frozen display's scale, then 2).
- Full scale: capture at window size × scale, find the body by opacity (alpha ≥ 128, each edge measured at ¼, ½ and ¾, agreeing within 2 px), and if `body.width / window.width < scale × 0.99`, capture again at `size × scale / got`. Otherwise, or if no body is found, keep the first image (`design/02` §2.5).

### 5.4 Output

After each still capture, in this order:
1. **Save** (`capture.saveToFolder`, on by default) to the folder in General ("Save captures to"), through `CaptureFileWriter.create` with a new `CaptureID` (C8). If the folder is unusable, the file goes to the temp folder (C11) and this notice is posted. `<path>` is shown as the General pane shows it (`~/…`):
   - `Couldn't save to folder` / `<path> is unavailable. The capture is kept temporarily; use Save in Quick Access.`

   With saving off, the file goes to the temp folder.
2. **Copy** (`capture.copyToClipboard`, on by default): one item holding the PNG and the file URL (C3).
3. **Announce:** publish `CaptureEvent(change: .created, item:, preview:, origin: "capture")`.

- **Format:** PNG at native resolution. **Downscale** (`capture.downscaleToPoints`, off by default) scales by 1/scale before encoding when scale > 1, with high-quality interpolation in the display's colour space. `pixelsPerPoint` is then 1.
- **Names:** `Screenshot YYYY-MM-DD at HH.MM.SS.png` (local time zone, `en_US_POSIX`). A taken name gets ` (2)`, ` (3)`, … before the extension. Bugeye never overwrites an existing file (C8).
- **Failures** (title `Capture failed`), body by cause:
  - PNG encoding: `Could not encode PNG.`
  - Even the temp write failed, with copy on: `Couldn't write the file. The image is on the clipboard.` The clipboard gets the PNG alone, and no event is published.
  - Even the temp write failed, with copy off: `Couldn't write the file.`
  - The window closed before its live capture: `The window closed before it could be captured.`
  - A display disappeared between freeze and crop: `The display was disconnected.`
  - Any other ScreenCaptureKit error: its `localizedDescription`.

### 5.5 Permission

`ScreenCapturePermission.preflight` runs before every request. If Screen Recording is missing, or ScreenCaptureKit reports `userDeclined`, nothing is captured and this alert shows (`design/01` §2.8):
- Title `Screen Recording permission needed`, text `Enable Bugeye under Privacy & Security → Screen & System Audio Recording, then relaunch the app.`, buttons `Open System Settings` / `Relaunch` / `Cancel`.
- **Open System Settings** calls `CGRequestScreenCaptureAccess()`, which adds Bugeye to the list, then opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- **Relaunch** spawns `/bin/sh -c`, which polls `kill -0 <pid>` every 0.1 s for up to 5 s, then `open`s Bugeye's own bundle path, and Bugeye terminates. Relaunching by path keeps the old app, in `/Applications`, out of it.

### 5.6 Hotkeys and the Shortcuts pane

Registration: Carbon `RegisterEventHotKey` through `HotkeyRegistrar`, at launch and whenever a binding changes. The signature is the 4-char code `'BgEy'`, distinct from the old app's `'CSC!'`. While any overlay is up, bare Esc is a temporary hotkey, registered on entering `selecting` and released on leaving it (§6 I3). It never outlives the selection.

A binding is stored as its `KeyCombo` description (`⇧⌘3`). `none` means cleared; a missing or invalid value means the default. A valid binding is a letter or digit with at least one of ⌘, ⌥ or ⌃. A binding that fails to register stays stored and is retried at every launch and by Try Again, so quitting the old app and pressing Try Again (or relaunching) brings it back.

**Pane** `Shortcuts` (C5, before AI). One row per `HotkeySpec`, labelled with its title: `Capture Fullscreen`, `Capture All Displays`, `Capture Area`. Each row has a shortcut field:
- It shows the combo, or `None` when cleared or not registered.
- Clicking it shows `Type a shortcut`. The next valid combo is saved and registered. Esc keeps the old one. Delete clears it.
- Footer: `Click a shortcut, then type the new keys. Delete clears it; Esc keeps the old one.`
- Button `Restore Defaults` sets every row back to its default.

Row messages (orange ⚠ under the row; at most one, in this priority):

| Case | Message | Button |
|---|---|---|
| Registration failed (key held by another app, the old Bugeye included) | `<key> is taken by another app, so this action has no shortcut. Quit that app and press Try Again, or choose another shortcut.` | `Try Again` |
| macOS screenshot shortcut on for the same key (C13) | `macOS also uses <key> for its own screenshots and gets it first. Turn it off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots.` | `Keyboard Shortcuts…` (opens `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`) |
| Typed combo already bound to another row; not saved | `<key> is already used by <title>.` | |
| Typed combo invalid; not saved | `Use a letter or digit with at least one of ⌘, ⌥ or ⌃.` | |

**Launch notices**, at most one of each per launch, after notification authorization is answered. `<keys>` joins combos as `A`, `A and B`, `A, B and C`:
- macOS conflict: `macOS screenshot shortcuts are still on` / `Disable <keys> in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, so Bugeye receives them.`
- Registration failed: `Some Bugeye shortcuts are taken` / `<keys> is taken by another app. Choose another in Bugeye Settings → Shortcuts.` for one key, or `<keys> are taken by other apps. Choose others in Bugeye Settings → Shortcuts.` for several.

### 5.7 Capture pane and settings

Pane `Capture` (module `capture`, order 10, after General). It has one section, `After capture`, with three toggles: `Copy to clipboard`, `Save to folder`, `Downscale Retina captures to 1×`. The folder itself stays in General.

| Key | Type | Default |
|---|---|---|
| `capture.copyToClipboard` | Bool | true |
| `capture.saveToFolder` | Bool | true |
| `capture.downscaleToPoints` | Bool | false |
| `capture.lastAreas` | String (JSON, C9) | empty |
| `capture.hotkey.fullscreen` / `.allDisplays` / `.area` | String | `⇧⌘3` / `⌥⇧⌘3` / `⇧⌘4` |

Settings are read fresh at each request. Notifications: the `Notifier` adapter becomes the `UNUserNotificationCenter` delegate, so banners show while Bugeye is frontmost. It asks for `.alert` and `.sound` at launch, and logs through `NSLog` when there is no bundle id (`design/01` §2.13).

## 6. The capture state machine

`CaptureFlow` in `CaptureCore` is the single owner of a capture: it is pure, has no AppKit, and is tested on Linux. The shell feeds it events and performs the effects it returns. Every overlay window and every view event carries the `SessionID` that created it, and an event from another session is ignored. Together with I1, that makes the stuck overlay inexpressible: no handler can show or key a window. Only the `showOverlays` and `makeKey` effects can, and the machine emits them only in `selecting` for the live session.

**States:** `idle` · `freezing(session, request)` · `selecting(session, purpose, mode: .area | .window, drag?, hovered?)` · `finishing(session)` (window live capture, encode, save, copy, publish) · back to `idle`. `purpose` is `.screenshot` in Wave 1 (C4).

**Events:** `request(kind, permitted)` with kind ∈ {fullscreen, allDisplays, area, window} · `frozen(frames, windows, pointer)` / `freezeFailed(error)` · from views: `pointerMoved`, `pointerEntered(display, buttonDown)`, `mouseDown`, `mouseDragged` (both with modifiers), `mouseUp`, `rightMouseDown`, `key(.escape | .space | .return)` · `globalEscape` · `displaysChanged` · `windowCaptured(image)` / `windowCaptureFailed(error)` · `delivered(outcome)`.

**Effects:** `readWindowList`, `freeze(displays)`, `showOverlays(session, displays, mode)`, `closeOverlays(session)` (close + leftover sweep), `sweepLeftovers`, `makeKey(display)`, `redraw(display, damage)`, `registerEscape`, `unregisterEscape`, `activateBugeye`, `reactivate(previousApp)`, `beep`, `captureWindow(id, pixelSize)`, `deliver(source, scale, time)`, `storeLastArea`, `showPermissionAlert`, `notify(title, body)`, `log(category, message)`.

| From | Event | To | Effects |
|---|---|---|---|
| idle | `request`, not permitted | idle | `showPermissionAlert` |
| idle | `request(fullscreen \| allDisplays)` | freezing | `freeze` (display under pointer, or all) |
| idle | `request(area \| window)` | freezing | `readWindowList`, `freeze(all)` |
| any but idle | `request` | same | `log("busy")` |
| freezing | `frozen`, full-screen kinds | finishing | `deliver` per display, in display order |
| freezing | `frozen`, area/window | selecting | `sweepLeftovers`, `showOverlays`, `registerEscape`, `activateBugeye`, `makeKey(pointer display)`, `log(begin)` |
| freezing | `freezeFailed(userDeclined)` | idle | `showPermissionAlert` |
| freezing | `freezeFailed(other)` | idle | `notify(Capture failed, …)` |
| selecting | `pointerEntered(d, buttonDown: false)` | same | `makeKey(d)` |
| selecting | area: `mouseDown`/`mouseDragged` | same | drag rules (§5.2), `redraw(old ∪ new)` |
| selecting | area: `mouseUp`, rect ≥ 4 × 4 pt | finishing | `storeLastArea`, *leave*, `deliver(crop of frozen frame)` |
| selecting | area: `mouseUp`, smaller | same | drag cleared |
| selecting | `key(.return)`, last area valid (C9) | finishing | `storeLastArea`, *leave*, `deliver(crop)` |
| selecting | `key(.return)`, otherwise | same | `beep` |
| selecting | `key(.space)` | same, mode toggled | drag reset, redraw all |
| selecting | window: `pointerMoved` | same | hovered updated; `redraw` only if it changed |
| selecting | window: `mouseDown`, nothing hovered | same | `beep` |
| selecting | window: `mouseDown` on a window | finishing | *leave*, `captureWindow` |
| selecting | `key(.escape)`, `rightMouseDown`, `globalEscape`, `displaysChanged` | idle | *leave* with result `cancelled` |
| finishing | `windowCaptured` | finishing | full-scale rule (§5.3), then `deliver` |
| finishing | `windowCaptureFailed` | idle | `notify` |
| finishing | `delivered` | idle | `notify` for any warning |
| any but selecting | any view event, `globalEscape` | same | none (stale-session events: `sweepLeftovers` only) |

*Leave* means `closeOverlays`, `unregisterEscape`, `reactivate(previousApp)` and `log(finish)`, in that order. The recording, scrolling and text purposes will branch on click-without-drag and on window clicks (`design/02` §1.2); C4 leaves those rows for them.

**Invariants** (each a test that drives random event sequences, plus named regression tests):
- I1. Overlays exist only in `selecting`. `showOverlays` and `makeKey` are emitted only there, and `makeKey` only with no button down.
- I2. Leaving `selecting` emits `closeOverlays` and `unregisterEscape` exactly once.
- I3. The Esc hotkey is registered exactly while the state is `selecting`.
- I4. Every `request` that leaves `idle` returns to `idle` exactly once, so the busy state always clears, on every failure path too.
- I5. Each `selecting` ends in exactly one result: area, window or cancelled.
- I6. In area mode, the selection rect stays inside the display where the drag started.
- I7. Events tagged with another session never produce effects other than `sweepLeftovers`.
- I8. `log(begin)` and `log(finish)` come in pairs, with the same window numbers.

Regression tests carried over by name (`design/02` §3.1): `aFinishedSelectionsOverlayIsNotBroughtBackByTheMouseEntering`, `leftoverOverlaysAreClosedWhenASelectionBeginsOrEnds`, `escapeHotkeyIsHeldWhileTheOverlayIsUpAndCancels`, `escapeHotkeyIsReleasedWhenAnAreaIsChosen`, `rightClickCancelsTheSelection`.

## 7. Architecture

| Target | Platform | Capture's content |
|---|---|---|
| `BugeyeCore` | portable | PR 1: the contract (§3). Later: the port changes in C8 and `CaptureFileWriter.create` |
| `BugeyeFeatures` | portable | `HotkeySpec.title` (PR 1). The Shortcuts pane model: bindings, validation, duplicate and conflict detection (`ShortcutConflicts`, given the parsed `symbolichotkeys` dictionary and the `hw.model` string), row messages, launch-notice texts, `ShortcutStrings`. `SettingsLayout` gains the Shortcuts pane |
| `BugeyeTestSupport` | portable | `CaptureEventRecorder`, `FakeNotifier` (PR 1). Fakes for every C8 port, with a call counter on `freeze` so "one content fetch per freeze" is testable |
| `CaptureCore` | portable | `CaptureModule` (menu items, hotkeys, Capture pane); coordinate types (§4); `SelectionGeometry` (axis lock, from-centre, capturable, loupe sample and frame, size readout frame); `CaptureFlow` (§6); `WindowHitTest`; `WindowShadow` on a `PixelBuffer` alpha channel with an injected capture closure; `FileNamer`; `OutputRouter` (save → copy → publish, fallbacks, warnings); `LastAreaStore`; `TempJanitor`; `CaptureSettings`; `CaptureStrings` |
| `MacAdapters` | macOS | ScreenCaptureKit `ScreenSource` (one fetch, task group, own-PID exclusion, error mapping); `CGWindowList` reader; ImageIO `ImagePipeline` (crop, downscale, PNG, `CGImage` ↔ `PixelBuffer`); `NSPasteboard` clipboard; `UNUserNotificationCenter` notifier; permission adapter; Carbon registrar; `symbolichotkeys` and `hw.model` reader |
| `BugeyeApp` | macOS | Overlay windows and views (render state, translate `NSEvent`s into `CaptureFlow` events, nothing else); Capture and Shortcuts panes; permission alert and relaunch; the action router (C12); wiring in `AppServices`; the hourly purge timer |

Main thread: freezing, window capture, encoding, writing and purging run off the main actor. Only `CaptureFlow`, the views and the bus are on it.

## 8. Logging

`os.Logger`, subsystem `dev.msenechal.bugeye`. Window titles are never logged.

| Category | Messages |
|---|---|
| `selection` | `begin <purpose> overlays [<window numbers>]` · `finish <area\|window\|cancelled> overlays [<window numbers>]` · error `closing a leftover overlay <n>` |
| `capture` | `freeze <n> displays in <ms> ms` · `busy: dropped <kind>` · `saved <file name>` / `kept in temp <file name>: <reason>` · `failed <kind>: <error>` · `purged <n> temp files` |
| `hotkeys` | `registered <id> <combo>` · `taken <id> <combo>` · `macOS conflict <combo>` · `escape on` / `escape off` |

Read with `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`. Do this before killing the app, if an overlay ever sticks.

## 9. Done when

1. PR 1 (the contract) has merged, and the Quick Access session has been told.
2. `linux` and `macos` are green on every PR of the epic, and `claude-review` has posted on each. Linux covers §4, §6 (with I1–I8 and the named regressions), geometry, hit test, window shadow, naming, the output order and every fallback, the last-area store, the purge, the bindings and conflicts, and every string in §5, character for character. macOS CI covers the overlay window's properties and its close-on-finish behaviour, a late `mouseEntered` after finish, damage rects, translation of synthetic `NSEvent`s, the ImageIO round trip with the colour space kept, the pasteboard item (PNG + file URL), the menu, and both panes.
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. The Mac batch (`needs-mac-check`) passes on your Mac:
   1. Real freeze on the Retina display and the 1× external: one content fetch, freeze time logged, Bugeye's windows absent.
   2. Window capture of a 400 × 300 fixture window on each display: body within 2 px of full scale, shadow present, transparent background.
   3. Permission: after `tccutil reset ScreenCapture dev.msenechal.bugeye`, the alert appears and Relaunch restarts Bugeye.
   4. With the old app running: its keys show as taken in the pane, and the taken notice appears. Quit it, press Try Again, and the keys work.
   5. The `symbolichotkeys` entry numbers in C13 match this macOS version.
5. Your manual pass, `docs/checklists/wave-1-capture.md` (`design/11` §5 format), with these sections: Before you start (quit the old app; grant Screen Recording) · Shortcuts table · How to check (`ls ~/Pictures/Bugeye`, `ls ~/Library/Caches/dev.msenechal.bugeye/Captures`, `log show …`) · A. Full screen and every display · B. Area overlay: freeze, dim, crosshair, loupe, readout, ⇧, ⌥ · C. Multi-display drags and keys · D. Window mode and shadow · E. Return on each display, after a relaunch · F. Esc, right-click, display unplugged · G. Output: names, save off, folder unplugged, downscale, paste into Slack, Finder and Preview · H. Permission alert · I. Shortcuts pane: change, clear, duplicate, macOS conflict, Restore Defaults.
6. You say "all good", and the last PR merges.
