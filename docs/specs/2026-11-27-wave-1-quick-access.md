# Wave 1: Quick Access

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → Mac batch → manual pass

Quick Access rebuilds the first build's thumbnail stack (`design/02` §1.4, §2.12): one floating thumbnail per capture, its strip and ⋯ menu, hover, Esc, drag-out, ⇧-click selection. It runs as one of the parallel Wave 1 sessions (`design/14` R1), on Wave 0's skeleton. It consumes the Capture contract (`docs/specs/2026-11-27-wave-1-capture.md` §3, C1, C2) and the Wave 1 contracts PR (§3 here). It owns thumbnails, Save, Save As…, Delete, and the `saved` and `deleted` events.

## 1. Decisions

From the brainstorm (your answer):

| # | Question | Decision |
|---|---|---|
| B1 | Behaviour | **Exactly as `design/02` §1.4 documents it**: size, position, stack limits, timers and pauses, look, animations, ✕, badges, strip buttons, ⋯ menu, drag-out, double-click, Esc, hover and key focus, ⇧-click selection and Combine. Plus `design/02` §5 items 7–9: a pure view model with the panel as a dumb renderer, no closure ever captures an entry (leak tests for every panel type), and one event bus. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| Q1 | **Wave 1 ships only the actions that exist in Wave 1:** Copy (PNG + URL), Save, Save As…, Reveal in Finder, Delete, drag-out, ✕. Everything else arrives later through the extension points in §3, with no edit to Quick Access: Edit / Trim / Open (primary), Copy Text, Copy for AI, Copy as Markdown, Open Source, Find Similar, Export GIF…, Combine, the source chip, the sweep badge, the media badge and the learned ★ ring. | One owner per action. The parallel Editor epic registers Edit itself (§3.2). [Low] |
| Q2 | **While no primary action is registered for a kind, the strip shows Copy · Save · ⋯ only**, sharing the width. There is no disabled placeholder, and double-click does nothing (no beep). Once the Editor epic registers Edit, the strip becomes Copy · Save · Edit · ⋯ with no Quick Access change. | A dead yellow button would be tapped and do nothing. [Low: a placeholder is one row in the strip table.] |
| Q3 | **Extension points live in shared code, landed by the contracts PR** (§3): a reshaped `QuickAccessActionSpec` with a placement and kinds, a runtime handler registry, a thumbnail-decoration store, an activity feed for the habits epic, and two new bus changes for the editor. | Area cores can't depend on each other (Wave 0 P14), and the Editor session works in parallel. [Medium: a missed extension point means a later epic edits Quick Access.] |
| Q4 | **⇧-click selection works now; Combine does not.** Selecting shows the border and ✓ and pauses every timer. The host's strip is replaced only while an action with `placement: .selection` is registered (the collections epic's Combine). Until then the host keeps its normal strip. | B1 asks for the selection rules; Combine needs collections. [Low] |
| Q5 | **Editing state and preview refresh come over the bus.** The editor publishes `openedInEditor` / `closedInEditor` (new values, §3.1) and `edited` with a ≤ 480 px `preview`. Quick Access never decodes a capture file. | One "capture changed" channel (`design/02` §5.9). The editor already holds the render. [Low] |
| Q6 | **Save moves through `CaptureFileWriter.move` (new, §3.1); Save As… writes through the existing `write(_:to:attributesFrom:identity: .new(id))`.** The copy is published as `created` with `origin: "quickAccess"`, and Quick Access ignores `created` events it published itself, so the copy gets no thumbnail. Quick Access publishes no `moved` in Wave 1; it follows `moved` from others. | Keeps the one-writer rule and the xattrs (`design/11` §6). The copy is a new capture for the index (`design/02` §1.4). [Low] |
| Q7 | **No new ports for macOS-only effects.** Trash, Reveal in Finder, the save panel, panels, animation and focus are effects the view model emits and Quick Access's own macOS files perform. Moving and copying files is portable and runs in `QuickAccessCore`. | Fewer shared files; the decisions stay Linux-testable. [Low] |
| Q8 | **Settings live in `QuickAccessCore`, under `quickAccess.*` keys**, read fresh at each show (Capture C6). Pane `Quick Access`, order 20, after Capture (10). A duration change applies to thumbnails shown afterwards; a position change at the next layout. | No edit to the shared `AppSettings`. [Low] |
| Q9 | **This epic creates `NightChrome`** (tokens and view styles, `design/01` §2.15) in `Sources/BugeyeApp/Chrome/`. No other Wave 1 epic draws night panels. Later epics reuse it. | First user builds it. [Low: if another Wave 1 spec needs it, it moves to the contracts PR.] |
| Q10 | **Every user-visible string is settled in §5**, including those the docs leave open: failure notices, accessibility labels, Settings options. | `design/11` §7. [Low] |
| Q11 | **Edge rules the docs leave open:** Delete of a file that is already gone counts as deleted (no notice). Save As… onto the capture's own file does nothing. Only clicks on the image area toggle or clear the selection; ✕, strip and ⋯ clicks don't. ⇧-click on a recording, GIF or collection is ignored. A `created` for a capture already shown is ignored. Delete asks no confirmation (as documented). | Each is one test. [Low] |
| Q12 | **The documented layout stays, known issues included.** A new capture still pushes the hovered thumbnail up one slot, and on a one-slot screen a hovered thumbnail plus the new one exceed the limit (`design/02` §4). They go to `docs/backlog.md`. | B1: exactly as documented. [Low] |
| Q13 | **⋯ menu order is by `order`, with no separators.** Reveal in Finder is 800, Delete 1000. Later epics use: Copy Text 100, Copy for AI 200, Copy as Markdown 300, Open Source 400, Find Similar 500, Export GIF… 850. That reproduces the documented order for every kind. | The docs list no separators. [Low] |
| Q14 | **Testing split** (§8): the view model, file actions and every string on Linux; panel properties, hosting, Esc routing, drag provider and leak tests on hosted macOS CI; the look, animations and focus return into real apps in the Mac batch and your manual pass. | `design/14` R8–R10. [Low] |

