# Wave 1: Editor core

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → manual pass

The editor core rebuilds the first build's annotation editor (`design/03` §1.1–1.7): opening, the window, eleven tools, the options strip, the background frame, undo, zoom and output. It runs as one of the five parallel Wave 1 sessions (`design/14` R1), on Wave 0's skeleton, after the Wave 1 contracts PR (§3). The display list is its centre: the canvas and every export draw from the same list (`design/03` §5.2).

## 1. Decisions

From the brainstorm (your answer):

| # | Question | Decision |
|---|---|---|
| B1 | Behaviour | **Exactly as `design/03` §1.1–1.7 and §2 describe it**: opening rules, one editor per capture, Dock and main menu while open, window sizing, layout, toolbar, 11 tools and their letter keys, text entry, degenerate input, the options strip with every value and default, the background frame, undo and redo (200 steps, one per drag), zoom, output (Copy, Save, Save As…, the drag handle), the moved-or-deleted alert and the unsaved-changes prompts. Plus `design/03` §5: the display list is the centre, and canvas and export render from the same list. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| E1 | **The editor never edits a shared file.** Everything it needs from shared code is in §3 and lands in the Wave 1 contracts PR. After that, the editor writes only `Sources/Core/EditorCore/`, `Sources/BugeyeApp/Editor/`, `Sources/Mac/MacAdapters/Editor/` and their test folders. A contract change after the merge needs a ruling in every affected epic's ledger. | Five sessions run in parallel (R1). [Medium: a late contract change costs several sessions a rework.] |
| E2 | **Registration is data plus the router.** `EditorModule` (in `EditorCore`) declares the Quick Access action `Edit` (primary, screenshots only) and the status-menu item `Open Last Capture` (slot `.library`, order 0). `EditorWiring.install` (a stub file the contracts PR creates, editor-owned from then on) binds them through `ActionRouter`, and registers the editor as the opener for `.screenshot`. Quick Access calls `router.performQuickAccessAction("editor.edit", on:)` for the Edit button and for double-click. The stub returns nil until the epic's last PR, so `main` never shows half a feature. | No session edits Quick Access's or the shell's files. One router serves menus, hotkeys, Quick Access and "open this capture". [Low] |
| E3 | **The bus tells Quick Access what the editor does.** Opening publishes `editingStarted`; closing publishes `editingEnded`; a successful Save publishes `edited` with a 480 px preview. Quick Access pauses the thumbnail's timer between the first two and swaps its image on the third. The editor follows `saved` and `moved` (re-points to the new URL, retitles the window) and `deleted` (the next Save shows the "gone" alert). Before publishing, the editor takes the item from `bus.item(id)`, never from its own copy. | The bus replaces the first build's `setEditing`, `updatePreview` and `onItemChanged` chain (`design/02` §5.9, `a77bc5a`). [Low] |
| E4 | **Every write goes through `CaptureFileWriter`.** Save: `write(png, to: url)` with `.keep`, so the xattrs and the `CaptureID` survive. Save As: `write(png, to: chosen, attributesFrom: url, identity: .new(CaptureID()))`. The drag-handle file: the same as Save As, into the drag folder, so it carries provenance once Wave 2 adds it (fixes the backlog item). Save As after the "gone" alert: `identity: .new(item.id)`, keeping the ID, then publish `moved` and `edited`. | One choke point (`design/11` §6). The guard already forbids other writes. [Low-Medium: after a Finder move, two files can share an ID; Wave 2's index must tolerate it.] |
| E5 | **Blur and pixelate are portable algorithms on `PixelBuffer`, in `EditorCore`.** The shell extracts the blur's source rect from the original capture into RGBA8 in the capture's own colour space, with no conversion, runs the core algorithm, and wraps the result back as a `CGImage` tagged with the same colour space. Edges clamp to the source rect, as Core Image's `clampedToExtent()` did. Gaussian is three box passes per axis. | `design/13` §2 rule 4: exact byte tests on Linux, no non-Sendable static `CIContext`. No colour conversion means no P3 drift (Capture C7). [Medium: if Strong blur on a 5K capture is slow, swap the gaussian for Core Image behind the same function, keeping the goldens.] |
| E6 | **Text is measured on macOS and represented in the display list.** A `TextMeasuring` port (§3) gives each line's width, ascent and descent: Core Text on macOS, a fixed-advance fake on Linux. A text annotation renders as one `textRun` per line, at its baseline. Typing happens in **one reusable `NSTextView`** owned by the canvas, with zero padding and zero inset, placed at the annotation's origin; the annotation being edited is hidden from the list. | IME, dead keys and typing undo come free from AppKit. One reused view fixes the closed-canvas retention; zero padding removes the 2 pt hack (`33d2852`, `design/03` §5.4). [Low-Medium: a fully model-rendered editor is the next step if the field and the render differ visibly.] |
| E7 | **Step numbers are computed**, not stored: a step's number is 1 + the number of steps below it in z-order. Deleting step 2 renumbers 3 to 2; undo restores. | `design/03` §5.4: numbering can't get gaps. Collections compute them already. [Low] |
| E8 | **Later features are absent, not disabled.** Copy Text, Copy for AI, the source chip, the find and sweep bars, Live Text, snapping, Copy as Markdown, Open Source, Find Similar and the collection-image mode have no button, no menu item and no space in Wave 1. `EditorCore` reserves their slots (§8.3), so each later epic adds rows, not rewrites. | A disabled control that never enables in Wave 1 is noise. `design/03` implies nothing different. [Low] |
| E9 | **Options are per editor and not persisted.** One `ToolOptions` value per editor, shared by every tool, starting at the defaults of §5.5. No editor settings keys and no Settings pane in Wave 1 (`editor.snapToElements` is reserved for snapping). | `design/03` stores nothing. [Low] |
| E10 | **One renderer, three lists.** `EditorRenderer` produces the **base** list (everything except the active annotation), the **active** list (the annotation being drawn, moved or resized) and the **overlay** list (selection outline, handles, crop dimming, never exported). Export is the base list with nothing active or hidden. The canvas caches the rasterised base keyed by the base list's hash. | WYSIWYG by construction; keeps the 180 ms fix (`645eecd`). [Low] |
| E11 | **The Core Graphics executor and the ImageIO helpers are editor-owned in Wave 1**, in `Sources/BugeyeApp/Editor/`. The editor doesn't extend Capture's `ImagePipeline`. A later epic that needs the executor (collections, motion) moves it with a ruling. | No file is shared with a parallel session. [Low: one move later.] |
| E12 | **Open Last Capture** follows the newest `created` event of any kind through `bus.item(id)`. It is enabled when that item exists, the router has an opener for its kind, and its file exists, all checked each time the menu opens (`60d29d1`). In Wave 1 only `.screenshot` has an opener. | Recording, GIF and collection openers register later without touching the editor. [Low] |
| E13 | **Saves are serialised and rendered off the main actor.** ⌘S snapshots the state; a save already in flight queues the next one. On completion `markSaved(snapshot)` uses the saved state, not the current one, so edits made during the save stay dirty. ⌘S on a clean document whose file exists does nothing. | Late results (`design/11` §6); export is slow on large captures. [Low] |
| E14 | **New strings the docs don't give**, settled in §5: tooltips, option labels, the frame popover's swatch names, the save and copy failures. | Every string is settled before implementation (`design/11` §7). [Low] |
| E15 | **Undocumented edges, settled:** Esc during a drag cancels it with no undo step; ⌘Z during a drag is ignored; moves aren't clamped; resizing ignores ⇧; switching away from Select deselects; the Crop tool draws a new crop on every drag (no crop handles); zoom-to-fit happens at open only, not on window resize. | The first build left them undefined. [Low] |
| E16 | **Testing split** (§9): model, interaction controller, undo, document lifecycle, blur algorithm, display-list golden JSON and every string on Linux; Core Graphics rasterisation goldens, the executor, AppKit wiring and leaks on hosted macOS CI; look and feel in your manual pass. No `needs-mac-check` label: nothing here needs Screen Recording. | `design/13` §2, `design/14` R8–R10. [Low] |

## 2. Scope

In scope:
1. `EditorModule`, the Edit action, Open Last Capture, the `.screenshot` opener (E2, E12).
2. Opening rules, one editor per capture, the window, Dock and main menu while open (§5.1).
3. Layout, toolbar, the 11 tools and their keys, text entry, degenerate input (§5.2–5.4).
4. The options strip and the background frame (§5.5–5.6).
5. The document: snapshot undo, coalescing, dirty state (§6.2).
6. Zoom (§5.7). Output: Copy, Save, Save As…, the drag handle, the gone alert, the unsaved prompts (§5.8–5.9).
7. The display list renderer, the blur algorithm, the Core Graphics executor (§7).

Out of scope (E8): Live Text (`design/03` §1.8), ⌘F find and the sweep bar (§1.9), snapping (§1.10), Copy Text, Copy for AI, Copy as Markdown, Open Source, Find Similar, the source chip, collection-image mode (§1.11), exact text (§2.12), Claude features (§5.5), indexing, opening from Find Capture or Spotlight.

## 3. Contract needs

Everything below lands in the Wave 1 contracts PR, before the epics start. Shapes are exact; doc comments state the rules the contracts PR tests.

### 3.1 `BugeyeCore`: display list (`DisplayList/DisplayList.swift`)

No feature uses Wave 0's display list yet, so the contracts PR reshapes it and rewrites its golden test.

```swift
/// Coordinates: origin top-left, y down, in the list's own pixels (`DisplayList.size`). The executor does
/// the one flip. Shadow offsets and blurs are in these pixels too; the executor multiplies them by the
/// device scale when it draws into a zoomed context.

public enum LineCap: String, Hashable, Codable, Sendable { case butt, round, square }
public enum LineJoin: String, Hashable, Codable, Sendable { case miter, round, bevel }

public struct Shadow: Hashable, Codable, Sendable {
    /// Positive y falls downward.
    public var offset: Point2D
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
    public var location: Double   // 0…1
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
    /// The system UI font. The executor and the measurer map it with `weight` (0.4 = bold, `NSFont.Weight.bold`).
    public static let systemFontName = "system"
}

extension DisplayList {
    /// Pushes and pops balance, and every `clip` sits inside a group.
    public var isBalanced: Bool { get }
}
```

### 3.2 `BugeyeCore`: the `TextMeasuring` port (`Ports/TextMeasuring.swift`)

```swift
public struct TextLineMetrics: Hashable, Sendable {
    public var width: Double
    public var ascent: Double
    public var descent: Double
    public init(width: Double, ascent: Double, descent: Double)
}

/// Measures one line of text, no wrapping, in pixels at `font.size` (Core Text on macOS). Fast enough to
/// call on the main actor for short strings.
public protocol TextMeasuring: Sendable {
    func measure(_ line: String, font: FontDescriptor) -> TextLineMetrics
}
```

`BugeyeTestSupport` gains `FakeTextMeasurer`: width = 0.6 × size × `line.count` (characters), ascent = 0.8 × size, descent = 0.2 × size.

### 3.3 `BugeyeCore`: the capture event bus (`Captures/CaptureEventBus.swift`, `CaptureItem.swift`)

```swift
extension CaptureChange {
    /// An editor opened on the capture. The item is unchanged.
    public static let editingStarted: CaptureChange
    /// That editor closed.
    public static let editingEnded: CaptureChange
}
```

Rule changes, each a test in the contracts PR:
- `CaptureEvent.preview` is set for `created` **and `edited`** (at most 480 px wide).
- `item(_:)` ignores `editingStarted` and `editingEnded`: it neither stores nor forgets.
- Quick Access's side (in its spec): the dismiss timer of a capture is paused from `editingStarted` to `editingEnded`; an `edited` event with a preview replaces the thumbnail image.

### 3.4 `BugeyeFeatures`: Quick Access action placement (`FeatureModule.swift`, `FeatureRegistry.swift`)

```swift
public enum QuickAccessPlacement: String, Hashable, Sendable { case primary, strip, moreMenu }

public struct QuickAccessActionSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var order: Int
    /// The kinds the action is offered for.
    public var kinds: Set<CaptureKind>
    /// `.primary` is the yellow button and the double-click action.
    public var placement: QuickAccessPlacement
    public init(id: String, title: String, order: Int,
                kinds: Set<CaptureKind> = Set(CaptureKind.allCases), placement: QuickAccessPlacement = .moreMenu)
}

// FeatureConflict gains:
case primaryActionTaken(CaptureKind, ids: [String])   // two primary actions for one kind
```

### 3.5 `BugeyeFeatures`: the action router (`ActionRouter.swift`)

This replaces the router Capture C12 planned inside `AppServices`, so Capture registers through it too.

```swift
@MainActor
public final class ActionRouter {
    public init()
    /// For a `MenuItemSpec` or `MainMenuItemSpec` id. `isEnabled` is asked each time the menu opens.
    public func onMenuItem(_ id: String, isEnabled: @escaping @MainActor () -> Bool = { true },
                           perform: @escaping @MainActor () -> Void)
    public func onHotkey(_ id: String, perform: @escaping @MainActor () -> Void)
    public func onQuickAccessAction(_ id: String,
                                    isEnabled: @escaping @MainActor (CaptureItem) -> Bool = { _ in true },
                                    perform: @escaping @MainActor (CaptureItem) -> Void)
    /// Opens a capture of this kind (Open Last Capture now; Find Capture and Spotlight later). One per kind.
    public func onOpen(_ kind: CaptureKind, perform: @escaping @MainActor (CaptureItem) -> Void)

    /// Each returns false when nothing is registered under the id.
    @discardableResult public func performMenuItem(_ id: String) -> Bool
    public func isMenuItemEnabled(_ id: String) -> Bool          // false when unregistered
    @discardableResult public func performHotkey(_ id: String) -> Bool
    @discardableResult public func performQuickAccessAction(_ id: String, on item: CaptureItem) -> Bool
    public func isQuickAccessActionEnabled(_ id: String, for item: CaptureItem) -> Bool
    public func canOpen(_ kind: CaptureKind) -> Bool
    @discardableResult public func open(_ item: CaptureItem) -> Bool
}
```

Registering an id or kind twice is a `preconditionFailure` (tests use a fresh router).

### 3.6 `BugeyeFeatures`: the document-window counter and the quit gate

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

/// Asked when the user quits (⌘Q, Quit Bugeye in either menu).
@MainActor
public final class TerminationGate {
    public init()
    /// Asked in registration order. Returning false cancels the quit, and later participants aren't asked.
    public func add(_ participant: @escaping @MainActor () async -> Bool)
    public func shouldTerminate() async -> Bool
}
```

### 3.7 `BugeyeFeatures`: the main menu (`MainMenu.swift`)

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

// FeatureModule gains, with a default of []:
func mainMenuItems() -> [MainMenuItemSpec]

public enum MainMenuEntry: Hashable, Sendable {
    case item(MainMenuItemSpec)
    case separator
}
public enum MainMenu {
    /// The shell's fixed items (below) with module items placed by group and order.
    public static func entries(for registry: FeatureRegistry) -> [MainMenuGroup: [MainMenuEntry]]
}
```

The shell's fixed items, which serve every document window (orders leave gaps of 10 for later items: Copy Text, Copy for AI, Copy as Markdown, Find…, Snap to Elements, Export…, Open Source, Find Similar):

| Menu (title) | Title | Key | Selector |
|---|---|---|---|
| Bugeye | Quit Bugeye | ⌘Q | `terminate:` |
| File | Save | ⌘S | `saveDocument:` |
| File | Save As… | ⇧⌘S | `saveDocumentAs:` |
| File | — | | |
| File | Close | ⌘W | `performClose:` |
| Edit | Undo | ⌘Z | `undo:` |
| Edit | Redo | ⇧⌘Z | `redo:` |
| Edit | — | | |
| Edit | Cut | ⌘X | `cut:` |
| Edit | Copy | ⌘C | `copy:` |
| Edit | Paste | ⌘V | `paste:` |
| Edit | Delete | | `delete:` |
| Edit | Select All | ⌘A | `selectAll:` |
| View | Zoom In | ⌘= | `zoomIn:` |
| View | Zoom Out | ⌘− (key `-`) | `zoomOut:` |
| View | Actual Size | ⌘1 | `zoomToActualSize:` |
| View | Zoom to Fit | ⌘0 | `zoomToFit:` |

The editor contributes no main-menu items in Wave 1; its window answers these selectors and validates them.

### 3.8 `BugeyeApp` shell (contracts PR edits; the editor never touches them)

- `Sources/BugeyeApp/Wiring/AppContext.swift`:
  ```swift
  @MainActor
  struct AppContext {
      let captureEvents: CaptureEventBus
      let router: ActionRouter
      let documentWindows: DocumentWindows
      let termination: TerminationGate
      let notifier: any Notifier
      let clipboard: any ClipboardWriter
      let metadata: any FileMetadataStore
      let settingsStore: any SettingsStore
  }
  ```
- One stub per Wave 1 epic, `Sources/BugeyeApp/Wiring/<Epic>Wiring.swift`, the editor's being:
  ```swift
  @MainActor
  enum EditorWiring {
      /// nil until the epic's last PR, so main never shows half a feature.
      static func install(_ context: AppContext) -> (any FeatureModule)?
  }
  ```
  `AppServices` builds its registry from `GeneralModule()` plus every wiring's non-nil result, in a fixed order.
- `AppDelegate`: module menu items and hotkeys go through `router` (C12's default branch); `applicationShouldTerminate` returns `.terminateLater` and replies with `termination.shouldTerminate()`.
- `MenuBarController` becomes the menu's delegate: `menuNeedsUpdate` sets each module item's enabled state from `router.isMenuItemEnabled`.
- `DocumentWindows`' apply closure: `.regular` sets the policy, installs the main menu from `MainMenu.entries` and activates Bugeye; `.accessory` removes the main menu and sets the policy back. `LSUIElement` stays in `Info.plist`.
- `MacAdapters` adapters for `ClipboardWriter` (`NSPasteboard`, one item: PNG, file URL, text) and `Notifier` (`UNUserNotificationCenter`) move from Capture's scope into the contracts PR, so `AppContext` has real ones whichever epic finishes first.

### 3.9 Not needed

No new settings keys, no Settings pane, no status-menu group, no hotkeys, no `CaptureFileWriter` change, no `Package.swift` change.

## 4. Coordinates

Units follow `design/03` §2.2, unchanged:
- **Annotations are stored in image pixels**, origin top-left, y down. Sizes (stroke width, font size, padding, corner radius, step diameter) are stored in **points** and multiplied by `ppp = max(1, item.pixelsPerPoint)` when rendered.
- **`CanvasLayout(imageSize:state:pixelsPerPoint:showingFullImage:)`** is the single source of geometry. Normal and export: `visible = crop ?? whole image`, `pad = round(frame.padding × ppp)` (0 without a frame), `size = visible + 2·pad`, `contentRect = (pad, pad, visible.size)`, `imageOrigin = (pad − visible.minX, pad − visible.minY)`. Crop tool: `showingFullImage = true`, the whole image and no frame.
- **The display list is in canvas pixels**, y down (§3.1). The canvas view is flipped; its unit is the point (canvas pixels / ppp); the scroll view's magnification is the zoom. Image point = `layout.imagePoint(fromCanvas: viewPoint × ppp)`.
- **Screen constants** (handle 8, hit distance 6, outline 1) are in screen points and become image pixels as `value × ppp / zoom`.

## 5. Behaviour

### 5.1 Opening and the window

- **Ways in (Wave 1):** Quick Access `Edit` and double-click (screenshots only), status menu `Open Last Capture` (E12). A request for another kind is refused by the router (no opener).
- **One editor per capture**, keyed by `CaptureID`. A request for a capture that has an editor, or one being opened, brings that window forward.
- **Opening:** the PNG is decoded off the main actor. Missing or unreadable: no window, and the notice `Couldn't open capture` / `<name> is missing or unreadable.` (`<name>` = the file name with its extension).
- **Bus:** `editingStarted` when the window shows; `editingEnded` when it closes (E3).
- **Dock and main menu:** `DocumentWindows.opened()` when the window shows, `closed()` when it closes (§3.6).
- **Window:** titled with the file name (with extension), `representedURL` set, resizable, content min 640 × 420 pt, `tabbingMode = .disallowed`, `isReleasedWhenClosed = false`. Initial content size: canvas in points + 40 pt each way, plus 78 pt of chrome height (toolbar 40 + divider 1 + options strip 36 + divider 1). Capped at 85 % of the main screen's visible frame, centred, then zoomed to fit (§5.7). The close button shows the edited dot while dirty.
- **Default tool:** Arrow.

### 5.2 Layout and toolbar

Top to bottom: toolbar (40 pt) · divider · canvas (scroll view, centred when smaller than the viewport) · divider · options strip (36 pt). The find and sweep bars of `design/03` §1.2 are absent (E8).

Toolbar, left to right: the 11 tool buttons, a divider, `Frame` (opens the popover, §5.6), spacer, Undo, Redo, `Copy`, `Save`, the drag handle. Copy Text, Copy for AI and the source chip are absent (E8).

| Control | Look | Tooltip |
|---|---|---|
| Tool buttons | SF Symbols of §5.3, selected one highlighted | `<Tool> (<Key>)`, e.g. `Arrow (A)` |
| Frame | text button `Frame` | `Background frame` |
| Undo | `arrow.uturn.backward` | `Undo (⌘Z)` |
| Redo | `arrow.uturn.forward` | `Redo (⇧⌘Z)` |
| Copy | text button `Copy` | `Copy the edited image (⌘C)` |
| Save | text button `Save` | `Save (⌘S)` |
| Drag handle | `hand.draw` | `Drag the edited image into another app` |

Undo and Redo are disabled when `canUndo` / `canRedo` is false. Every toolbar, options-strip and frame action commits typed text first.

### 5.3 Tools and keys

Plain letter keys on the canvas switch tools: no modifier (⇧ included), case-insensitive. They're ignored while the text view has focus.

| Key | Tool (tooltip name) | SF Symbol | Behaviour |
|---|---|---|---|
| V | Select | `cursorarrow` | Click selects (dashed outline + handles); drag moves; handles resize; Delete removes; double-click a text annotation re-edits it |
| C | Crop | `crop` | Drag a crop rect over the whole image (no frame), outside dimmed 50 % black, 1 pt white border. Each drag draws a new crop (E15). Non-destructive until export |
| A | Arrow | `arrow.up.right` | Drag tail → head. ⇧ snaps to 45° |
| R | Rectangle | `rectangle` | Drag. ⇧ makes a square. Outline or filled |
| O | Ellipse | `circle` | Drag. ⇧ makes a circle. Outline or filled |
| L | Line | `line.diagonal` | Drag. ⇧ snaps to 45° |
| T | Text | `textformat` | Click places a text field; click on a text annotation re-edits it |
| P | Pen | `pencil.tip` | Freehand polyline |
| H | Highlighter | `highlighter` | Freehand, 3 × stroke width, 40 % opacity; overlapping strokes of one annotation don't darken |
| B | Blur / Pixelate | `square.grid.3x3` | Drag a rect. Never has a shadow |
| N | Numbered step | `1.circle` | Click adds a filled circle with the next number (E7) |

Other canvas keys: **Esc** cancels a drag in progress (no step, E15), else deselects. **Backspace (key code 51)** and **forward Delete (117)** delete the selected annotation (one step). Everything else passes up the responder chain.

Cursor: arrow for Select, crosshair for every drawing tool and Crop, I-beam for Text.

### 5.4 Text entry and degenerate input

- The text view uses the bold system font at the chosen size in canvas points (the scroll view's magnification scales it), in the chosen colour. **Return** commits; **⌥Return** inserts a newline; **Esc** cancels; a click anywhere else on the canvas commits and does nothing else. Any toolbar, options or frame action, undo, save, copy, close or tool change commits first.
- Empty or whitespace-only text is discarded. Emptying a re-edited annotation deletes it (one step). A re-edit that changes nothing makes no step. A re-edit keeps the annotation's font size and colour.
- While typing, ⌘Z / ⇧⌘Z undo the typing (the text view's undo manager), not the document.
- **Degenerate input:** an arrow or line shorter than 3 image px, a rectangle, ellipse or blur narrower or shorter than 3 px, or a pen or highlighter stroke whose bounds are under 3 px on both sides creates nothing. A shape whose bounds miss the visible rect (in the padding or outside the crop) is dropped. A blur is clamped to the visible rect, then dropped if under 3 px. Text and steps can only be placed by a click inside the visible rect.

### 5.5 Options strip

Shows the current tool's options, or, in Select mode, the selected annotation's tool's options. Selecting an annotation loads its style into the options first (`dbadb7c`). Changing an option with an annotation selected restyles it: one undo step, even for a continuous colour-panel drag.

| Option | Tools | Control and values | Default |
|---|---|---|---|
| Colour | all but Select, Crop, Blur | 6 swatches, tooltips `Red` (1, .23, .19), `Orange` (1, .58, 0), `Yellow` (1, .8, 0), `Green` (.2, .78, .35), `Blue` (0, .48, 1), `Black` (0, 0, 0); a colour well, tooltip `Custom colour`, no opacity | Red |
| Width | Arrow, Rectangle, Ellipse, Line, Pen, Highlighter, Numbered step | segmented `Thin` 2 pt / `Medium` 4 pt / `Thick` 8 pt | Medium |
| Filled | Rectangle, Ellipse | checkbox `Filled` | off |
| Shadow | Arrow, Rectangle, Ellipse, Line, Pen, Text, Numbered step | checkbox `Shadow` | off |
| Size | Text | label `Size`, popup `16 pt` / `24 pt` / `36 pt` / `48 pt` | 24 pt |
| Mode | Blur | segmented `Pixelate` / `Blur` | Pixelate |
| Strength | Blur | segmented `Light` (1) / `Medium` (2) / `Strong` (3) | Medium |
| Crop | Crop | `<W> × <H> px` of the crop (U+00D7), or `Drag to crop` with no crop; button `Reset Crop` (one step; disabled with no crop) | |
| Select | Select, nothing selected | `Click an annotation to select it · drag to move · Delete removes it` | |

### 5.6 Background frame

The `Frame` popover: toggle `Background frame`; when on, six fill swatches, slider `Padding` 0–160 pt, slider `Corner radius` 0–32 pt (both in steps of 1, value shown as `<n> pt`), toggle `Shadow`.

- Off by default. Turning it on sets padding 48 pt, the first gradient, radius 10 pt, shadow on (one step).
- Fills (tooltips): `Indigo to pink` (.39,.40,.95) → (.93,.36,.70); `Orange to coral` (1,.62,.27) → (.96,.31,.45); `Teal to blue` (.20,.80,.75) → (.16,.42,.90); `Graphite` (.30,.32,.36) → (.08,.08,.10); `White`; `Black`. Gradients run diagonally from the canvas's top-left to its bottom-right.
- One slider drag is one step; a run of keyboard steps on a slider is one step, closed by the next other edit (`e68db00`).

### 5.7 Undo and zoom

- **Undo / Redo:** ⌘Z / ⇧⌘Z, the toolbar, the Edit menu. Rules in §6.2.
- **Zoom:** Zoom In ×1.25, Zoom Out ÷1.25, Actual Size 100 %, Zoom to Fit = min(1, (viewport − 2 × 20 pt) / canvas) on the tighter axis. Pinch and smart magnify (two-finger double-tap) use AppKit's behaviour. Range 10 %–800 %, clamped. 100 % = one view point per canvas point.
- Handles, outlines and hit areas keep their screen size at any zoom. The zoom reaches the interaction controller on every clip-view bounds change, smart magnify included (`c1db340`).

### 5.8 Output

| Command | Key | What happens |
|---|---|---|
| Copy | ⌘C, toolbar | The export render as PNG on the clipboard (`ClipboardPayload(png:)`). No notice on success |
| Save | ⌘S, toolbar | The export render through `CaptureFileWriter` (E4), then `markSaved`, then publish `edited` with a preview (E3) |
| Save As… | ⇧⌘S | Save panel: name field = the file name, folder = the file's folder, PNG only. Writes a copy (E4). The editor keeps the original and stays dirty. No event |
| Drag handle | | Drags a PNG named like the capture, written to `<temp>/Bugeye-Drag/` (E4). Files there older than 24 h are deleted when a drag starts |

- The export render is the base list with nothing active or hidden, in the capture's colour space (sRGB if it isn't RGB), 8-bit RGBA premultiplied, rendered off the main actor (E13).
- **Gone file:** if the file is missing at Save, alert `The original file is gone` / `“<name>” was moved or deleted since it was opened.`, buttons `Save As…` and `Cancel`. After Save As from there, the editor tracks the new file (E4) and retitles.
- **Failures:**
  - Save or Save As write: alert `Couldn't save “<name>”` / `<the error's localizedDescription>`, button `OK`. The document stays dirty.
  - Copy: notice `Couldn't copy` / `The image couldn't be put on the clipboard.`
  - Drag file write: the drag doesn't start, a beep, a log line.

### 5.9 Unsaved changes

- Closing a dirty editor (close button, ⌘W) asks `Save changes to “<name>”?` / `Your annotations will be lost if you don't save them.`, buttons `Save`, `Don't Save`, `Cancel`. Save that fails, or a gone-file alert answered with Cancel, keeps the window open.
- Quit asks the same for every dirty editor in turn, bringing each forward (a `TerminationGate` participant). Cancel stops the quit; the remaining editors aren't asked.
- A clean editor closes without asking.

## 6. Model and interaction rules

### 6.1 Model

```text
AnnotationShape: arrow(from, to) · line(from, to) · rectangle(rect, filled) · ellipse(rect, filled)
                 · text(origin, string, fontSize pt) · pen([points]) · highlighter([points])
                 · blur(rect, mode: pixelate|blur, strength 1…3) · step(center)
Annotation: id, shape, style (color RGBAColor, width thin|medium|thick, shadow)
EditorState: annotations (z-order, bottom first), crop: Rect2D?, frame: BackgroundFrame?
BackgroundFrame: padding 48, fill gradient(0…3) | white | black, cornerRadius 10, shadow true
ToolOptions: color, width, filled, shadow, fontSize, blurMode, blurStrength (defaults §5.5)
```

- `clampedCrop` rounds to whole pixels, intersects the image, and rejects anything under 3 px.
- Step number = 1 + steps below it (E7). Text `origin` is the top-left of the first line's box.

### 6.2 Document and undo

`EditorDocument` (pure, not `@MainActor`), from `design/03` §2.4:
- U1. `beginChange()` remembers the state only if no change is open; `update {}` mutates; `endChange()` pushes the remembered state only if the state differs, and clears redo. `apply {}` = begin + update + end.
- U2. A drag (draw, move, resize, crop, slider) is begin on mouse-down, updates, end on mouse-up: exactly one step. A click that changes nothing makes none.
- U3. At most 200 undo steps; the oldest is dropped.
- U4. `canUndo` is also true while an open change differs from its start; `undo()` closes it first.
- U5. Restyle coalescing: repeated option changes on the same selected annotation extend one open change; any other action closes it. An unbracketed frame change (keyboard slider steps) opens a change the next edit closes.
- U6. `isDirty = state != savedState`; `markSaved(state)` takes the state that was written (E13).
- U7. After undo or redo, a selection whose annotation no longer exists is cleared.

### 6.3 Interaction controller

Pure; the canvas sends events in image pixels with the click count and modifiers, and the current zoom.

- I1. **Tolerances:** handle size 8, hit distance 6, both × ppp / zoom. Hit tolerance = max(stroke width / 2, hit distance).
- I2. **Hit testing,** topmost first: line and arrow by distance to the segment; rectangle and ellipse outline as a ring of ± tolerance, the inside too when filled; pen and highlighter by distance to any segment; text, blur and step by bounds.
- I3. **Handles:** 8 for rectangle, ellipse, blur; `start` and `end` for line and arrow; none for pen, highlighter, text and step (move only). A resize keeps the grab offset, so clicking a handle doesn't jump the edge (`dbadb7c`). Dragging past the opposite edge flips.
- I4. **Select mouse-down:** a handle of the selected annotation resizes; else the topmost hit is selected (options loaded) and moved; a double-click on text begins re-editing; else deselect.
- I5. **Drafts:** a shape tool's drag makes a draft, drawn live as the active list; on mouse-up the §5.4 rules apply, then it is added in one step. ⇧ constrains drawing only (E15).
- I6. **Text:** returns `beginTextEntry(origin, editing: id?)`; `commitText` adds, replaces or removes per §5.4; the edited annotation is hidden while its text view is up.
- I7. `displayState` = state − hidden + draft + draft crop; `activeID` = the annotation being drawn, moved or resized.

### 6.4 Session lifecycle

`EditorSessions` (portable, `@MainActor`) owns the open editors and emits effects the shell performs. Rules, each a test with a fake bus, router, writer and clipboard:
- S1. `open(item)` for an id that is open or opening emits `bringForward` only.
- S2. A successful open emits `showWindow`, then `documentWindows.opened()` and `editingStarted`, in that order. A failed decode emits only the notice.
- S3. Every close emits `editingEnded` and `documentWindows.closed()` exactly once.
- S4. `saved` and `moved` events for an open id re-point the session to `event.item.fileURL` and retitle. `deleted` marks the file gone.
- S5. Save on a gone file emits the alert, never a write.
- S6. A save result applies only if its generation is the session's latest for that file (late results, `design/11` §6).
- S7. Quit visits dirty sessions in opening order and stops at the first Cancel.
- S8. Open Last Capture's enabled state follows E12.

## 7. Rendering

`EditorRenderer.lists(state:image:layout:ppp:measurer:active:hidden:zoom:)` → base, active and overlay `DisplayList`s (E10). The base list:

1. **No frame:** push a group, clip to `contentRect`, `image("capture", imageOrigin + image size)`, every annotation translated by `imageOrigin`, pop.
2. **Frame:** the fill over the whole canvas (solid, or `fillLinearGradient` from (0, 0) to (width, height)); push an unbounded group with shadow offset (0, 6 ppp), blur 20 ppp, black 40 %, isolated; clip to `roundedRect(contentRect, min(radius × ppp, half the short side))`; the content of 1; pop.
3. **Per annotation:** push an isolated group with bounds = annotation bounds + 16 ppp, opacity 0.4 for highlighter, and, when `shadow` is on, offset (0, 2 ppp), blur 6 ppp, black 45 % (never for highlighter or blur); the shape; pop.
   - Strokes: round caps and joins. Highlighter width = 3 × width.
   - Arrow: head length = min(length, max(width × 3.5, 12 ppp)), half-width 0.45 × head; the shaft stops 0.3 × head inside the head.
   - Text: font `system`, weight 0.4, size × ppp; one `textRun` per line, baseline at origin.y + ascent + line index × (ascent + descent).
   - Step: filled circle of diameter 22 / 28 / 36 pt (thin / medium / thick) × ppp; number at 0.55 × diameter, centred by measured width; black on light colours, white on dark (`0.299r + 0.587g + 0.114b > 0.6`).
   - Blur: `blurRegion(rect + imageOrigin, sourceImageID: "capture", sourceRect: rect rounded outward, effect)`, with pixelate cell = strength × 6 × ppp and gaussian radius = strength × 5 × ppp.

Overlay list (never exported, widths × ppp / zoom): crop dimming and border, selection outline (1 pt, dash 4/3, outset 2 pt), white 8 pt handle squares with a 1 pt grey border.

**`RegionEffects`** (E5): `pixelate(_:cellSize:)` averages each cell, with the grid anchored at the source rect's origin; `gaussianBlur(_:radius:)` is three box passes per axis with clamped edges. Results cached by the shell by (source rect, effect), cleared past 64 entries.

**Executor** (macOS): flips once; maps groups to `saveGState` / `setAlpha` / `setShadow` × device scale / transparency layers; `clip`; gradients extended at both ends; `textRun` through Core Text with the same font mapping as the measurer.

## 8. Architecture

### 8.1 By target

| Target | Platform | Editor's content |
|---|---|---|
| `BugeyeCore`, `BugeyeFeatures`, `BugeyeTestSupport`, shell files | | Contract only (§3), in the contracts PR |
| `EditorCore` | portable | `EditorModule`; model (§6.1); `EditorDocument`; `EditorTool`, `EditorShortcuts`; `AnnotationGeometry`; `CanvasLayout`; `InteractionController`; `TextLayout` (on `TextMeasuring`); `EditorRenderer`; `RegionEffects`; `ZoomModel`; `WindowSizing`; `EditorSessions`; `LastCapture`; chrome models (toolbar, options strip, frame popover, reserved slots); `EditorStrings` |
| `MacAdapters` (`Editor/`) | macOS | `CoreTextMeasurer` |
| `BugeyeApp` (`Editor/`, `Wiring/EditorWiring.swift`) | macOS | Wiring; window controller; flipped canvas view; centring clip view; the one reusable text view; SwiftUI toolbar, options strip and popover; the display-list executor; PNG decode and encode, region extraction (E11); drag provider; save panel; alerts |

### 8.2 Main thread

Decode, export renders, PNG encoding, region effects and writes run off the main actor. The canvas's base bitmap is rendered on the main actor only on a state change, never per mouse move.

### 8.3 Reserved slots (E8)

`EditorCore`'s chrome model has named, empty slots: toolbar `copyText` and `copyForAI` (before `Copy`), `sourceChip` (after the drag handle); bars `find` and `sweep` (between toolbar and canvas, reserving their height when shown); an `EditorServices` value whose optional ports (`TextReader`, `FaceFinder`, `RectangleFinder`) are nil in Wave 1. `EditorState` and `InteractionController` keep a snapping hook that returns its input unchanged.

### 8.4 Logging

`os.Logger`, subsystem `dev.msenechal.bugeye`, category `editor`: `open <file name>` · `open failed <file name>: <reason>` · `close <file name>` · `saved <file name> in <ms> ms` · `save failed <file name>: <error>` · `drag file failed: <error>`. Text annotation contents are never logged.

## 9. Done when

1. The contracts PR (§3) has merged before the epic's first PR.
2. Per R10, CI runs when each PR is marked ready: `linux` and `macos` green, `claude-review` posted. Drafts rely on the session's own `make test-core`.
   - **Linux:** U1–U7, I1–I7, S1–S8, degenerate input, `CanvasLayout` (crop, frame, 1× and 2×), arrow and step maths, computed step numbers, `RegionEffects` on synthetic buffers byte for byte (edges clamped, grid anchored), golden JSON of the base, active and overlay lists for: each tool, frame on and off, crop, shadows, highlighter, blur, multi-line text with `FakeTextMeasurer`; every list `isBalanced`; every string in §5 character for character.
   - **macOS CI:** pixel goldens with a small tolerance: orientation (a shape at the top-left lands top-left; blur samples the pixels under it, not a mirrored region), crop + frame + 2× sizes, frame shadow on a transparent capture, highlighter overlap, Strong pixelate and blur, text against `CoreTextMeasurer`; device-scale shadows in a zoomed context; save keeps the ID and other `dev.msenechal.bugeye.*` xattrs (real `XattrMetadataStore`); Save As gets a new ID; the menu validation; `DocumentWindows` policy round trip; the unsaved and quit prompts with injected answers; a leak test that polls for the editor, its window **and its canvas**.
3. The final review's Critical and Important findings are fixed, each with a test that failed first.
4. Your manual pass, `docs/checklists/wave-1-editor.md` (`design/11` §5 format), after Capture and Quick Access have merged: Before you start (quit the old app) · Shortcuts table · How to check (`ls ~/Pictures/Bugeye`, `xattr -l <file>`, `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`) · A. Opening: Edit, double-click, Open Last Capture, second open brings it forward, missing file, Dock icon and menu appear and leave · B. Each tool and letter key, ⇧ constraints, degenerate clicks · C. Text: Return, ⌥Return, Esc, click away, re-edit, ⌘Z while typing, accents · D. Options and restyle, colour panel drag = one undo · E. Frame: fills, sliders, keyboard steps, shadow on a window capture · F. Undo and redo per gesture · G. Zoom: menu, pinch, smart magnify, handles stay the same size · H. Output: Copy into Slack, Save then Quick Access preview, Save As, drag handle into Finder and Slack · I. Gone file, unsaved close, quit with two dirty editors · J. A 5K capture with a frame: drawing stays smooth, Strong blur.
5. You say "all good", and the last PR merges.

## 10. Contradictions found in the sources

- Copy for AI is ⌥⇧⌘C in `design/03` §1.7 and `design/06`, but ⌥⌘C in `design/01` §1.4. Out of scope here; its epic should take ⌥⇧⌘C.
- Step numbers: stored and reused in `design/03` §2.3, computed in §5.4. E7 takes §5.4.
- Text entry: a fresh `NSTextField` per entry with a 2 pt offset in §2.7, a model-rendered text in §5.4. E6 takes a middle path.
- Capture C12 puts the action router in `AppServices`; the contracts PR moves it to `BugeyeFeatures` (§3.5). Capture's spec needs a one-line update.
- Capture §3 documents `CaptureEvent.preview` for `created` only; the editor needs it on `edited` (§3.3).
- Wave 0's `blurRegion(_, radius:)` can't name its source or a pixelate mode, and the list has no layers, clips, gradients or stroke caps, all of which `design/03` §5.2 lists. §3.1 reshapes it.
- Capture C17 places the clipboard and notifier adapters in its own epic; the editor needs them too, so §3.8 moves them into the contracts PR.
