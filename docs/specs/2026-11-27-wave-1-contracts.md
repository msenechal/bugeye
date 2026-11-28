# Wave 1: Contracts

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** spec (this) → plan → execution → final review → fix pass

Wave 1 runs five epics in five parallel cloud sessions (`design/14` R1): Capture, Quick Access, Editor core, Recording core, and the OCR word map. Before any of them starts, one session lands one small pull request, **the Wave 1 contracts PR**, holding every shared type, port, protocol and app-shell change the five epics need. After it merges, each epic writes only inside its own folders (§3), and a CI check enforces that. This spec reconciles the five epic specs (`docs/specs/2026-11-27-wave-1-{capture,quick-access,editor,recording,ocr}.md`) against what Wave 0 actually built (branch `feat/wave-0`, ledger `docs/ledgers/wave-0.md`). Each epic spec now has a short "Uses from the contracts" section pointing here; where they disagree, this spec wins.

## 1. Decisions

There was no brainstorm: the five epic specs are the input. Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| K1 | **One contracts PR lands first, alone, from one session.** Branch `feat/wave1-contracts`, from `main` once Wave 0 has merged; ledger `docs/ledgers/wave-1-contracts.md`. It absorbs Capture's former "PR 1" (Capture C1) and every epic's former "Contract needs". No epic session starts until it merges. | Every epic needs some of it; one session avoids five sessions racing on `BugeyeCore`, `BugeyeFeatures` and the shell (`design/14` §4 "contracts before code"). [Medium: the five sessions wait about a day for it.] |
| K2 | **After the merge the contract is frozen.** A change to any file marked *contract* in §3 goes through a **contract amendment PR** (branch `feat/wave1-contracts-<slug>`, contract files only, one ruling in this spec's ledger and in the ledger of every epic that uses the changed item, see §5). Epics never edit contract files on their own branches. | A late change costs several sessions a rework; making it a separate, visible PR keeps it rare and reviewed. [Medium] |
| K3 | **What counts as contract: anything two Wave 1 epics use, or the shell needs.** A port only one Wave 1 epic uses is not frozen: the contracts PR **moves** its Wave 0 declaration, unchanged, into a folder that epic owns (§4.1.9), and the epic reshapes it with a ruling in its own ledger. The next wave's contracts PR promotes it when a second user appears. | Keeps the contracts PR small and lets each epic shape its own ports (Capture C8, OCR T4, Recording V3). [Low: a promotion later is a file move.] |
| K4 | **The contracts PR implements shapes, fakes and plumbing, not features.** It writes: value types and protocols; fakes; the pure shared helpers every user needs identically (bus, writer additions, namer, folders, bindings, router, gates, menus, activity gating); the shell plumbing (wiring, panes, menus, status-item override, termination, main menu); and five small shared macOS adapters (clipboard, notifier, Screen Recording permission, Core Text measurer, `PixelBuffer` ↔ `CGImage`). Every screen, flow, overlay, panel and string table of a feature stays in its epic (§5). | `design/14` §4. The adapters are each under 100 lines and needed by two or more epics before any of them ships. [Low] |
| K5 | **Names chosen once.** Editor events are `editingStarted` / `editingEnded` (Editor's names; Quick Access's `openedInEditor` / `closedInEditor` are renamed). Quick Access placements are `primary`, `menu`, `selection` (Quick Access's names; the Editor's `.strip` had no user and `.moreMenu` is `.menu`). | The editor names describe any document window, not only the editor; the strip is Quick Access's own and takes no foreign buttons except the primary. [Low: a rename.] |
| K6 | **One action router, `ActionRouter`, in `BugeyeFeatures`** (§4.2.4). It replaces Capture C12's map inside `AppServices`, Quick Access's `QuickAccessActionHandlers`, Recording's `AppServices.actions.register` and the Editor's router. It routes status-menu items, override-menu entries, hotkeys, Quick Access actions (with Quick Access's richer handler: state, submenus, selection) and "open this capture". A duplicate registration keeps the first and is reported; launch fails on any. | Four specs designed four routers for one job. [Low] |
| K7 | **One wiring shape, and no runtime feature flags.** The contracts PR creates `Sources/BugeyeApp/Wiring/<Epic>Wiring.swift` for each epic, each an enum with `static let modules` and `static func install(_ context: AppContext)`, empty. After the merge each file belongs to its epic. Both stay empty until the epic's **last** PR, so `main` never shows half a feature. `design/14` §4's "behind its own feature flag" (a proposal, not a ruling) is not adopted; Capture C12 and OCR's contradiction 6 already chose this. | One shape instead of four (Quick Access's `ModuleWiring`, the Editor's `install -> FeatureModule?`, Recording's `AppServices` extension, OCR's `make(bus:)`). A flag would need a settings key, a Settings switch and tests for both states, for nothing the stub doesn't give. [Low] |
| K8 | **`CaptureFileWriter` gains `create` and `move`, implemented here, with one clash rule.** `create` (Capture C8) writes a new file; `move` (Quick Access Save, Recording delivery, which the Recording spec called `adopt`) moves one in, optionally renamed and with a new identity. Neither ever replaces a file: on a clash the writer itself tries `<stem> (2).<ext>`, `(3)`, … (`CaptureFileNamer.candidate`). | The writer is the one choke point (`design/11` §6) and a shared file: it can't be split across three epics. Suffixing inside the writer removes the "throw `.exists`, ask the namer, retry" loop from every caller. [Medium: later waves inherit it.] |
| K9 | **Image decoding has one owner: the OCR epic's `ImageFileReader`.** It is the only way a portable core gets a file's pixels (sRGB RGBA8, premultiplied). Capture's `ImagePipeline` (Capture-owned) works on native frozen frames only (crop, downscale, encode) and never decodes a file. The editor decodes a PNG into a `CGImage` for display in its own colour space (Editor E11) and never into a `PixelBuffer`. The one `PixelBuffer` ↔ `CGImage` conversion, with the 480 px preview, is a shared adapter here (§4.4). `PixelBuffer` is documented as RGBA8, premultiplied alpha, sRGB unless the producer documents otherwise (OCR T8, Capture C7). | Resolves Capture C8 vs OCR T11 and OCR contradictions 3–4. Quick Access never decodes (Q5). [Low: if Wave 2 needs another decoder, it extends `ImageFileReader`.] |
| K10 | **The display list is reshaped here (the Editor's §3.1 shape), and it has one executor, owned by the Editor.** The executor lives in `Sources/Mac/MacAdapters/DisplayList/`, Editor-owned in Wave 1, in the Editor's **first** macOS PR, because Recording's overlay window draws its click rings and keystroke badge through it. The `TextMeasuring` port and its Core Text adapter (with the one font mapping the executor also uses) are contract. | Editor and Recording both draw display lists (Recording §8); two executors would drift (the flip bug class). [Medium: Recording's overlay PR waits for the Editor's executor PR.] |
| K11 | **One termination gate, two stages.** `TerminationGate` (§4.2.8) asks the `ask` participants (editors with unsaved changes, which may cancel) first, then runs the `finish` participants (a recording that stops, converts and delivers; it can't cancel). It replaces Recording's `TerminationCoordinator`. | The Editor's and Recording's designs were two mechanisms for one `applicationShouldTerminate`. Asking before finishing means a cancelled quit never stops a recording for nothing. [Low] |
| K12 | **The ▶ badge on a recording's thumbnail is a decoration Recording sets.** Recording calls `thumbnailDecorations.set([.mediaBadge(text:)], for:, from: "recording")` before it publishes `created`; Quick Access draws decorations as its spec already says. `MediaTime` stays in `RecordingCore`. `CaptureItem.duration` is contract. | Quick Access Q1 left the badge "for later"; Recording assumed Quick Access draws it from `duration`. This way neither edits the other (§6 lists it as a visible outcome). [Low] |
| K13 | **The shell shows each module menu item's current hotkey.** `MenuItemSpec` gains `hotkeyID`; the status menu reads the binding through `HotkeyBindings` each time it opens, and disables a module item no handler answers. | Capture §5.1 and Recording §3.1 both want "shows the current binding"; neither can edit `MenuBarController`. [Low] |
| K14 | **The Shortcuts pane and the hotkey registrar are Capture's, in Capture-owned folders** (`Sources/BugeyeFeatures/Shortcuts/`, `Sources/BugeyeApp/Shortcuts/`). The contracts PR adds only the pane's spec to `SettingsLayout`, `HotkeySpec.title`, `HotkeyBindings` and the hotkey → router dispatch. A pane appears in Settings only once a view is registered for it. | Capture C5 builds it; other modules get rows for free from `registry.hotkeys`. [Low] |
| K15 | **Capture implements `AreaSelector` for Recording in Wave 1**, including the recording rows (hint, click selects the display, window-centre rule, a caller's last area, external cancel, `.display` and `.busy` results), and honours `ScreenActivity`. The types, a relay and a fake are contract. | One overlay owner (Recording V2, `design/11` §6). [Medium: Capture's scope grows; Recording's last PR waits for Capture's.] |
| K16 | **Folder ownership is enforced in CI.** `scripts/ownership.sh` fails a pull request from an epic branch (`feat/wave1-<epic>-<slice>`) that changes a path its epic doesn't own (§3). It runs in the `linux` job and has a self-test in `make guards`. | A CODEOWNERS-style map (`design/14` §4) only works if something reads it. 60 lines of shell. [Low] |
| K17 | **Shell strings and other shared strings are copied, not invented.** Every string here comes from an epic spec (named per string), except the fixture app's three new labels (§4.6), which are test-only. | `design/11` §7. [Low] |
| K18 | **No `Package.swift` change.** Every fake needed is of a `BugeyeCore` type (`BugeyeTestSupport` sees only `BugeyeCore`, Wave 0 P14); Quick Access's handler fake is dropped, since a handler is two closures a test writes inline. | Feature branches never edit the manifest (Wave 0 W3). [Low] |
| K19 | **No user Mac step.** Everything here is checked by `linux` and `macos` CI. The real notification banner, the permission prompt, the status item's look and the main menu in use are checked in Capture's, Recording's and the Editor's own Mac batches and manual passes. | Nothing here needs Screen Recording or a real display (`design/14` R8, R9). [Low] |

## 2. Scope

In scope:
1. `BugeyeCore`: the capture item, kinds, events and bus; the writer's `create` and `move`; the file namer; the capture folders; the Capture pane's output keys and the shared "couldn't save" notice; the `Notifier`, `ScreenCapturePermission` and `TextMeasuring` ports; `WindowID` and `DisplayInfo`'s documented frame; `PixelBuffer`'s convention; the display-list reshape; `AreaSelector`, its relay, and `ScreenActivity`; moving five single-epic ports to their owners.
2. `BugeyeFeatures`: spec changes (`HotkeySpec.title`, `MenuItemSpec.hotkeyID`, Quick Access placements and kinds, main-menu items), new registry conflicts, `HotkeyBindings`, `ActionRouter`, Quick Access's action and decoration types, `MainMenu`, `DocumentWindows`, `TerminationGate`, `StatusItemOverride`, the Shortcuts pane's spec.
3. `BugeyeTestSupport`: the new fakes and recorders; moving the moved ports' fakes.
4. `MacAdapters/Shared/`: the five shared adapters.
5. `BugeyeApp`: `AppContext`, the five wiring stubs, `AppServices` and `AppDelegate` rewired, the status menu's delegate, hotkey keys and override, the Settings pane registry, the main menu, termination, the Screen Recording alert relay, `NightChrome`.
6. `Resources/Info.plist` usage strings, three fixture-app additions, `TextCore`'s `TextServices` stub.
7. `scripts/ownership.sh`, its self-test, its `make` target and its `linux` step.
8. Updating the Wave 0 tests the reshapes break, and moving the tests of moved declarations.

Out of scope: every feature behaviour (§5's "implements" column); the Capture-only, Recording-only and OCR-only ports' new shapes (K3); the display-list executor (K10); the timeline schema (Recording-owned, §4.1.9); any Settings pane's content; any epic's strings beyond the shared ones in §4.

## 3. Ownership after the merge

`docs/backlog.md` takes appends from anyone. `design/` is read-only for everyone. Every path not listed is **contract** (owned by the contracts PR and its amendments): `Package.swift`, `Makefile`, `scripts/`, `.github/`, `Resources/`, `Sources/BugeyeFixture/`, every file of `BugeyeCore`, `BugeyeFeatures`, `BugeyeTestSupport`, `MacAdapters`, `BugeyeApp` and their tests outside the folders below.

| Epic (branch prefix) | Writes only |
|---|---|
| Capture (`feat/wave1-capture-`) | `Sources/Core/CaptureCore/` · `Tests/CaptureCoreTests/` · `Sources/BugeyeCore/Ports/Capture/` · `Tests/BugeyeCoreTests/Capture/` · `Sources/BugeyeTestSupport/Capture/` · `Tests/BugeyeTestSupportTests/Capture/` · `Sources/BugeyeFeatures/Shortcuts/` · `Tests/BugeyeFeaturesTests/Shortcuts/` · `Sources/Mac/MacAdapters/Capture/` · `Tests/MacAdaptersTests/Capture/` · `Sources/BugeyeApp/Capture/` · `Sources/BugeyeApp/Shortcuts/` · `Sources/BugeyeApp/Wiring/CaptureWiring.swift` · `Tests/BugeyeAppTests/Capture/` · `docs/*wave-1-capture*` |
| Quick Access (`feat/wave1-quick-access-`) | `Sources/Core/QuickAccessCore/` · `Tests/QuickAccessCoreTests/` · `Sources/BugeyeApp/QuickAccess/` · `Sources/BugeyeApp/Wiring/QuickAccessWiring.swift` · `Tests/BugeyeAppTests/QuickAccess/` · `docs/*wave-1-quick-access*` |
| Editor (`feat/wave1-editor-`) | `Sources/Core/EditorCore/` · `Tests/EditorCoreTests/` · `Sources/Mac/MacAdapters/DisplayList/` · `Tests/MacAdaptersTests/DisplayList/` · `Sources/BugeyeApp/Editor/` · `Sources/BugeyeApp/Wiring/EditorWiring.swift` · `Tests/BugeyeAppTests/Editor/` · `docs/*wave-1-editor*` |
| Recording (`feat/wave1-recording-`) | `Sources/Core/RecordingCore/` · `Tests/RecordingCoreTests/` · `Sources/BugeyeCore/Ports/Recording/` · `Sources/BugeyeCore/Ports/Accessibility/` · `Sources/BugeyeCore/Timeline/` · `Tests/BugeyeCoreTests/{Recording,Accessibility,Timeline}/` · `Sources/BugeyeTestSupport/{Recording,Accessibility}/` · `Tests/BugeyeTestSupportTests/{Recording,Accessibility}/` · `Sources/Mac/MacAdapters/{Accessibility,Permissions}/` · `Tests/MacAdaptersTests/{Accessibility,Permissions}/` · `Sources/BugeyeApp/Recording/` · `Sources/BugeyeApp/Wiring/RecordingWiring.swift` · `Tests/BugeyeAppTests/Recording/` · `docs/*wave-1-recording*` |
| OCR (`feat/wave1-ocr-`) | `Sources/Core/TextCore/` · `Tests/TextCoreTests/` · `Sources/BugeyeCore/Ports/Text/` · `Tests/BugeyeCoreTests/Text/` · `Sources/BugeyeTestSupport/Text/` · `Tests/BugeyeTestSupportTests/Text/` · `Sources/Mac/MacAdapters/{Text,Images}/` · `Tests/MacAdaptersTests/{Text,Images}/` · `Sources/BugeyeApp/Wiring/TextWiring.swift` · `Tests/BugeyeAppTests/Text/` · `docs/*wave-1-ocr*` |

Settings keys follow the same split: `capture.*` Capture, `quickAccess.*` Quick Access, `editor.*` Editor, `recording.*` Recording, `text.*` OCR; `saveFolder` and `ai.model` stay the shell's. Reading another epic's key is allowed only through a contract constant (`OutputSettings`, §4.1.4). A `CaptureEvent.origin` is the publishing module's `FeatureModule.id`.

**The ownership check** (`scripts/ownership.sh`, K16):
- It takes the branch from `OWNERSHIP_BRANCH`, else `GITHUB_HEAD_REF`, else the current branch, and the base from its first argument (default `origin/main`). A branch that isn't `feat/wave1-<epic>-…` for one of the five prefixes above prints `ownership: <branch> is not an epic branch, skipped` and passes.
- It lists `git diff --name-only --no-renames $(git merge-base <base> HEAD) HEAD` (a move counts as both paths) and prints `ownership <epic>: <path> belongs to <owner>` for each path outside the epic's row, `<owner>` being another epic, or `contract (needs a contract amendment, K2)`. Any line fails it.
- `scripts/test-ownership.sh` builds a throwaway git repository and proves: an owned path passes; another epic's path, a contract file, and a rename out of the epic's folder each fail with the right owner; `docs/backlog.md` passes; a non-epic branch is skipped. `make guards` runs it; `make ownership` runs the check.
- `linux.yml`: the checkout gets `fetch-depth: 0` and, for pull requests only, a step that marks the workspace safe for git inside the container (`git config --global --add safe.directory "$GITHUB_WORKSPACE"`) and runs `make ownership BASE=origin/${{ github.base_ref }}`.

## 4. The contract

Shapes are exact; doc comments state the rules the contracts PR tests. "Used by" names the Wave 1 epics.

### 4.1 `BugeyeCore`

#### 4.1.1 Captures and the bus (`Captures/CaptureItem.swift`, `Captures/CaptureEventBus.swift`; all five epics)

```swift
public enum CaptureKind: String, Hashable, Codable, Sendable, CaseIterable {
    case screenshot, recording, gif, collection
    /// "Screenshot", "Recording", "Recording", "Collection".
    public var namePrefix: String { get }
    /// "png", "mp4", "gif", "bugeye": only the default for new files. The extension of an item's `fileURL`
    /// is authoritative (a recording can be a `.mov`, Recording V8), and Save keeps it.
    public var fileExtension: String { get }
}

/// One capture as every module knows it. Provenance and snapshots stay on the file (xattrs), not here.
public struct CaptureItem: Hashable, Codable, Sendable, Identifiable {
    public var id: CaptureID
    public var fileURL: URL
    /// In the save folder. False: in the temp folder, until Quick Access saves it.
    public var isSaved: Bool
    public var kind: CaptureKind
    /// When the pixels were taken (Capture C10); a recording's first frame (Recording §5.6).
    public var createdAt: Date
    /// 2 on Retina, 1 on a 1× display or after "Downscale Retina captures to 1×"; a recording's stream scale.
    public var pixelsPerPoint: Double
    /// Seconds, for recordings and GIFs; nil for stills.
    public var duration: Double?
    public init(id: CaptureID, fileURL: URL, isSaved: Bool, kind: CaptureKind, createdAt: Date,
                pixelsPerPoint: Double, duration: Double? = nil)
}

/// What happened to a capture. An open set: later epics add values without breaking anyone's switch,
/// so subscribers ignore changes they don't know.
public struct CaptureChange: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String)
    public static let created: CaptureChange          // a new capture's file exists
    public static let saved: CaptureChange            // moved from the temp folder into the save folder
    public static let moved: CaptureChange            // the file now lives at another URL, for any other reason
    public static let edited: CaptureChange           // the file's content was rewritten in place
    public static let deleted: CaptureChange          // trashed (saved) or removed (temp)
    public static let editingStarted: CaptureChange   // a document window (the editor) opened on it; item unchanged
    public static let editingEnded: CaptureChange     // that window closed
}

public struct CaptureEvent: Hashable, Sendable {
    /// The widest a `preview` may be, in pixels.
    public static let previewMaxWidth = 480
    public var change: CaptureChange
    /// The capture as it is after the change. Publishers take it from `bus.item(id)`, not a stale copy.
    public var item: CaptureItem
    /// For saved and moved: where the file was.
    public var previousURL: URL?
    /// For created and edited: the image at most `previewMaxWidth` wide (sRGB), so no subscriber decodes the
    /// file. Nil when it couldn't be made (Quick Access then shows a generic icon).
    public var preview: PixelBuffer?
    /// The publishing module's `FeatureModule.id`: "capture", "quickAccess", "editor", "recording".
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
    /// The latest item for a capture after every event so far; nil if never created, or deleted.
    public func item(_ id: CaptureID) -> CaptureItem?
}

@MainActor
public final class CaptureSubscription {
    /// Stops delivery. Dropping the subscription also cancels it.
    public func cancel()
}
```

Rules, each a test: `publish` reaches every live subscriber in subscription order, and a cancelled or dropped subscription gets nothing; nested publishes are delivered FIFO after the current event, to everyone; `item(_:)` follows `created`, `saved`, `moved` and `edited`, forgets on `deleted`, and neither stores nor forgets on `editingStarted`, `editingEnded` or an unknown change; a change for an unknown id is still delivered, not stored; prefixes and extensions are exactly as above.

#### 4.1.2 The writer (`Files/CaptureFileWriter.swift`; Capture, Quick Access, Recording; Editor uses Wave 0's `write`)

```swift
extension CaptureFileWriter {
    public struct NoFreeName: Error, Equatable { public let name: String }

    /// Writes a new capture file into `folder`, trying `name`, then `CaptureFileNamer.candidate(name, attempt: 2…999)`,
    /// never replacing a file. The identity attribute is set before the file appears under its final name.
    /// Returns the final URL. Throws `NoFreeName` after 999 attempts; on any failure no file or temp file remains.
    public func create(_ data: Data, named name: String, in folder: URL, identity: CaptureID) throws -> URL

    /// Moves an existing file into `folder` under `name` (default: its own file name), with the same clash rule.
    /// `.keep` keeps every attribute; `.new(id)` writes `id` as the identity (onto the source first).
    /// Same volume: a no-replace rename, so every attribute follows. Another volume (`EXDEV`): a copy carrying the
    /// preserved attributes (P11) to a temp name in `folder`, a no-replace rename, then the source is removed.
    /// Returns the final URL. On failure the source is still there and no partial file remains in `folder`.
    public func move(_ source: URL, into folder: URL, named name: String? = nil,
                     identity: CaptureIdentity = .keep) throws -> URL
}
```

The no-replace primitive is `renameatx_np(…, RENAME_EXCL)` on macOS. On Linux it is `renameat2(…, RENAME_NOREPLACE)` if the Swift `Glibc` module exposes it, else `link(2)` then `unlink(2)` (both refuse an existing target); the contracts PR picks one and ledgers it. An internal seam lets Linux tests force the cross-volume path. Tests on Linux, through `FakeFileMetadataStore`: `create` suffixes on a clash and never touches the existing file; `move` same-volume keeps every attribute, `.new` replaces the id; the cross-volume path keeps the preserved attributes and removes the source; a failure leaves the source and no partial file; ` (2)` goes before the last extension only (`a.b.png` → `a.b (2).png`); `NoFreeName` after 999.

#### 4.1.3 Names and folders (`Captures/CaptureFileNamer.swift`, `Captures/CaptureFolders.swift`; Capture, Recording)

```swift
public enum CaptureFileNamer {
    /// "<namePrefix> YYYY-MM-DD at HH.MM.SS.<ext>", local time zone, en_US_POSIX, `ext` = `kind.fileExtension`
    /// unless given. "Screenshot 2026-11-27 at 14.03.12.png".
    public static func name(kind: CaptureKind, date: Date, fileExtension: String? = nil,
                            timeZone: TimeZone = .current) -> String
    /// Attempt 1: `name`. Attempt n ≥ 2: "<stem> (n).<ext>", stem = `name` without its last extension, as is.
    public static func candidate(_ name: String, attempt: Int) -> String
}

public enum CaptureFolders {
    public static let bundleID = "dev.msenechal.bugeye"   // also the os.Logger subsystem
    /// <home>/Library/Caches/dev.msenechal.bugeye/Captures/: unsaved captures; Capture's janitor purges it (C11).
    public static func temp(home: String) -> URL
    /// <home>/Library/Caches/dev.msenechal.bugeye/Recordings/: takes in progress; never purged.
    public static func recordingsInProgress(home: String) -> URL
    /// <home>/Library/Application Support/dev.msenechal.bugeye/
    public static func applicationSupport(home: String) -> URL
}
```

None of them creates a folder; callers use `SaveFolder.ensureExists`.

#### 4.1.4 Output settings and the shared notice (`Captures/OutputSettings.swift`; Capture writes the keys, Recording reads them)

```swift
/// The Capture pane's "After capture" toggles that recordings follow too (Recording V12).
public struct OutputSettings: Hashable, Sendable {
    public enum Key {
        public static let copyToClipboard = "capture.copyToClipboard"
        public static let saveToFolder = "capture.saveToFolder"
    }
    public var copyToClipboard: Bool   // default true
    public var saveToFolder: Bool      // default true
    public init(copyToClipboard: Bool = true, saveToFolder: Bool = true)
    /// Missing or non-Bool values fall back to the defaults.
    public static func load(from store: any SettingsStore) -> OutputSettings
}

/// Capture §5.4's notice when the save folder is unusable, also posted by Recording (§5.6).
public enum OutputStrings {
    public static let folderUnavailableTitle = "Couldn't save to folder"
    /// "<path> is unavailable. The capture is kept temporarily; use Save in Quick Access."
    public static func folderUnavailableBody(path: String) -> String
}
```

#### 4.1.5 Ports (`Ports/Notifier.swift`, `Ports/ScreenCapturePermission.swift`, `Ports/TextMeasuring.swift`, `Ports/Ports.swift`)

```swift
/// User notifications (UNUserNotificationCenter on macOS). Capture, Quick Access, Editor, Recording.
public protocol Notifier: Sendable {
    func post(title: String, body: String)
}

/// Screen Recording permission (CoreGraphics on macOS). Capture, Recording.
public protocol ScreenCapturePermission: Sendable {
    /// CGPreflightScreenCaptureAccess: never prompts.
    func preflight() -> Bool
    /// CGRequestScreenCaptureAccess: adds Bugeye to System Settings' list, prompting at most once.
    func requestAccess()
}

public struct TextLineMetrics: Hashable, Sendable {
    public var width: Double
    public var ascent: Double
    public var descent: Double
    public init(width: Double, ascent: Double, descent: Double)
}

/// Measures one line of text, no wrapping, in pixels at `font.size` (Core Text on macOS). Fast enough to call on
/// the main actor for short strings. Editor (text annotations, step numbers), Recording (keystroke badge).
public protocol TextMeasuring: Sendable {
    func measure(_ line: String, font: FontDescriptor) -> TextLineMetrics
}

// Ports.swift, Screen section: DisplayID stays; DisplayInfo's frame is documented as
// "Cocoa global points: origin at the bottom-left of the primary display, y up" (Capture C8).
/// A window server window id (CGWindowID). Capture's window list, the selector, Recording.
public struct WindowID: Hashable, Codable, Sendable {
    public var rawValue: UInt32
    public init(_ rawValue: UInt32)
}
```

#### 4.1.6 `PixelBuffer` (`Image/PixelBuffer.swift`, doc comment only; Capture, Quick Access, Editor, OCR)

The type's comment gains: "RGBA8 with premultiplied alpha, sRGB unless the producer documents otherwise. There is no colour-space field (Capture C7, OCR T8)."

#### 4.1.7 Display list (`DisplayList/DisplayList.swift`; Editor, Recording)

No feature uses Wave 0's list yet, so it is reshaped and its golden test rewritten. Coordinates: origin top-left, y down, in the list's own pixels (`DisplayList.size`); the executor does the one flip. Shadow offsets and blurs are in these pixels too; the executor multiplies them by the device scale when it draws into a zoomed context.

```swift
public enum LineCap: String, Hashable, Codable, Sendable { case butt, round, square }
public enum LineJoin: String, Hashable, Codable, Sendable { case miter, round, bevel }

public struct Shadow: Hashable, Codable, Sendable {
    public var offset: Point2D        // positive y falls downward
    public var blur: Double
    public var color: RGBAColor
    public init(offset: Point2D, blur: Double, color: RGBAColor)
}

public struct GroupStyle: Hashable, Codable, Sendable {
    public var opacity: Double
    public var shadow: Shadow?
    /// Composited as one layer: overlaps inside don't darken, and the shadow is cast once.
    public var isolated: Bool
    /// The layer's extent; nil is unbounded.
    public var bounds: Rect2D?
    public init(opacity: Double = 1, shadow: Shadow? = nil, isolated: Bool = false, bounds: Rect2D? = nil)
}

public struct GradientStop: Hashable, Codable, Sendable {
    public var location: Double       // 0…1
    public var color: RGBAColor
    public init(location: Double, color: RGBAColor)
}

public enum BlurEffect: Hashable, Codable, Sendable {
    case pixelate(cellSize: Double)   // pixels
    case gaussian(radius: Double)     // pixels
}

public enum DisplayCommand: Hashable, Codable, Sendable {
    case fillPath(VectorPath, color: RGBAColor)
    case strokePath(VectorPath, color: RGBAColor, lineWidth: Double,
                    cap: LineCap = .butt, join: LineJoin = .miter, dash: [Double] = [])
    /// Fills the path with a linear gradient, extended past both ends.
    case fillLinearGradient(VectorPath, stops: [GradientStop], start: Point2D, end: Point2D)
    case image(imageID: String, rect: Rect2D)
    /// `origin` is the left end of the baseline.
    case textRun(String, origin: Point2D, font: FontDescriptor, color: RGBAColor)
    /// Draws `sourceRect` (pixels of the image registered under `sourceImageID`, top-left) with `effect`
    /// applied, edges clamped to `sourceRect`, into `rect`. Samples the source only, never what was drawn before.
    case blurRegion(Rect2D, sourceImageID: String, sourceRect: Rect2D, effect: BlurEffect)
    /// Saves the graphics state and applies the style. Every push has a matching pop.
    case pushGroup(GroupStyle)
    case popGroup
    /// Intersects the clip with the path until the enclosing `popGroup`. Only valid inside a group.
    case clip(VectorPath)
}

extension VectorPath {
    /// Four cubic Béziers (κ = 0.5522847498), clockwise from the rightmost point.
    public static func ellipse(in rect: Rect2D) -> VectorPath
    /// Radius clamped to half the shorter side; 0 gives `rect(_:)`.
    public static func roundedRect(_ rect: Rect2D, cornerRadius: Double) -> VectorPath
}

extension FontDescriptor {
    /// The system UI font. The executor and the measurer map `weight` the same way (0.4 = bold,
    /// 0.3 = semibold, 0 = regular; `CoreTextFonts`, §4.4).
    public static let systemFontName = "system"
}

extension DisplayList {
    /// Pushes and pops balance, and every `clip` sits inside a group.
    public var isBalanced: Bool { get }
}
```

#### 4.1.8 Selection and gating (`Selection/AreaSelector.swift`, `Selection/ScreenActivity.swift`; Capture implements, Recording calls)

```swift
public enum SelectionPurpose: String, Hashable, Sendable { case screenshot, recording, scrolling, text }

/// An area remembered for Return: display-local, top-left origin, points. Capture C9's `capture.lastArea` JSON
/// and Recording's `recording.lastArea` both use it.
public struct StoredArea: Hashable, Codable, Sendable {
    public var display: DisplayID
    public var rect: Rect2D
    public var displaySize: Size2D
    public init(display: DisplayID, rect: Rect2D, displaySize: Size2D)
}

public struct SelectionRequest: Hashable, Sendable {
    public var purpose: SelectionPurpose
    public var startInWindowMode: Bool
    /// Drawn at the top of each display; nil for none.
    public var hint: String?
    /// A click without a drag, or a selection under 4 × 4 pt, selects the display under it.
    public var clickSelectsDisplay: Bool
    /// In window mode, a window whose centre is on no display beeps and the overlay stays.
    public var windowNeedsDisplayCentre: Bool
    /// What Return / keypad Enter returns; beeps when nil, its display is gone or changed size.
    public var lastArea: StoredArea?
    public init(purpose: SelectionPurpose, startInWindowMode: Bool = false, hint: String? = nil,
                clickSelectsDisplay: Bool = false, windowNeedsDisplayCentre: Bool = false, lastArea: StoredArea? = nil)
}

public enum SelectionResult: Hashable, Sendable {
    case area(DisplayID, Rect2D)                              // display-local, top-left, points
    case display(DisplayID)
    case window(WindowID, display: DisplayID, frame: Rect2D)  // frame in Cocoa global points
    case cancelled
    case busy                                                 // another selection or capture is in progress
}

@MainActor
public protocol AreaSelector: AnyObject {
    /// Opens the overlay for `request` and returns once it closes. Purposes other than `.screenshot` never
    /// deliver, store a last area, or capture a window: they only return the result.
    func select(_ request: SelectionRequest) async -> SelectionResult
    /// Cancels a selection opened with this purpose (no-op otherwise); `select` returns `.cancelled`.
    func cancel(_ purpose: SelectionPurpose)
}

/// What the shell hands out before Capture's selector exists. Capture's wiring sets `target` once.
@MainActor
public final class AreaSelectorRelay: AreaSelector {
    public init()
    public var target: (any AreaSelector)?
    /// Forwards to `target`; `.cancelled` while it is nil.
    public func select(_ request: SelectionRequest) async -> SelectionResult
    public func cancel(_ purpose: SelectionPurpose)
}

/// design/01 §1.2's HotkeyRoute, shared by Capture and Recording.
@MainActor
public final class ScreenActivity {
    public enum Activity: String, Hashable, Sendable {
        case screenshotSelection   // Capture: from request to idle, purpose .screenshot only
        case recordingSetup        // Recording: selecting, configuring, countingDown, starting
        case recording             // Recording: recording, paused, finishing
    }
    public enum Request: Hashable, Sendable { case screenshot, captureText, startRecording, findCapture }
    public init()
    public private(set) var active: Set<Activity>
    public func begin(_ activity: Activity)   // idempotent
    public func end(_ activity: Activity)     // idempotent
    /// screenshot: not during recordingSetup. captureText: not during recordingSetup or recording.
    /// startRecording: not during screenshotSelection. findCapture: always. Stopping a recording is never asked.
    public func allows(_ request: Request) -> Bool
}
```

#### 4.1.9 Moved, unchanged (K3)

The contracts PR moves these Wave 0 declarations, their fakes and their tests, with no shape change. The owner reshapes them later with a ruling in its own ledger.

| Declaration | From | To (owner) |
|---|---|---|
| `ScreenSource` | `Ports/Ports.swift` | `Ports/Capture/ScreenSource.swift` (Capture: becomes `freeze(displays:)` + `captureWindow`, C8) |
| `FakeScreenSource` | `BugeyeTestSupport/FakeServices.swift` | `BugeyeTestSupport/Capture/FakeScreenSource.swift` (Capture) |
| `OCRLine`, `TextReader` | `Ports/Ports.swift` | `Ports/Text/TextReader.swift` (OCR: gains `OCRWord`, `NormalizedRect2D`, T4) |
| `FakeTextReader` | `BugeyeTestSupport/FakeServices.swift` | `BugeyeTestSupport/Text/FakeTextReader.swift` (OCR: reshaped to steps, OCR §3.3) |
| `AXElementInfo`, `AXReader` | `Ports/Ports.swift` | `Ports/Accessibility/AXReader.swift` (Recording: gains `subrole`, `isSecure`, V3) |
| `FakeAXReader` | `BugeyeTestSupport/FakeServices.swift` | `BugeyeTestSupport/Accessibility/FakeAXReader.swift` (Recording) |

Owner-created, not contract: Capture's `WindowListReader`, `ImagePipeline`, `HotkeyRegistrar`, `SystemShortcutReader` (`Ports/Capture/`); OCR's `ImageFileReader`, `FileFingerprint` and `OCRWord` (`Ports/Text/`); Recording's `MediaPermissions` (`Ports/Recording/`) and the event timeline schema (`BugeyeCore/Timeline/`, read by Waves 3–4); Quick Access's `QuickAccessActionID`, `QuickAccessActivity` and `PerformedQuickAccessAction` (`QuickAccessCore`, promoted when the habits epic needs them); `MediaTime` (`RecordingCore`).

### 4.2 `BugeyeFeatures`

#### 4.2.1 Spec changes (`FeatureModule.swift`)

```swift
public struct MenuItemSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var shownKey: KeyCombo?
    public var slot: MenuSlot
    /// The menu shows this hotkey's current binding instead of `shownKey` (K13), e.g. "capture.hotkey.area".
    public var hotkeyID: String?
    public init(id: String, title: String, shownKey: KeyCombo? = nil, slot: MenuSlot, hotkeyID: String? = nil)
}

public struct HotkeySpec: Hashable, Sendable {
    public var id: String
    /// The Shortcuts pane's row label (Capture C5), e.g. "Capture Area".
    public var title: String
    public var defaultKey: KeyCombo
    public var settingKey: String
    public init(id: String, title: String, defaultKey: KeyCombo, settingKey: String)
}

public enum QuickAccessPlacement: String, Hashable, Sendable {
    /// The yellow strip button; double-click runs it too. At most one per kind across all modules.
    case primary
    /// An item of the ⋯ menu, sorted by `order` (Quick Access Q13).
    case menu
    /// Replaces the selection host's strip with one yellow button "<title> (N)". At most one.
    case selection
}

public struct QuickAccessActionSpec: Hashable, Sendable {
    public var id: String          // unique across modules, e.g. "editor.edit"
    public var title: String
    public var order: Int
    public var placement: QuickAccessPlacement
    /// The kinds it is offered for.
    public var kinds: Set<CaptureKind>
    public init(id: String, title: String, order: Int, placement: QuickAccessPlacement = .menu,
                kinds: Set<CaptureKind> = Set(CaptureKind.allCases))
}

// FeatureModule gains, with a default of []:
func mainMenuItems() -> [MainMenuItemSpec]
```

`FeatureConflict` gains, each a test: `quickAccessPrimaryTaken(CaptureKind, ids: [String])` (two `.primary` specs share a kind), `quickAccessSelectionTaken(ids: [String])` (more than one `.selection`), `duplicateMainMenuItem(String)`, `unknownHotkey(menuItem: String, hotkeyID: String)` (a `hotkeyID` no module declares). `FeatureRegistry` gains `mainMenuItems` (sorted by group, then order).

#### 4.2.2 Bindings (`HotkeyBindings.swift`; Capture writes, the shell and Recording read)

```swift
extension KeyCombo {
    /// Parses `description` ("⇧⌘3", "⌥⇧⌘3"): modifier symbols, then one character. Nil for anything else.
    public init?(description: String)
    /// A letter or digit with at least one of ⌘, ⌥ or ⌃ (Capture §5.6).
    public var isValidHotkey: Bool { get }
}

public enum HotkeyBindings {
    /// The stored value of a cleared binding.
    public static let cleared = "none"
    /// The user's binding: nil when cleared; the default when the value is missing or not a valid hotkey.
    public static func current(_ spec: HotkeySpec, in store: any SettingsStore) -> KeyCombo?
}
```

#### 4.2.3 Quick Access actions and decorations (`QuickAccess/QuickAccessActions.swift`, `QuickAccess/ThumbnailDecorations.swift`; Quick Access, Editor, Recording)

```swift
public enum QuickAccessTrigger: Hashable, Sendable { case strip, menu, doubleClick, decoration, selection }

public struct QuickAccessSubitem: Hashable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String)
}

/// Asked at every render of a thumbnail.
public enum QuickAccessActionState: Hashable, Sendable {
    case enabled, disabled, hidden
    /// A submenu under the action's title.
    case submenu([QuickAccessSubitem])
}

public struct QuickAccessActionContext: Hashable, Sendable {
    public var actionID: String
    /// The thumbnail's item; for `.selection`, the selected items in stack order, oldest first.
    public var items: [CaptureItem]
    public var trigger: QuickAccessTrigger
    public var subitemID: String?
    public init(actionID: String, items: [CaptureItem], trigger: QuickAccessTrigger, subitemID: String? = nil)
}

public struct QuickAccessActionHandler: Sendable {
    public var state: @MainActor @Sendable (CaptureItem) -> QuickAccessActionState
    public var perform: @MainActor @Sendable (QuickAccessActionContext) -> Void
    public init(state: @escaping @MainActor @Sendable (CaptureItem) -> QuickAccessActionState = { _ in .enabled },
                perform: @escaping @MainActor @Sendable (QuickAccessActionContext) -> Void)
}

public enum ThumbnailDecoration: Hashable, Sendable {
    /// Top of the image, right of ✕: app icon + short label (provenance). Tapping runs `actionID`.
    case sourceChip(label: String, appBundleID: String?, actionID: String?)
    /// Bottom-right corner: "▶ 00:42" (Recording, K12), "GIF".
    case mediaBadge(text: String)
    /// Bottom edge, centred, amber capsule. Tapping runs `actionID`.
    case warningBadge(text: String, tooltip: String?, actionID: String?)
    /// The learned usual action: a ring on its strip button, else on ⋯ plus "★ " before its menu title.
    case suggestedAction(actionID: String)
}

@MainActor
public final class ThumbnailDecorations {
    public init()
    /// Replaces everything `provider` shows on `capture`; [] removes it.
    public func set(_ decorations: [ThumbnailDecoration], for capture: CaptureID, from provider: String)
    /// All providers' decorations, providers in first-set order.
    public func decorations(for capture: CaptureID) -> [ThumbnailDecoration]
    /// Called after every `set`, with the capture it changed. Observers live as long as the app.
    public func observe(_ handler: @escaping @MainActor (CaptureID) -> Void)
}
```

#### 4.2.4 The router (`ActionRouter.swift`; all epics but OCR, and the shell)

```swift
@MainActor
public final class ActionRouter {
    public init()
    /// For a `MenuItemSpec` id or a `StatusItemOverride.Entry` id. `isEnabled` is asked each time the menu opens.
    public func onMenuItem(_ id: String, isEnabled: @escaping @MainActor () -> Bool = { true },
                           perform: @escaping @MainActor () -> Void)
    /// For a `HotkeySpec` id; Capture's registrar calls `performHotkey` when the key is pressed.
    public func onHotkey(_ id: String, perform: @escaping @MainActor () -> Void)
    /// For a `QuickAccessActionSpec` id. Quick Access shows a spec only while it has a handler.
    public func onQuickAccessAction(_ id: String, _ handler: QuickAccessActionHandler)
    /// Opens a capture of this kind (Open Last Capture now; Find Capture and Spotlight later). One per kind.
    public func onOpen(_ kind: CaptureKind, perform: @escaping @MainActor (CaptureItem) -> Void)

    /// Each returns false when nothing is registered under the id.
    @discardableResult public func performMenuItem(_ id: String) -> Bool
    public func isMenuItemEnabled(_ id: String) -> Bool        // false when unregistered
    @discardableResult public func performHotkey(_ id: String) -> Bool
    public func quickAccessHandler(for id: String) -> QuickAccessActionHandler?
    public func canOpen(_ kind: CaptureKind) -> Bool
    @discardableResult public func open(_ item: CaptureItem) -> Bool

    /// Registrations refused because the id (or kind) was already taken, as "menu:<id>", "hotkey:<id>",
    /// "quickAccess:<id>", "open:<kind>". The first registration stays. Launch fails unless this is empty.
    public private(set) var duplicates: [String]
}
```

#### 4.2.5 Main menu (`MainMenu.swift`; Editor, and later collection windows)

```swift
public enum MainMenuGroup: Int, Hashable, Sendable, CaseIterable { case app, file, edit, view }

public struct MainMenuItemSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var key: KeyCombo?
    public var group: MainMenuGroup
    public var order: Int
    /// The Objective-C selector sent to the first responder, e.g. "copyText:".
    public var action: String
    public init(id: String, title: String, key: KeyCombo?, group: MainMenuGroup, order: Int, action: String)
}

public enum MainMenuEntry: Hashable, Sendable {
    case item(MainMenuItemSpec)
    case separator
}

public enum MainMenu {
    /// The shell's fixed items (below) with module items placed by group and order.
    public static func entries(for registry: FeatureRegistry) -> [MainMenuGroup: [MainMenuEntry]]
}
```

The shell's fixed items (from the Editor spec's earlier §3.7, which this table replaces; orders leave gaps of 10 for later items: Copy Text, Copy for AI, Copy as Markdown, Find…, Snap to Elements, Export…, Open Source, Find Similar). Menu titles `Bugeye`, `File`, `Edit`, `View`; each title and key goes into `ShellStrings`:

| Menu | Order | Title | Key | Selector |
|---|---|---|---|---|
| Bugeye | 0 | Quit Bugeye | ⌘Q | `terminate:` |
| File | 0 | Save | ⌘S | `saveDocument:` |
| File | 10 | Save As… | ⇧⌘S | `saveDocumentAs:` |
| File | 20 | — | | |
| File | 30 | Close | ⌘W | `performClose:` |
| Edit | 0 | Undo | ⌘Z | `undo:` |
| Edit | 10 | Redo | ⇧⌘Z | `redo:` |
| Edit | 20 | — | | |
| Edit | 30 | Cut | ⌘X | `cut:` |
| Edit | 40 | Copy | ⌘C | `copy:` |
| Edit | 50 | Paste | ⌘V | `paste:` |
| Edit | 60 | Delete | | `delete:` |
| Edit | 70 | Select All | ⌘A | `selectAll:` |
| View | 0 | Zoom In | ⌘= | `zoomIn:` |
| View | 10 | Zoom Out | ⌘− (key `-`) | `zoomOut:` |
| View | 20 | Actual Size | ⌘1 | `zoomToActualSize:` |
| View | 30 | Zoom to Fit | ⌘0 | `zoomToFit:` |

#### 4.2.6 Document windows (`DocumentWindows.swift`; Editor)

```swift
public enum ActivationPolicy: Hashable, Sendable { case accessory, regular }

/// Counts open document windows (editors now, collection windows later).
@MainActor
public final class DocumentWindows {
    public init(apply: @escaping @MainActor (ActivationPolicy) -> Void)
    public private(set) var openCount: Int
    /// 0 → 1 applies `.regular`.
    public func opened()
    /// 1 → 0 applies `.accessory`. Below 0 is an assertion failure and the count stays 0.
    public func closed()
}
```

#### 4.2.7 Status-item override (`StatusItemOverride.swift`; Recording)

```swift
public struct StatusItemOverride: Hashable, Sendable {
    public enum Badge: Hashable, Sendable {
        case recording(elapsed: String)   // red "● " + elapsed, monospaced digits
        case paused(elapsed: String)      // "❙❙ " + elapsed
        case finishing                    // the "hourglass" SF Symbol
    }
    public struct Entry: Hashable, Sendable {
        public var id: String?            // nil: a separator
        public var title: String
        public var shownKey: KeyCombo?
        public var isEnabled: Bool
        public init(id: String?, title: String, shownKey: KeyCombo? = nil, isEnabled: Bool = true)
        public static let separator: Entry
    }
    public var badge: Badge
    public var accessibilityLabel: String
    /// Replaces the whole status menu while set. Chosen ids go to `ActionRouter.performMenuItem`.
    public var menu: [Entry]
    public init(badge: Badge, accessibilityLabel: String, menu: [Entry])
}
```

#### 4.2.8 Termination (`TerminationGate.swift`; Editor, Recording)

```swift
/// Asked when the user quits (⌘Q, Quit Bugeye in either menu).
@MainActor
public final class TerminationGate {
    public init()
    /// May cancel (an editor's unsaved-changes prompt). Asked first, in registration order; the first false
    /// cancels the quit, and later participants aren't asked.
    public func addAsk(_ participant: @escaping @MainActor () async -> Bool)
    /// Can't cancel; finishes work first (a recording stops and delivers). Run after every ask said yes,
    /// in registration order, each awaited.
    public func addFinish(_ participant: @escaping @MainActor () async -> Void)
    /// A second call while one is running returns that call's answer.
    public func shouldTerminate() async -> Bool
}
```

#### 4.2.9 Settings layout (`StatusMenu.swift`)

`SettingsLayout.shortcutsPane = SettingsSectionSpec(id: "shortcuts", title: ShellStrings.shortcutsPane, order: 900)`, with `ShellStrings.shortcutsPane = "Shortcuts"` (Capture C5). `panes(for:)` returns the modules' sections, then Shortcuts, then AI. The shell shows a pane only when it has a view for it (§4.5).

### 4.3 `BugeyeTestSupport`

New, each with a self-test in `BugeyeTestSupportTests`:
- `CaptureEventRecorder` (`@MainActor final class`): `init(_ bus: CaptureEventBus)`, `events: [CaptureEvent]`, `changes: [CaptureChange]`.
- `FakeNotifier`: `posts: [FakeNotifier.Post]` (`title`, `body`), thread-safe.
- `FakeScreenCapturePermission`: `init(granted: Bool)`, settable `granted`, `requestCount`.
- `FakeAreaSelector` (`@MainActor`): `init(results: [SelectionResult])`, answers them in order then `.cancelled`; `requests: [SelectionRequest]`, `cancels: [SelectionPurpose]`.
- `FakeTextMeasurer`: width = 0.6 × size × `line.count` (characters), ascent = 0.8 × size, descent = 0.2 × size.

Moved (§4.1.9): `FakeScreenSource`, `FakeTextReader`, `FakeAXReader`, with their tests.

### 4.4 `MacAdapters/Shared/` (the five shared adapters, K4)

| File | Adapter | Behaviour |
|---|---|---|
| `PasteboardClipboardWriter.swift` | `ClipboardWriter` | Clears the general pasteboard and writes **one** item holding whichever of `png` (`public.png`), `fileURL` (`public.file-url`) and `text` (`public.utf8-plain-text`) are set (Capture C3, Editor §5.8, Recording V12). |
| `UserNotificationNotifier.swift` | `Notifier` | `UNUserNotificationCenter`; becomes its delegate so banners show while Bugeye is frontmost; `requestAuthorization()` asks for `.alert` and `.sound` (the shell calls it at launch); posts made before the answer are held and delivered after it, in order; with no bundle id (`swift run`, tests) it only `NSLog`s `<title>: <body>` (Capture §5.7, `design/01` §2.13). |
| `SystemScreenCapturePermission.swift` | `ScreenCapturePermission` | `CGPreflightScreenCaptureAccess()`, `CGRequestScreenCaptureAccess()`. |
| `CoreTextMeasurer.swift` | `TextMeasuring` | `CTLine` typographic bounds. Plus `CoreTextFonts.font(for: FontDescriptor) -> CTFont`, the one mapping the executor uses too: `system` → the system UI font at `size` with weight `0.4` bold, `0.3` semibold, `0` regular; any other name → that font, else the system font. |
| `PixelBufferImages.swift` | helper | `cgImage(_ buffer:, colorSpace: CGColorSpace? = nil) -> CGImage?` wraps the bytes as RGBA8 premultiplied last, tagged `colorSpace` (nil = sRGB), no conversion. `pixelBuffer(_ image:, rect: Rect2D? = nil, colorSpace: CGColorSpace? = nil) -> PixelBuffer?` draws the image (or `rect`, pixels, top-left) into RGBA8 premultiplied in `colorSpace` (nil = sRGB; pass `image.colorSpace` to keep the source's space, Editor E5). `preview(_ image:) -> PixelBuffer?`: at most `CaptureEvent.previewMaxWidth` wide, never upscaled, high-quality interpolation, sRGB. |

### 4.5 `BugeyeApp` (shell plumbing)

```swift
// Sources/BugeyeApp/Wiring/AppContext.swift
/// Everything an epic's wiring may use, built before any wiring runs.
@MainActor
final class AppContext {
    let home: String
    let registry: FeatureRegistry
    let settingsStore: any SettingsStore
    let metadata: any FileMetadataStore
    let fileWriter: CaptureFileWriter
    let clipboard: any ClipboardWriter
    let notifier: any Notifier
    let screenPermission: any ScreenCapturePermission
    let general: GeneralSettings
    let captureEvents: CaptureEventBus
    let router: ActionRouter
    let settingsPanes: SettingsPanes
    let thumbnailDecorations: ThumbnailDecorations
    let screenActivity: ScreenActivity
    let areaSelector: AreaSelectorRelay
    let screenRecordingAlert: ScreenRecordingAlert
    let statusItem: StatusItemState
    let documentWindows: DocumentWindows
    let termination: TerminationGate
    /// Keeps a controller alive for the app's life.
    func retain(_ object: AnyObject)
    /// Runs after the menu bar exists, in registration order: global hotkeys, timers, crash recovery.
    /// `install` itself must not show a window, register a global hotkey or start a timer (tests build it).
    func onLaunch(_ step: @escaping @MainActor () -> Void)
}

/// Settings panes by section id (Capture, Quick Access, Recording, Capture's Shortcuts).
@MainActor final class SettingsPanes {
    func register(_ sectionID: String, _ make: @escaping @MainActor () -> AnyView)
    func view(for sectionID: String) -> AnyView?
    private(set) var duplicates: [String]
}

/// Capture §5.5's alert, shown by Capture and Recording. Capture's wiring sets `presenter`; until then `show()` logs.
@MainActor final class ScreenRecordingAlert {
    var presenter: (@MainActor () -> Void)?
    func show()
}

/// The status item's override, observed by `MenuBarController` (testable without an NSStatusItem).
@MainActor final class StatusItemState {
    private(set) var override: StatusItemOverride?
    private(set) var owner: String?
    /// nil restores the glyph and the module menu. Another owner's override is refused and logged.
    func setOverride(_ override: StatusItemOverride?, owner: String)
    func observe(_ handler: @escaping @MainActor () -> Void)
}

// Sources/BugeyeApp/Wiring/CaptureWiring.swift (and QuickAccess, Editor, Recording the same way).
// Created by the contracts PR, owned by the epic afterwards; both members stay empty until its last PR (K7).
@MainActor
enum CaptureWiring {
    static let modules: [any FeatureModule] = []
    static func install(_ context: AppContext) {}
}

// Sources/BugeyeApp/Wiring/TextWiring.swift: OCR has no module; its install returns the text services.
@MainActor
enum TextWiring {
    static let modules: [any FeatureModule] = []
    static func install(_ context: AppContext) -> TextServices { TextServices() }
}
// Sources/Core/TextCore/TextServices.swift (owned by OCR afterwards):
// @MainActor public final class TextServices { public init() {} }
```

- **`AppServices`**: `static let modules = [GeneralModule()] + CaptureWiring.modules + QuickAccessWiring.modules + EditorWiring.modules + RecordingWiring.modules + TextWiring.modules`. Its initializer takes every port (live adapters by default, fakes in tests) and an `applyActivationPolicy` closure, builds the registry and the `AppContext`, then calls the installs in the order Capture, Quick Access, Editor, Recording, Text, and keeps `text: TextServices`. It throws when `router.duplicates` or `settingsPanes.duplicates` isn't empty; `AppDelegate` logs a fault and terminates, as for registry conflicts. Wave 0's `waveZeroRegistersOnlyGeneral` becomes `modulesAreGeneralThenEveryWiringsModules`, computed from the wiring lists, so no epic edits it.
- **`AppDelegate`**: a status-menu id that isn't About, Settings or Quit goes to `router.performMenuItem`, logged `no action for <id>` when it returns false. After the menu bar is built it asks the notifier for authorization, then runs the `onLaunch` steps. `applicationShouldTerminate` returns `.terminateLater` and replies with `termination.shouldTerminate()`.
- **`MenuBarController`**: becomes its menu's `NSMenuDelegate`. `menuNeedsUpdate` sets each module item's key from `HotkeyBindings.current` (items with `hotkeyID`) and its enabled state from `router.isMenuItemEnabled`. It observes `StatusItemState`: with an override, the item gets variable length and draws the badge (red `● ` + elapsed in monospaced digits; `❙❙ ` + elapsed; the `hourglass` symbol), sets the accessibility label and swaps in the override menu, whose ids go through the router; without one it restores the square glyph, the `Bugeye` label and the module menu.
- **Settings**: `SettingsView` shows General and AI as today, and every other pane from `settingsPanes`; a pane with no registered view is not shown (so Shortcuts appears once Capture registers it).
- **Main menu**: `DocumentWindows`' apply closure: `.regular` sets the policy, installs `NSApp.mainMenu` built from `MainMenu.entries` (items target the first responder with the spec's selector), then activates Bugeye; `.accessory` removes the main menu and sets the policy back. `LSUIElement` stays.
- **`NightChrome`** (`Sources/BugeyeApp/Chrome/NightChrome.swift`, `design/01` §2.15, values from Quick Access §4): tokens (gradient `#2B3242` → `#1B1F29`; 1 px inner border white 8 %; text `#E8EAF0`; accent `#FFC93C`, hover `#FFD666`, text on accent `#1F2430`; control fill white 7 %, hover 12 %; dark appearance) and two SwiftUI styles, `nightPanel(cornerRadius:)` (default 10 pt) and `NightButtonStyle(accent:)`. Quick Access's thumbnails and Recording's options bar and countdown both use it (Quick Access Q9's cost case).

### 4.6 Resources and the fixture app

- `Resources/Info.plist` gains `NSMicrophoneUsageDescription` = `Bugeye records your microphone only when you turn on Mic for a recording.` and `NSCameraUsageDescription` = `Bugeye shows your camera only when you turn on Cam for a recording.` (Recording §3, settled there).
- The fixture app gains what the epics' Mac batches drive, with its strings in `FixtureContent`: a secure field with placeholder `Password` (Recording §9.4.5), a button `Play Click` that plays a short click sound (Recording §9.4.2), and a menu item `Window` ▸ `Small Window` that opens a 400 × 300 pt window titled `Bugeye Fixture Small` (Capture §9.4.2). Fixture strings are test-only (K17).

## 5. Who implements what

"Contracts" means the contracts PR writes the code and its tests; otherwise it writes the shape (and fake) and the named epic implements the behaviour.

| Item | Used by | Behaviour implemented by |
|---|---|---|
| Bus, `CaptureItem`, kinds, changes | all | contracts |
| `CaptureFileWriter.create` / `move` | Capture, Quick Access, Recording | contracts |
| `CaptureFileNamer`, `CaptureFolders`, `OutputSettings`, `OutputStrings` | Capture, Recording (Quick Access via the writer) | contracts; Capture's janitor purges the temp folder |
| `Notifier`, its adapter, `FakeNotifier` | Capture, Quick Access, Editor, Recording | contracts |
| `ClipboardWriter` adapter | Capture, Quick Access, Editor, Recording | contracts |
| `ScreenCapturePermission`, its adapter | Capture, Recording | contracts |
| Screen Recording alert and relaunch | Capture, Recording | Capture (sets `ScreenRecordingAlert.presenter`) |
| `TextMeasuring`, `CoreTextMeasurer`, `CoreTextFonts` | Editor, Recording | contracts |
| Display list shapes | Editor, Recording | contracts |
| Display-list executor | Editor, Recording | Editor, first macOS PR (K10) |
| `PixelBufferImages` | Capture, Quick Access, Editor, OCR | contracts |
| `ImageFileReader` and its ImageIO adapter | OCR | OCR (K9) |
| `AreaSelector` types, relay, fake | Capture, Recording | Capture implements the selector (K15) |
| `ScreenActivity` | Capture, Recording | contracts (the table); each epic begins and ends its activities |
| `HotkeySpec.title`, `MenuItemSpec.hotkeyID`, `HotkeyBindings` | Capture, Recording, shell | contracts; Capture's registrar and Shortcuts pane |
| `ActionRouter` | Capture, Quick Access, Editor, Recording, shell | contracts |
| Quick Access action types, placements, conflicts | Quick Access, Editor | contracts; Quick Access draws and dispatches |
| `ThumbnailDecorations` | Quick Access, Recording | contracts; Quick Access draws |
| `MainMenu`, `DocumentWindows`, main-menu install | Editor | contracts; the Editor answers the selectors |
| `TerminationGate` | Editor (`addAsk`), Recording (`addFinish`) | contracts |
| `StatusItemOverride`, `StatusItemState`, its rendering | Recording | contracts; Recording builds the overrides |
| `SettingsPanes`, Shortcuts pane spec | Capture, Quick Access, Recording | contracts; each epic its pane |
| Wiring stubs, `AppContext`, `AppServices`, `AppDelegate` | all | contracts; each epic its wiring file |
| `NightChrome` | Quick Access, Recording | contracts |
| Info.plist usage strings, fixture additions | Recording, Capture, OCR (Mac batches) | contracts |
| `TextServices` stub | OCR | OCR |
| Ownership check | all | contracts |

**Amendment rule (K2).** A session that finds the contract short stops that slice, writes the smallest change as a contract amendment PR (contract files only, tests first), adds a ruling to `docs/ledgers/wave-1-contracts.md` and to each affected epic's ledger, and tells the other sessions through the user. Additive changes (a new `CaptureChange`, a new fake) need no other epic's agreement; a changed or removed shape does.

## 6. What the reconciliation changed for the user

No settled string changed. These outcomes are now fixed where the epic specs disagreed or were silent; each follows the design docs, but you may want to confirm them:
1. A recording's thumbnail shows its `▶ mm:ss` badge in Wave 1 (K12). Quick Access had deferred the badge; Recording expected it.
2. On quit with unsaved editors and a running recording, the editors ask first; a Cancel leaves the recording running. Only after every editor agrees does the recording stop, convert and save (K11).
3. ⇧⌘3, ⌥⇧⌘3 and ⇧⌘4 are refused (dropped and logged, like a request during a capture) from Record Screen's selection until its countdown ends; they work during the recording itself (`ScreenActivity`, `design/01` §1.2). The Capture spec didn't state it.
4. A module's status-menu item is disabled until its handler is registered, so nothing clickable does nothing (K13).

## 7. Testing

- **Linux (`make test-core`):** every rule in §4.1–4.2: the bus rules; kinds; the writer (§4.1.2); namer and candidates; folders for a given home; `OutputSettings` defaults and bad values; `OutputStrings` character for character; `isBalanced`, `ellipse`, `roundedRect` and the rewritten display-list golden JSON covering every command; `AreaSelectorRelay` with and without a target; the `ScreenActivity` table, every activity × request; the new registry conflicts and `mainMenuItems` order; `KeyCombo(description:)` round trips for every Capture and Recording default, invalid strings, `isValidHotkey`; `HotkeyBindings.current` for missing, `none`, invalid and valid values; `ActionRouter` (unregistered ids return false or nil, duplicates recorded and the first kept, `isEnabled` asked each time, one opener per kind); `ThumbnailDecorations` (replace, remove with [], provider order, observers called); `DocumentWindows` (0→1 and 1→0 only, below 0 stays 0); `TerminationGate` (ask order, first false stops, finish only after every ask, a second call shares the first answer); `MainMenu.entries` against §4.2.5's table; every fake's self-test; the moved tests still pass where they moved.
- **`make guards`:** the existing guards and `scripts/test-ownership.sh` (§3).
- **macOS CI:** the pasteboard item (PNG + file URL + text on one item); the notifier's no-bundle path logs and doesn't crash, and posts before authorization are held, through an injected center; `CoreTextMeasurer` (positive width, bold wider than regular for the same text, ascent and descent match `CTFont`); `PixelBufferImages` round trip byte for byte in sRGB, a P3 image kept in P3 when asked, `preview` of a 2000 px image is 480 px wide and of a 300 px image unchanged; `AppServices` builds with fakes and `modulesAreGeneralThenEveryWiringsModules`; launch fails on a duplicate router or pane id; the status menu's key comes from a changed binding and a module item without a handler is disabled; the override badge, label and menu are applied and restored, and a second owner is refused; the main menu is installed on `.regular` and removed on `.accessory` (injected apply); `applicationShouldTerminate` answers `.terminateLater` and replies with the gate's answer; Settings shows a registered pane and hides an unregistered one; `Info.plist` holds both usage strings; the fixture app builds.

## 8. Done when

1. Wave 0 has merged; `feat/wave1-contracts` is cut from `main`, with its ledger, and a draft PR is open. While it is a draft, `make test-core lint guards` is the check and pushes are batched (`design/14` R10).
2. The PR is marked ready; `linux` and `macos` are green on its head, and `claude-review` has posted (R10).
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. The PR description has a table mapping every item of each epic's "Uses from the contracts" list to the merged file and name, checked by the session, so the five sessions start from names that exist.
5. No step on your Mac (K19).
6. You merge it; the five epic sessions are started (or told) only after that.