## 2. Scope

In scope:
1. The stack: show, layout, eviction, screen fit, timers and their pauses, fade and slide.
2. The thumbnail: image, ✕, selection border and ✓, strip, ⋯ menu, the decoration slots (empty in Wave 1).
3. Actions: Copy, Save, Save As…, Reveal in Finder, Delete, drag-out, double-click (runs the primary once registered), Esc.
4. Hover and key focus, with focus return.
5. ⇧-click selection; the `.selection` slot for Combine.
6. Following the bus: `created`, `saved`, `moved`, `edited`, `deleted`, `openedInEditor`, `closedInEditor`; publishing `saved`, `deleted` and the Save As copy's `created`.
7. The Quick Access settings pane, `NightChrome`, logging.

Out of scope: every action and decoration listed in Q1 (later epics); recordings, GIFs and collections arriving at all (Wave 1 creates screenshots only, though the model handles every `CaptureKind`); the action-habits store; Duplicates; Open Last Capture.

## 3. Contract needs

These land in the Wave 1 contracts PR, before any epic starts. Nothing else in this epic touches a shared file. Exact names may be harmonised with the other four specs in that PR; the capabilities and shapes may not shrink.

**Capture's C1 contract is enough for:** `CaptureItem`, `CaptureKind`, `CaptureEvent`, `CaptureEventBus` (subscribe, publish, `item(_:)`), `CaptureSubscription`, the `Notifier` port and `FakeNotifier`, `CaptureEventRecorder`, and the `captureEvents` instance. **Wave 0 is enough for:** `ClipboardWriter` / `ClipboardPayload` (Copy), `CaptureFileWriter.write(_:to:attributesFrom:identity:)` (Save As…), `AppSettings.saveFolder`, `FolderPath`, `SaveFolder.ensureExists`, `SettingsStore`, `CaptureID`, `PixelBuffer`, `Rect2D`.

### 3.1 BugeyeCore

```swift
// Captures/CaptureEventBus.swift: two more changes, published by the editor (Q5).
extension CaptureChange {
    public static let openedInEditor: CaptureChange   // "openedInEditor": an editor window shows this capture
    public static let closedInEditor: CaptureChange   // "closedInEditor": the last editor window on it closed
}
// CaptureEvent.preview's doc becomes: "For created and edited: the image at most 480 px wide."
// item(_:) is unchanged by the two new values.

// Files/CaptureFileWriter.swift
extension CaptureFileWriter {
    /// Moves a capture into `folder` under its own file name and extension, never replacing a file:
    /// on a clash it tries "<stem> (2).<ext>", "<stem> (3).<ext>", … (stem = the name without its last
    /// extension, as is). Same volume: a no-replace rename, so every attribute follows. Another volume:
    /// a no-replace write of a copy carrying the kept attributes (P11), then the source is removed.
    /// Returns the final URL. On failure the source is untouched and no partial file remains.
    public func move(_ source: URL, into folder: URL) throws -> URL
}
```

`move` shares the no-replace primitive (`renameatx_np(RENAME_EXCL)` / `renameat2(RENAME_NOREPLACE)`) with Capture's `create(_:named:in:identity:)` (Capture C8), so both land together in the contracts PR. Tests on Linux: same-volume move keeps attributes, suffixing on clash, the source survives a failure, and a cross-volume path through an injected "rename fails with `EXDEV`" seam.

### 3.2 BugeyeFeatures

```swift
// QuickAccess/QuickAccessActionSpec.swift: replaces Wave 0's QuickAccessActionSpec(id:title:order:).
public struct QuickAccessActionSpec: Hashable, Sendable {
    public enum Placement: Hashable, Sendable {
        /// The yellow strip button; double-click runs it too. At most one per kind across all modules.
        case primary
        /// An item of the ⋯ menu, sorted by `order` (Q13).
        case menu
        /// Replaces the selection host's strip with one yellow button "<title> (N)". At most one.
        case selection
    }
    public var id: String          // unique across modules, e.g. "editor.edit"
    public var title: String       // "Edit", "Copy for AI", "Combine"
    public var order: Int
    public var placement: Placement
    /// Kinds it is offered for, e.g. [.screenshot].
    public var kinds: Set<CaptureKind>
    public init(id: String, title: String, order: Int, placement: Placement, kinds: Set<CaptureKind>)
}

// FeatureRegistry.swift: two more conflicts, each a test.
extension FeatureConflict {
    // case quickAccessPrimaryTaken(CaptureKind, ids: [String])   two .primary specs share a kind
    // case quickAccessSelectionTaken(ids: [String])               more than one .selection spec
}

// QuickAccess/QuickAccessRuntime.swift
public enum QuickAccessActionID {
    public static let copy = "quickAccess.copy"
    public static let save = "quickAccess.save"
    public static let saveAs = "quickAccess.saveAs"
    public static let reveal = "quickAccess.reveal"
    public static let delete = "quickAccess.delete"
}

public enum QuickAccessTrigger: Hashable, Sendable { case strip, menu, doubleClick, decoration, selection }

public struct QuickAccessSubitem: Hashable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String)
}

/// Asked at every render of a thumbnail (§6.9).
public enum QuickAccessActionState: Hashable, Sendable {
    case enabled, disabled, hidden
    /// A submenu under the action's title (Open Source with several sources).
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

/// Runtime behaviour for registered specs. A spec without a handler is not shown (logged once).
@MainActor public final class QuickAccessActionHandlers {
    public init()
    /// Registering an id twice is a programming error (assertion in debug; the first stays).
    public func register(_ id: String, _ handler: QuickAccessActionHandler)
    public func handler(for id: String) -> QuickAccessActionHandler?
}

// QuickAccess/ThumbnailDecorations.swift
public enum ThumbnailDecoration: Hashable, Sendable {
    /// Top of the image, right of ✕: app icon + short label (provenance). Tapping runs `actionID`.
    case sourceChip(label: String, appBundleID: String?, actionID: String?)
    /// Bottom-right corner: "▶ 0:42", "GIF".
    case mediaBadge(text: String)
    /// Bottom edge, centred, amber capsule (sweep "⚠ 2 possible"). Tapping runs `actionID`.
    case warningBadge(text: String, tooltip: String?, actionID: String?)
    /// The learned usual action: a ring on its strip button, else on ⋯ plus "★ " before its menu title.
    case suggestedAction(actionID: String)
}

@MainActor public final class ThumbnailDecorations {
    public init()
    /// Replaces everything `provider` shows on `capture`; [] removes it.
    public func set(_ decorations: [ThumbnailDecoration], for capture: CaptureID, from provider: String)
    /// All providers' decorations, providers in first-set order.
    public func decorations(for capture: CaptureID) -> [ThumbnailDecoration]
    /// Called after every `set`, with the capture it changed. Observers live as long as the app.
    public func observe(_ handler: @escaping @MainActor (CaptureID) -> Void)
}

// QuickAccess/QuickAccessActivity.swift: what the habits epic learns from (design/06 §1.6).
public struct PerformedQuickAccessAction: Hashable, Sendable {
    public var actionID: String
    public var item: CaptureItem
    public var trigger: QuickAccessTrigger
    public init(actionID: String, item: CaptureItem, trigger: QuickAccessTrigger)
}

@MainActor public final class QuickAccessActivity {
    public init()
    public func record(_ action: PerformedQuickAccessAction)
    public func observe(_ handler: @escaping @MainActor (PerformedQuickAccessAction) -> Void)
}
```

Wave 0's `FeatureRegistryTests` that build `QuickAccessActionSpec(id:title:order:)` are updated in the same PR. `BugeyeTestSupport` gets `RecordingQuickAccessHandler` (counts `perform` calls, returns a scripted state).

### 3.3 App shell (`BugeyeApp`)

Five sessions must never edit `AppServices.swift`, `SettingsWindowController.swift` or `AppDelegate.swift`. The contracts PR therefore adds one wiring file per Wave 1 epic and the hooks that read them:

```swift
/// Shared instances every epic's wiring may use, built before any wiring runs.
@MainActor struct SharedServices {
    let registry: FeatureRegistry
    let settingsStore: any SettingsStore
    let metadata: any FileMetadataStore
    let clipboard: any ClipboardWriter
    let notifier: any Notifier
    let general: GeneralSettings
    let captureEvents: CaptureEventBus               // C1
    let quickAccessHandlers: QuickAccessActionHandlers
    let thumbnailDecorations: ThumbnailDecorations
    let quickAccessActivity: QuickAccessActivity
}

/// What one epic plugs into the shell.
@MainActor struct ModuleWiring {
    var actions: [String: @MainActor () -> Void] = [:]          // menu-item and hotkey ids (Capture C12)
    var settingsPanes: [String: @MainActor () -> AnyView] = [:] // pane id → view
    var retained: [AnyObject] = []                              // controllers kept alive for the app's life
}

// Sources/BugeyeApp/Wiring/QuickAccessWiring.swift, created empty by the contracts PR, owned by this epic.
extension ModuleWiring {
    static let quickAccessModules: [any FeatureModule] = []   // this epic's last PR adds QuickAccessModule()
    static func quickAccess(_ shared: SharedServices) -> ModuleWiring { ModuleWiring() }
}
```

- `AppServices.modules` = `[GeneralModule()]` + each epic's `…Modules` list, written once by the contracts PR.
- `AppServices` builds `SharedServices`, calls the five wiring functions and merges their results; a duplicate action or pane id fails at launch with a test.
- `SettingsView`'s pane switch looks unknown ids up in the merged `settingsPanes`.
- `PixelBuffer → CGImage` (sRGB, premultiplied last) in `MacAdapters`, used by Capture's `ImagePipeline` and by Quick Access's renderer.

No new settings keys in shared code (Q8), no `Notifier` change, and no bus addition beyond §3.1.

## 4. The thumbnail and stack (look)

| Property | Value |
|---|---|
| Thumbnail | 240 × 176 pt: image area 136 pt high, strip 40 pt |
| Position | Bottom-left (default) or bottom-right of the **visible frame** of the display under the pointer when the latest `created` arrived; 16 pt margin, 10 pt gap; newest at the bottom |
| Stack | At most 5 and never more than fit (§6.2) |
| Look | Night chrome: gradient `#2B3242` → `#1B1F29`, 1 px inner border white 8 %, 10 pt corners, dark appearance; text `#E8EAF0`; accent `#FFC93C` (hover `#FFD666`, text on accent `#1F2430`); control fill white 7 % (hover 12 %) |
| Image | The `created` preview, aspect-fill, clipped to the image area |
| ✕ | Top-left, yellow (accent) glyph on a dark circle; dismisses |
| Selected | 2 pt accent border and a ✓ at top-right |
| Decorations | Source chip at the top, right of ✕; media badge bottom-right; warning badge centred on the image's bottom edge (all empty in Wave 1). At most one of each case is drawn, the first provider's; a second is logged |
| Strip | 8 pt padding, 6 pt gaps, 28 pt high buttons: Copy, Save, primary (accent fill), ⋯ (28 pt square). Buttons other than ⋯ share the remaining width |
| Ring | 1.5 pt accent ring on the suggested strip button, or on ⋯ |
| Animation | Fade in 0.18 s; fade out 0.15 s, then close; the stack slides to close gaps in 0.18 s |

Panel (`design/02` §2.12): `NSPanel` with `[.nonactivatingPanel, .borderless]`, `level = .statusBar`, clear background, shadow, not movable, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `NSAppearance(named: .darkAqua)`, `canBecomeKey = true`, `canBecomeMain = false`. Esc arrives as `keyDown` keyCode 53 or as `cancelOperation(_:)`; both send `escape`. Dismissal **closes** the panel.

## 5. Behaviour and strings

### 5.1 Strip and menu

| Slot | Screenshot | Recording | GIF |
|---|---|---|---|
| Copy | `Copy`: one item, PNG read from the file + file URL | `Copy`: file URL only | same as recording |
| Save | `Save` while `isSaved == false`; `Save As…` once saved | same | same |
| Primary | the registered `.primary` spec for the kind, else absent (Q2) | same | same |
| ⋯ | registered `.menu` specs for the kind, then `Reveal in Finder` (800), `Delete` (1000) | same | same |

- The suggested action (a `suggestedAction` decoration): if its id is Copy, Save, Save As… (both ring the Save slot) or the primary, that button gets the ring. Otherwise ⋯ gets the ring and the item's title is prefixed `★ ` (U+2605, space).
- With a `.selection` spec registered and two or more selected, the host's strip is one accent button `<title> (N)`, e.g. `Combine (3)`.
- Accessibility labels: ✕ `Dismiss`, ⋯ `More`.
- Double-click on the image runs the primary with trigger `.doubleClick`; with none registered it does nothing.

### 5.2 Actions

Every action goes through one dispatcher keyed by `CaptureID`, which first records a `PerformedQuickAccessAction` (for strip, menu, double-click, decoration and selection triggers), then acts on the entry's **current** item.

| Action | Effect | Event published |
|---|---|---|
| Copy | `ClipboardWriter.write` per §5.1. File missing or unreadable: notice | none |
| Save | Ensure the save folder (`AppSettings.saveFolder`, read fresh) exists, then `CaptureFileWriter.move(file, into: folder)`. The button becomes `Save As…` | `saved` (`isSaved = true`, new `fileURL`, `previousURL`, `origin: "quickAccess"`) |
| Save As… | Save panel: name field = current file name, starting folder = the file's folder, content type of the file. On OK: `CaptureFileWriter.write(data, to: chosen, attributesFrom: current, identity: .new(newID))`. Chosen = current file: nothing (Q11) | `created` for the copy (new id, `isSaved = true`, the thumbnail's preview, `origin: "quickAccess"`) |
| Reveal in Finder | `NSWorkspace.activateFileViewerSelecting([url])` | none |
| Delete | Saved: move to the Trash. Temp: remove the file. Already gone: treated as done. Then dismiss | `deleted` |
| Drag | Image drag provides the file at the entry's current URL at drag start; the thumbnail stays | none |
| ✕ | Dismiss. A temp file stays in the temp folder (purged after 24 h by Capture) | none |

File work (Copy's read, Save, Save As…) runs off the main actor; its result returns as an event tagged with the `CaptureID` and is dropped if the entry is gone, except that a finished Save or Save As… still publishes its event (the file did move).

### 5.3 Notices

Posted through `Notifier`. `<path>` is shown as General shows it (`~/…`); `<name>` is the file name; `<error>` is the error's `localizedDescription`.

| Case | Title | Body |
|---|---|---|
| Save: folder missing or unwritable | `Couldn't save to folder` | `<path> is unavailable. The capture stays in the temporary folder.` |
| Save: other failure | `Couldn't save to folder` | `<error>` |
| Save As… failed | `Couldn't save a copy` | `<error>` |
| Copy: file missing or unreadable | `Couldn't copy` | `<name> is missing or unreadable.` |
| Delete failed | `Delete failed` | `<error>` |

A failed action leaves the thumbnail and its timer as they were.

### 5.4 Settings pane

Pane `Quick Access` (module `quickAccess`, order 20). Two pickers:
- `Auto-dismiss`: `Never`, `5 seconds`, `10 seconds`, `30 seconds`, `60 seconds`.
- `Position`: `Bottom left`, `Bottom right`.

| Key | Type | Default | Valid |
|---|---|---|---|
| `quickAccess.autoDismissSeconds` | Int | 5 | 0 (Never), 5, 10, 30, 60; anything else → default |
| `quickAccess.position` | String | `bottomLeft` | `bottomLeft`, `bottomRight`; anything else → default |

## 6. The view model

`QuickAccessModel` in `QuickAccessCore` is the single owner of the stack. It is pure, on the main actor, with an injected clock value per event, and returns effects. The macOS controller feeds it events and performs effects; panels and views hold no state of their own.

**State:** `entries` (oldest first), each `{ item: CaptureItem, preview: PixelBuffer?, timer: DismissTimer, duration: Duration?, isEditing: Bool }` · `hovered: CaptureID?` · `selection: QuickAccessSelection` · `anchor: Rect2D` (visible frame, Cocoa points) · `position` · `keyPanel: CaptureID?` · `rememberedKeyWindow: WindowToken?` · `ticking: Bool`.

**Events:** `bus(CaptureEvent, now, anchor?, settings?)` (anchor and fresh settings only with `created`) · `tick(now)` · `hoverBegan(id, bugeyeKeyWindow: WindowToken?, now)` · `hoverEnded(id, bugeyeIsActive, now)` · `imageClicked(id, shift, now)` · `imageDoubleClicked(id)` · `escape(id, now)` · `closeTapped(id)` · `stripTapped(id, slot)` · `menuChosen(id, actionID, subitemID?)` · `decorationTapped(id, actionID)` · `selectionActionTapped` · `decorationsChanged(id)` · `fileActionFinished(id, action, result)` · `saveAsChosen(id, url?)` · `fadeOutFinished(id)`.

**Effects:** `showPanel(id, frame)` · `fadeIn(id)` · `fadeOut(id)` · `closePanel(id)` · `layout([id: Rect2D], animated)` · `render(id, ThumbnailState)` · `makeKey(id)` · `restoreKey(WindowToken)` · `activateFrontmostApp` · `startTicker` / `stopTicker` · `copy(ClipboardPayload)` · `runFileAction(id, .save | .saveAs(URL) | .readForCopy)` · `trash(url)` / `remove(url)` · `reveal(url)` · `showSavePanel(id, name, directory)` · `perform(QuickAccessActionContext)` · `recordActivity(PerformedQuickAccessAction)` · `publish(CaptureEvent)` · `notify(title, body)` · `log(message)`.

`ThumbnailState` is the whole render: preview, ✕, selected flag, strip buttons (title, id, accent, ring, enabled), ⋯ items (title with ★, id, state, subitems), decorations. The view draws it and nothing else.

### 6.1 Rules (each a named test)

1. **Show.** `created` with `origin != "quickAccess"` and an id not already shown appends an entry: duration from fresh settings (0 → nil, never expires); timer started at `now`, paused at once if the selection is non-empty; `anchor` and `position` replaced; `limit = fitting(anchor.height)`; `push(…, sparing: hovered)`; every evicted entry is dismissed (rule 8); `showPanel`, `fadeIn`, `layout` for all; `startTicker` if not ticking.
2. **Fit.** `fitting(h) = max(1, floor((h − 2·16 + 10) / (176 + 10)))`; the stack holds at most `min(5, fitting)`. Push evicts from the oldest, skipping the hovered id and never the new item, until the count fits or only those two remain. ≈850 pt → 4.
3. **Layout.** For `entries.reversed()` (newest first) at index i: `y = anchor.minY + 16 + i·186`; `x = anchor.minX + 16` (bottom left) or `anchor.maxX − 16 − 240` (bottom right). Every entry follows the latest anchor. Any change of entries emits `layout(animated: true)`.
4. **Timers.** `DismissTimer` with `remaining` and `runningSince`; `pause(at:)` banks elapsed time; `resume(at:)`; `restart(duration:at:)`; `isExpired(at:)`; nil duration never expires. A timer runs only if its entry is not hovered, not editing, and the selection is empty. `tick` every 0.5 s dismisses expired entries; the ticker stops when `entries` is empty.
5. **Hover.** `hoverBegan`: `hovered = id`, pause its timer, remember `bugeyeKeyWindow` if given (Bugeye active and its key window isn't a thumbnail), `makeKey(id)`, `keyPanel = id`. `hoverEnded`: `hovered = nil`; resume unless editing or selection non-empty; if `keyPanel == id`, then `restoreKey(remembered)` when `bugeyeIsActive` and one is remembered, else `activateFrontmostApp`; `keyPanel = nil`.
6. **Esc.** On the key thumbnail: selection non-empty → clear it (rule 7); else dismiss that thumbnail.
7. **Selection.** `imageClicked(shift: true)` on a screenshot toggles its id; the host is the most recently ⇧-clicked id still selected. The first selected id pauses every timer. `imageClicked(shift: false)` on any image clears the selection. Clearing (plain click, Esc, a `.selection` action, the last selected dismissed) restarts every timer with its entry's full duration, except the hovered one and those editing. A `.selection` action runs with the selected items in stack order, oldest first, then clears the selection. ⇧-click on other kinds does nothing.
8. **Dismiss** (✕, Esc, expiry, eviction, Delete, a `deleted` event): remove from the selection (clearing rules if it empties), from `hovered`; if `keyPanel == id`, focus returns as in rule 5; `fadeOut` then `closePanel` on `fadeOutFinished`; the rest `layout`. A dismissed id never produces effects again.
9. **Following the bus.** For a shown id: `saved` / `moved` replace the item (button title follows `isSaved`); `edited` replaces the preview when one is given; `deleted` dismisses; `openedInEditor` sets `isEditing` and pauses; `closedInEditor` clears it and resumes per rule 4; any other change, known or not, re-renders (so handler states and decorations refresh). Events for ids not shown are ignored.
10. **Strip and menu.** Built per §5.1 from the registry's specs filtered by kind and by handler presence; each handler's `state` is asked at render: `hidden` drops the item, `disabled` greys it, `submenu` nests subitems. The primary is never hidden by state; `disabled` greys it.
11. **Actions.** Per §5.2. Delete on a saved file emits `trash`, on a temp file `remove`; the dismiss and `deleted` follow the success result. Save emits `runFileAction(.save)`; success publishes `saved` and re-renders. Save As… emits `showSavePanel`; `saveAsChosen(nil)` does nothing.
12. **No captured entries.** Every closure a panel or view holds captures only a `CaptureID` and a `weak` reference to the controller (`design/02` §5.8).

Regression tests carried over by name (`design/02` §3.2): `evictedQuickAccessPanelIsDeallocated`, `hoveredThumbnailIsNotEvictedByANewCapture`, `stackLimitFollowsTheVisibleHeight`, `escapeAsCancelOperationDismissesAndClosesTheGap`, `keyFocusReturnsWhenThePointerLeaves`, `saveKeepsTheSourceExtension`, `lateEventFollowsTheMovedFile`.

## 7. Architecture

| Target | Platform | Quick Access content |
|---|---|---|
| `BugeyeCore`, `BugeyeFeatures`, `BugeyeApp` shared files | | §3 only, in the contracts PR |
| `QuickAccessCore` | portable | `QuickAccessModule` (pane spec; `.menu` specs for Reveal in Finder and Delete); `QuickAccessStack`; `DismissTimer`; `QuickAccessSelection`; `QuickAccessLayout`; `QuickAccessModel` (§6); `ThumbnailState` and the strip/menu builder; `QuickAccessFileActions` (copy read, Save via `move`, Save As via `write`, results as values); `QuickAccessSettings`; `QuickAccessStrings`; `WindowToken` |
| `BugeyeTestSupport` | portable | nothing beyond §3.2's handler fake; Quick Access tests use the C1 and Wave 0 fakes |
| `BugeyeApp` (`QuickAccess/`, `Chrome/`, `Wiring/QuickAccessWiring.swift`) | macOS | `QuickAccessController` (bus subscription, display-under-pointer lookup, 0.5 s ticker, effect executor); `QuickAccessPanel`; SwiftUI `ThumbnailView` in an `NSHostingView` whose `rootView` is replaced on render; drag provider; `NSSavePanel`, Trash, Reveal and focus effects; the Quick Access pane; `NightChrome` |

Main thread: file reads, moves, copies and trashing run off the main actor. Only the model, the controller, the views and the bus are on it.

**Logging:** `os.Logger`, subsystem `dev.msenechal.bugeye`, category `quickAccess`: `show <id> stack <n>` · `dismiss <id> <reason>` (`close`, `escape`, `expired`, `evicted`, `deleted`) · `saved <file name>` · `failed <action> <id>: <error>` · `no handler for <action id>` · `decoration ignored <case> from <provider>`. File paths other than names are never logged.

## 8. Done when

1. The contracts PR with §3 has merged before this epic's first PR, and the session has checked §3's shapes against it.
2. `linux` and `macos` are green on every ready-for-review PR of the epic (R10: drafts get no CI; pushes are batched), and `claude-review` has posted on each. Linux covers §6 rules 1–12 and the named regressions, `fitting` and layout on 1 and 2 displays with negative origins, timer banking, selection and host order, the strip/menu builder with fake specs and handlers (primary absent, primary present, hidden/disabled/submenu, ★ and ring placement, `Combine (N)`), Save, Save As… and Copy against temp folders and `FakeFileMetadataStore`, published events with `CaptureEventRecorder`, settings parsing, and every string in §5 character for character. macOS CI covers the panel's properties, Esc through both `keyDown` 53 and `cancelOperation`, render replacement, the drag provider's URL after Save, the pane, and leak tests: an evicted, a dismissed and an Esc-dismissed panel and its hosting view deallocate.
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. The Mac batch (`needs-mac-check` on PRs touching panels or focus) passes: drag-out to Finder makes a copy of the current file; with the fixture app's `Type here` field focused, hovering a thumbnail then leaving returns typing to the fixture; thumbnails never appear in a full-screen capture.
5. Your manual pass, `docs/checklists/wave-1-quick-access.md` (`design/11` §5 format): Before you start (quit the old app; Wave 1 Capture installed) · How to check (`ls ~/Pictures/Bugeye`, `ls ~/Library/Caches/dev.msenechal.bugeye/Captures`, `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`) · A. Look: size, night chrome, ✕, strip, ⋯ · B. Stack: five captures, laptop screen limit, bottom left and right, display under the pointer, fade and slide · C. Timers: 5 s, Never, 60 s, hover pause, selection pause and full restart · D. Hover and keys: Esc dismisses, typing goes back to your app · E. Actions: Copy (paste into Slack, Finder, Preview), Save with saving off, Save As…, Reveal in Finder, Delete (saved to Trash, temp removed), drag to Finder and Slack · F. Selection: ⇧-click, ✓ and border, plain click and Esc clear · G. Failures: save folder unplugged, file deleted in Finder then Copy and Delete · H. Settings pane.
6. You say "all good", and the last PR merges.
