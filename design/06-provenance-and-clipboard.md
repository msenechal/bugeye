# 06 · Provenance, the source chip and the rich clipboard (M7)

M7 makes every capture remember **where it came from**. That is its *source record*, or provenance: the apps and window titles under it, the Arc or Chrome tab's address, or the document's path. Bugeye then:
- shows the source as a **chip** on the capture
- opens it again (**Open Source**)
- writes it into Finder's **Get Info → Where from**
- uses it for richer copying: the normal copy, **Copy for AI** and **Copy as Markdown**
- learns which action you usually take for captures from each app, and rings it (**ActionHabits**)

M7 also raised the macOS minimum to 26.

The code is the source of truth. Where the shipped code differs from the spec (`docs/superpowers/specs/2026-10-22-provenance-design.md`), this file follows the code and says so.

Other sources:
- plan: `docs/superpowers/plans/2026-10-22-m7-provenance.md`, including its appendix of drafter rulings
- checklist: `docs/manual-checklist-m7-provenance.md`, passed in full by the user
- `docs/backlog.md`
- git history `3ace1ad..b1bd3bf` (merge `b1bd3bf`)

---

## 1. What it does

### 1.1 The record, per kind of capture

| Capture | Sources recorded |
|---|---|
| Area screenshot (⇧⌘4), scrolling capture by area (⇧⌘6) | Every counted window under the selection, ranked by visible share. The window list is the one the selection overlay took when it opened, i.e. the moment the hotkey was pressed. |
| Full screen (⇧⌘3, ⌥⇧⌘3) | Ranked over each display's whole frame, from a fresh window list. Each display's file gets its own record. |
| Window screenshot (Space + click), scrolling capture by window | That window only, share 1 (100 %) |
| Area or display recording (⇧⌘5) | Ranked over the area or display, from a window list taken **as the take starts** (the options bar may have been open a while) |
| Window recording | The followed window only, share 1 |
| Capture Text (⇧⌘7) | None. Nothing is saved. |
| Trimmed copy, GIF export, GIF-format recording, editor Save As…, Quick Access Save As… | The original's record, copied |
| Collections (M11) | Each `ImageBlock` keeps its image's source; out of scope here |

**Timing rule: a capture never waits for provenance and never fails because of it.**
- Collection starts as the selection closes, in parallel with the capture, off the main thread.
- The thumbnail, the clipboard and the save don't wait.
- The record arrives **up to about 1 s later**. It is then written to the file and set on the `CaptureItem`, and Quick Access re-renders, so the chip appears.
- The checklist tells the user to wait 1 s after the thumbnail.

**The first capture from a browser has no URL.** macOS shows the Automation prompt ("“Bugeye” wants access to control “Arc”"). The user's answer comes after the 1 s budget, so that capture records the app and title only. Later captures have the address. This is accepted behaviour (checklist B1, `dea0226`).

### 1.2 Where the user sees it

- **Finder Get Info → More Info → Where from:** the main source's URL, else its document path, else nothing.
- **Terminal:**
  - `mdls -name kMDItemWhereFroms "<file>"` prints "Where from".
  - `xattr -p dev.msenechal.bugeye.provenance "<file>"` prints the JSON record.
- **Source chip** (Quick Access and editor), described in §1.3.
- **Copy for AI** block and **Copy as Markdown** alt text, described in §1.5.
- **Search (M10):** the index stores the sources (app, title, URL) for Find Capture's app chips and words. See the search findings.

### 1.3 The source chip

- **Content:** the main source's app icon (14×14) plus a short label, chosen in this order:
  1. the URL's host, `:port` and path, with trailing slashes dropped and the path percent-decoded, e.g. `localhost:7474/browser`. The host is kept as is, with no "www." stripping.
  2. the document's file name
  3. the window title
  4. the app name
- **Length:** at most 32 characters. Longer labels are cut in the middle with `…`: the first 16 characters, `…`, the last 15.
- **Tooltip:** one line per source, `Arc — Neo4j Browser — https://… (62 %)`. A missing title is left out. The third part is the URL, else the document path.
- **Quick Access:** a dark capsule at the top of the thumbnail, right of the close button (night style, 10 pt medium text).
- **Editor:** in the toolbar, next to the drag handle, in system colours. It shortens first when the window is narrow.
- **No main source** (an empty `sources` list, or no record at all): no chip, and **Open Source** is hidden in Quick Access and greyed out in the editor's File menu.

### 1.4 Open Source

- **Ways in:**
  - click the chip (opens the main source)
  - Quick Access ⋯ → **Open Source**
  - editor **File → Open Source** (main source)
- **With several sources,** the ⋯ item becomes **Open Source ▸**, a submenu with one item per source, titled `Arc — Neo4j Browser · 62 %`. The editor's chip also offers the menu.
- **Routing** (`SourceOpener.action`, pure):

| Source has | Action | Result |
|---|---|---|
| A URL | `.openURL(url, appBundleID:)` | Opens in the app it came from (`NSWorkspace.open([url], withApplicationAt:)`). If that app isn't installed, the default browser. **The URL wins over a document path.** |
| A document path, file exists | `.openFile(path, appBundleID:)` | Opens in the source app; if that isn't installed, in the default app |
| A document path, file gone | `.fileGone` | Notification `The source file is gone (moved or deleted)`, body `App — Title` |
| App only, installed | `.activate(bundleID:, windowTitle:)` | Activates (or launches) the app. With Accessibility, raises the window whose `AXTitle` equals the recorded title (`AXRaise`). |
| App only, not installed, or no bundle ID | `.notInstalled(appName:)` | Notification `<App> isn't installed` |

An empty `documentPath` counts as none.

### 1.5 Copying

**The normal copy** covers auto-copy after a capture, Quick Access **Copy**, and the editor's ⌘C (image). It writes **one** `NSPasteboardItem` with:

| Type | When | How |
|---|---|---|
| `public.png` | always | the PNG bytes |
| `public.tiff` | only when an app asks | lazy `NSPasteboardItemDataProvider` (`TIFFFromPNG`): no eager TIFF |
| `public.file-url` | when the capture has a file on disk (delivery, Quick Access Copy). Not for the editor's copy of unsaved edits. | `item.setString(fileURL.absoluteString, forType: .fileURL)` |
| `public.html` | only when an app asks | lazy provider (`HTMLFromPNG`): `<img src="data:image/png;base64,…">`, a data URI, so Mail and Notes never point at a local file |

- **No plain text and no alt text.** The user dropped alt text.
- **Markdown is not on the normal copy.** It is a separate command.
- **Verified paste targets:**
  - Mail and Notes: the image, with no broken link
  - Slack: **one** upload, not two
  - Finder ⌘V: copies the file
  - Obsidian, Gmail, a GitHub comment: the image, never the base64 text
  - terminals: the file path, because they read the file URL
- **Recordings, GIFs and collections** use `writeFileReference(url)` instead: the file itself, so it pastes as an attachment.

**Copy as Markdown**
- **Where:**
  - Quick Access ⋯ → `Copy as Markdown`, for screenshots, which include scrolling captures
  - editor **Edit → Copy as Markdown** (no shortcut); disabled for a collection's image
- **Text written** (plain `.string`): `![<alt>](<path>)`
  - `<alt>` is the main source's `App — Window title` (the app alone without a title), or the file name without provenance. `[`, `]` and newlines are removed.
  - `<path>` is the absolute file path, in angle brackets when it contains a space: `![Arc — Neo4j Browser](</Users/me/Pictures/Bugeye/Screenshot 2026-10-22 at 10.14.03.png>)`
- **An unsaved (temp) capture is saved to the folder first,** like Quick Access Save, so the link outlives the 24 h temp purge. The thumbnail's button then reads **Save As…**.
- **In the editor** it first saves the edits exactly like ⌘S, including the "The original file is gone" alert. Cancel copies nothing; Save As… saves and copies the new file's link.
- **Notification:** `Markdown link copied`, with the file name as its body.

**Copy for AI**
- **Where:**
  - Quick Access ⋯ → `Copy for AI`, for screenshots
  - editor toolbar button `Copy for AI` (tooltip `Copy for AI (⌥⇧⌘C)`) and **Edit → Copy for AI**, ⌥⇧⌘C
- **Writes one pasteboard item:** `public.png` (with lazy TIFF) plus `public.utf8-plain-text` (the block below).
  - **No file URL.** In Claude Code, Ctrl+V attaches the image and ⌘V pastes the text. A file URL would make ⌘V paste a path in a terminal.
- **The capture isn't saved.** In the editor the image is the **flattened render**, so blurs and annotations show and blurred text isn't read. The file on disk is unchanged.
- **It waits for OCR** (about 1 s; with M9, exact text where the snapshot has it).
- **The block** (`ContextPack.text`):
  ````
  Source: Arc — Neo4j Browser (62 %) · Terminal — zsh (30 %)
  URL: https://…/browser
  File: /Users/…/README.md
  Captured: 2026-10-22 10:14
  Text:
  ```text
  …recognised text, laid out line by line…
  ```
  ````
  - `Source:` appears only with a main source. `URL:` and `File:` come from the **main** source only, and only when present (an empty path is skipped).
  - `Captured:` uses `yyyy-MM-dd HH:mm`, `en_US_POSIX`, in the local time zone.
  - The **code fence grows** past the longest run of backticks in the text (at least 3). A captured terminal showing ```` ``` ```` can't close the block.
  - No text read means no `Text:` part.
- **Notifications:**
  - `Copied for AI`, with the text summary as its body (e.g. `$ make test (14 lines)`, plus ` · exact text from …` after M9)
  - if recognition fails or finds nothing: `Copied for AI (no text read)` / `The image and its details are on the clipboard.`
  - an unreadable file: `Couldn't copy for AI` / `<name> is missing or unreadable.`

### 1.6 Learned next action (the ring)

- **What's learned:** for each pair (main source app, capture kind), the last **20** actions taken from Quick Access or the editor.
- **The suggestion** is the most frequent of those, if it occurred **at least 3 times** and in **more than half** of them.
- **No main source means no suggestion and no recording.**
- **Counted actions** (`QuickAction`): `copy, save, edit, copyText, copyForAI, copyMarkdown, openSource, reveal, exportGIF`. `edit` also covers Trim for recordings.
- **Never counted:** Delete, drag-out, a dismiss with no action, and the editor's close-prompt Save.
- **UI:**
  - if the suggested action is on the strip (Copy, Save / Save As…, Edit), that button gets a 1.5 pt accent ring (`NightChrome.accent`)
  - otherwise the **⋯** button gets the ring, and the menu item's title starts with `★ `, e.g. `★ Copy for AI`
  - there's no keyboard shortcut for it
- **The ring re-renders** when a late record arrives.
- **Stored in UserDefaults** under `actionHabits` (JSON).

### 1.7 Settings → Setup: browser permission

- One block titled **Browser URLs (Arc, Chrome)**. Under it, one row per **installed** browser: `Chrome: Allowed`, `Chrome: Not asked` or `Chrome: Not allowed`.
- **Not asked:** an **Allow** button. It runs a harmless AppleScript (`tell application id "…" to get name`), which launches the browser and makes macOS ask.
- **Not allowed:** an **Open Settings** button. It opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.
- There's a **Re-check**. The status is looked up off the main thread, only when Settings opens.
- **There is no on/off setting:** declining in macOS is the off switch.
- `Info.plist` → `NSAppleEventsUsageDescription`: `Bugeye reads the address of the browser tab you capture, so you can open it again later.`
- To reset during testing: `tccutil reset AppleEvents dev.msenechal.cleanshotcopy`.

---

## 2. How it's built

### 2.1 Files

| Layer | File | Contents |
|---|---|---|
| CSCore | `Provenance.swift` | `CaptureSource`, `CaptureProvenance` (JSON, version check) |
| CSCore | `ProvenanceRanker.swift` | visible-share ranking over a grid |
| CSCore | `ProvenanceStore.swift` | xattr read, write and copy; "Where from" |
| CSCore | `SourceText.swift` | `SourceLabel` (chip, tooltip, menu title), `MarkdownLink`, `ContextPack` |
| CSCore | `SourceOpener.swift` | Open Source routing (`Action`, `notice`) |
| CSCore | `ActionHabits.swift` | `QuickAction`, `ActionHabits` |
| CSCore | `OutputRouter.swift` | `ClipboardWriting` protocol; `CaptureItem.provenance`; copy after write; `deliverFile` reads the record back |
| CSCore | `WindowHitTest.swift` | `WindowInfo` (id, pid, owner name, layer, bounds, alpha, `title` = `kCGWindowName`) |
| App | `Provenance/ProvenanceCollector.swift` | `ProvenanceLookups` (the seam), `ProvenanceCollector`, `within(budget)` |
| App | `Provenance/ProvenanceLookups+Live.swift` | live lookups: `NSRunningApplication`, `BrowserScript` (AppleScript), `AXDocumentReader` |
| App | `Provenance/StoredProvenance.swift` | `CaptureItem.withStoredProvenance()` (and the M9 snapshot) |
| App | `PasteboardClipboard.swift` | `writeImage`, `writeImageAndText`, `writeFile`, `writeFileReference`, `writeText`; `TIFFFromPNG`, `HTMLFromPNG` |
| App | `SourceLauncher.swift` | `SourceWorkspace` seam, `SourceLauncher`, `SystemWorkspace` (NSWorkspace + AX raise) |
| App | `ActionHabitsStore.swift` | UserDefaults wrapper; key = `bundleID ?? appName` |
| App | `Settings/BrowserAutomation.swift` | `AutomationStatus`, `BrowserAutomation` seam, `AEDeterminePermissionToAutomateTarget` |
| App | `QuickAccess/ThumbnailView.swift` | `SourceChip`, `SourceChipView`, `SourceChipLabel`, strip slots, ring, ★ titles |
| App | `QuickAccess/QuickAccessController.swift` | `perform(_:on:source:)`, `updateProvenance`, `copyMarkdown`, `saveCopy(of:to:)` |
| App | `Editor/EditorWindowController.swift` | chip, Open Source, `copyForAIRendered`, `copyMarkdown`, `keepProvenance` |
| App | `TextCapture/TextCopier.swift` | `copyForAI(png:image:pixelsPerPoint:provenance:capturedAt:snapshot:)`, `copyForAI(fromFile:)` |
| App | `CaptureCoordinator.swift` | `collectProvenance(area:…)`, `collectProvenance(window:…)`, `attach(_:to:)` |
| App | `Recording/RecordingCoordinator.swift` | `collectProvenance(for:)` at take start; `attach(_:to:)` writes onto the finished file |

### 2.2 Data model

```swift
public struct CaptureSource: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleID: String?
    public var windowTitle: String?
    public var url: URL?             // Arc / Chrome active tab
    public var documentPath: String? // AXDocument
    public var share: Double         // 0...1 visible share of the captured area
}
public struct CaptureProvenance: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var sources: [CaptureSource]   // main source first
    public var displayID: UInt32?
    public var selection: CGRect?         // Quartz global points; nil for a window capture
    public var main: CaptureSource? { sources.first }
}
```
- **Encoding:** `JSONEncoder` with `.sortedKeys`. `CGRect` uses its default Codable form `[[x,y],[w,h]]`; `URL` is encoded as a string.
- **Decoding** rejects corrupt JSON and any `version` outside `1...currentVersion`. Such a record is treated as none.
- **An empty `sources` list is still written.** It keeps `displayID` and `selection`; `main` is nil, so there's no chip.
- **`CaptureItem.provenance`** is nil for captures from before M7 and when nothing was recorded.

### 2.3 Ranking (`ProvenanceRanker.rank(windows:selection:ownPID:)`)

- **Input:** windows front to back, in Quartz global points (top-left origin), from `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` → `WindowHitTest.parse`.
- **Counted windows:** `layer == 0`, `ownerPID != Bugeye's`, and `alpha > 0`. That excludes the desktop, the menu bar, the Dock and Bugeye's own overlay.
- **Sampling:**
  - a grid of cell centres across the selection
  - per side, `min(64, max(1, ceil(length / 8 pt)))` samples
  - each sample goes to the **frontmost** counted window containing it
  - samples over no window count toward the total, but for nobody
- **Share** = hits ÷ all samples. Windows under 2 % (`minimumShare`) are dropped as slivers.
- **Order:** share descending; ties go to the frontmost.
- **Display-local → global:** `ProvenanceCollector.globalRect(rect, displayBounds: CGDisplayBounds(id))` offsets by the display's origin.

### 2.4 Collecting (`ProvenanceCollector`)

```swift
struct ProvenanceLookups: Sendable {
    var bundleID: @Sendable (Int32) -> String?
    var browserURL: @Sendable (_ bundleID: String, _ windowTitle: String?) async -> URL?
    var documentPath: @Sendable (_ pid: Int32, _ windowTitle: String) async -> String?
}
final class ProvenanceCollector: Sendable {
    static let browsers: Set<String> = ["company.thebrowser.Browser", "com.google.Chrome"]
    init(lookups: ProvenanceLookups = .live, budget: Duration = .seconds(1))
    func collect(windows: [WindowInfo], selection: CGRect, displayID: UInt32?, ownPID: Int32) async -> CaptureProvenance
    func collect(window: WindowInfo, displayID: UInt32?) async -> CaptureProvenance
    static func within<T: Sendable>(_ budget: Duration, _ work: @escaping @Sendable () async -> T?) async -> T?
}
```
- The coordinator starts it with `Task.detached` and hands the `Task<CaptureProvenance, Never>` to `finish(...)`. When it completes, `attach(record, to: item)` runs.
- **All ranked windows are looked up at once** (`withTaskGroup`), so several browsers still share one 1 s budget. Each window's URL and document lookups also run concurrently (`async let`).
- **`within(budget)`** races the work against a sleep, using a lock-guarded "first result wins" continuation. A slow lookup is **left to finish unseen**; its result is discarded.
- **Bundle ID:** `NSRunningApplication(processIdentifier:)?.bundleIdentifier`.
- **Window title:** `kCGWindowName`. It is only present with **Screen Recording** permission, which Bugeye already needs. An empty title counts as none.
- **The document lookup is skipped without a title,** because it matches `AXTitle` against the title.

**Browser URL (AppleScript), `BrowserScript`**
```applescript
with timeout of 2 seconds
tell application id "com.google.Chrome"
    set chosen to front window
    repeat with w in windows
        if name of w is "<window title>" then
            set chosen to w
            exit repeat
        end if
    end repeat
    return URL of active tab of chosen
end tell
end timeout
```
- The same script works for Arc (`company.thebrowser.Browser`) and Chrome: both expose `URL of active tab of window`.
- **Strings are quoted** by escaping `\` and `"` (`BrowserScript.quoted`). Window titles are untrusted input.
- **Execution:** `NSAppleScript(source:).executeAndReturnError(&error).stringValue` on **one serial queue** (`dev.msenechal.bugeye.browser-script`), because `NSAppleScript` isn't meant for concurrent use. It's bridged to async with a continuation.
- **When the title doesn't match** (Chrome reports some tabs, such as PDFs, differently), the front window's URL is used. The checklist accepts this.
- **Declined, failed or slow** (> 1 s budget): `url` stays nil.
- **Code signing:** the app is signed with a self-signed identity and **without hardened runtime** (`scripts/bundle.sh`: `codesign --force --sign "CleanShotCopy Dev"`). So no `com.apple.security.automation.apple-events` entitlement is needed. A hardened or sandboxed rebuild would need that entitlement, plus the usage string.

**Document path (Accessibility), `AXDocumentReader.path(pid:windowTitle:)`**
- Requires `AXIsProcessTrusted()`. Without it, the path is nil.
- `AXUIElementCreateApplication(pid)`, then `AXUIElementSetMessagingTimeout(app, 0.5)` so a hung app can't hold the record back.
- `kAXWindowsAttribute` → the window whose `kAXTitleAttribute` equals the title → `kAXDocumentAttribute`.
- **`AXDocument` is usually a file URL string** (`file:///…`); a few apps give a plain path. `filePath(fromAXDocument:)` accepts a path starting with `/`, or a file URL, decoded without percent-encoding.
- It runs on a global queue. Verified with Preview (PDF) and VS Code.

### 2.5 Delivering and attaching the late record

1. `CaptureCoordinator.finish(image:scale:provenance:snapshot:)` encodes the PNG, then `router.deliver(...)` writes the file (save folder or temp) and **then** copies, so the clipboard can carry the file URL. The thumbnail shows.
2. `Task { attach(await provenance.value, to: result.item) }`.
3. `attach`:
   - First it tries `quickAccess.updateProvenance(record, for: id)`. That writes the xattrs onto the entry's **current** file (Save may have moved it), sets `entry.item.provenance`, re-renders the thumbnail (chip and ring), and fires `onItemChanged`. The coordinator's `lastItem`, open editors, media windows and the indexer all follow `onItemChanged`.
   - If the thumbnail is gone, it writes onto `lastItem`'s or the item's file directly, updates `lastItem`, and tells the indexer (`indexer?.moved`).
4. **Recordings:** the record is collected at take start. `RecordingCoordinator.attach` writes it onto the finished `.mp4` / `.gif` **before** delivery. `OutputRouter.deliverFile` moves the file (`moveItem` keeps xattrs) and reads the record back into the new `CaptureItem`.

### 2.6 Storage (`ProvenanceStore`)

| Attribute | Content |
|---|---|
| `dev.msenechal.bugeye.provenance` | the JSON `CaptureProvenance` (UTF-8, sorted keys) |
| `com.apple.metadata:kMDItemWhereFroms` | a **binary** property list: an array with one string, the main source's `url.absoluteString`, else its `documentPath`. Removed when the main source has neither, so a rewritten file never keeps a stale origin. |

- **API:** Darwin `getxattr` / `setxattr` / `removexattr` with options 0, through `url.withUnsafeFileSystemRepresentation`. Reading is two calls: first the size, then the data, and the result is accepted only if the second read returns the same size.
- **Failures are silent no-ops.** A file system that refuses xattrs just means no chip for that capture.
- **Spotlight imports `kMDItemWhereFroms`** from the xattr, so Finder's Get Info shows it with no other API. It works for file paths as well as URLs.
- `UISnapshotStore` (M9) and `CaptureIdentity` (M10, `dev.msenechal.bugeye.id`) reuse the same helpers. Every rule below applies to them too.

### 2.7 Atomic writes drop xattrs: every place that copies them back

**Rule: `Data.write(to:options: .atomic)` writes a temp file and renames it over the target, so the target's extended attributes are lost.** `FileManager.moveItem` keeps them (a rename). `FileManager.copyItem` usually keeps them on APFS, but Bugeye copies them explicitly anyway.

| Write path | File | How the record survives |
|---|---|---|
| First delivery (folder or temp) | `CaptureCoordinator.attach` / `QuickAccessController.updateProvenance` | written after the record arrives |
| Quick Access Save of a temp capture | `OutputRouter.save` → `moveItem` | rename keeps xattrs |
| Quick Access Save As… | `QuickAccessController.saveCopy(of:to:)` | `copyItem`, then `ProvenanceStore.copy` and `UISnapshotStore.copy`, then a **new** `CaptureIdentity` ID |
| Copy as Markdown on a temp capture | `saveToFolder` → `router.save` | rename |
| Editor ⌘S | `EditorWindowController.save` → `EditorExporter.save` (`.atomic`) | `keepProvenance(on:)` writes `item.provenance`; `keepSnapshot`; `CaptureIdentity.assign` re-applies the old ID |
| Editor Save As… | `saveCopy(to:)` → `EditorExporter.saveCopy` (`.atomic`) | `keepProvenance`, `keepSnapshot` |
| Editor save of a moved or deleted file (Save As… from the alert) | `saveReplacingMissingFile` | `keepProvenance`, `keepSnapshot`, `CaptureIdentity.assign(item.id)` |
| Trim | `TrimWindowController.save(range:)` | `ProvenanceStore.copy(from: source, to: out)` after the trimmer |
| GIF export | `MediaWindows.exportGIF` | `ProvenanceStore.copy` after encoding |
| GIF-format recording, MP4 recording | `RecordingCoordinator.attach` | written onto the finished file before `deliverFile` |
| **Not covered** | `EditorExporter.dragFile` (the editor's drag handle) | **no record**: a backlog item |

**Reading the record back** happens wherever a capture is reopened from a file:
- `CaptureItem.withStoredProvenance()` in the editor's init, the trim window, and Open Last Capture (`0e58d59`)
- the indexer (`Indexer`)
- collections (`CollectionManager`, `AppDelegate`)

### 2.8 Clipboard implementation (`PasteboardClipboard`)

```swift
public protocol ClipboardWriting: AnyObject {
    func writePNG(_ data: Data)                         // = writeImage(png:, fileURL: nil)
    func writeImage(png: Data, fileURL: URL?)           // the normal copy
    func writeImageAndText(png: Data, text: String)     // Copy for AI
    func writeFileReference(_ url: URL)                 // recordings: the file itself (NSURL)
    func writeText(_ text: String)                      // Copy Text, Markdown
}
```
- **Default implementations** in a protocol extension (`writeImage` → `writePNG`; `writeImageAndText` → `writePNG` + `writeText`) let older fakes keep compiling.
- **One `NSPasteboardItem` per copy.** `clearContents()`, then `writeObjects([item])`. A second item makes Slack upload twice.
- **Lazy types** via `item.setDataProvider(provider, forTypes: [.tiff])` and `[.html]`. A provider builds its data only when a reader asks, and then calls `item.setData` / `setString`. The item retains the provider until the clipboard changes. Tests hold the providers `weak` and check `produced == false` after a write.
- `writeFile(url)` (Quick Access Copy of a screenshot) reads the PNG from disk and calls `writeImage(png:fileURL: url)`.

### 2.9 Source chip, Open Source and habits wiring

- `SourceChip(provenance)` is nil without a main source. Its `icon` comes from `NSWorkspace.urlForApplication(withBundleIdentifier:)` + `icon(forFile:)`. **This is recomputed on every render** (a backlog item).
- `QuickAccessController.render(entry)` builds `ThumbnailView(…, provenance: entry.item.provenance, suggested: habits.suggestion(for: entry.item))`. Every strip and ⋯ action goes through `perform(action, on: id, source:)`, which first calls `habits.record(action, for: item)` and then acts.
- `ThumbnailView.slot(for:)` maps `copy/save/edit` to their strip buttons and everything else to `.more` (the ⋯ button).
- Copy Text, Copy for AI and Copy as Markdown are offered only when `kind == .screenshot`.
- **Editor:** `EditorManager(clipboard:habits:)`; the controller has `onCopyForAI`, `onOpenSource`, `onAction` and `saveToFolder` hooks. `validateMenuItem` greys out Open Source without a main source, and greys out Save As… and Copy as Markdown for a collection's image.
- `SourceLauncher.open(source)` turns `SourceOpener.action` into the `SourceWorkspace` calls (`SystemWorkspace` in the app, a fake in tests).

### 2.10 Browser permission status

```swift
var target = AEAddressDesc()
let id = Array(bundleID.utf8)
AECreateDesc(DescType(typeApplicationBundleID), id, id.count, &target)
let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
// noErr → allowed; errAEEventNotPermitted (-1743) → notAllowed; anything else (e.g. -600, the app isn't running) → notAsked
```
- With `askUserIfNeeded: false`, it never prompts.
- **A browser that isn't running can't answer,** so it counts as "Not asked". Allow then launches it and macOS asks if it needs to.
- Installed browsers are found with `NSWorkspace.urlForApplication(withBundleIdentifier:)`. All of this runs off the main thread, **only when the Settings window shows** (`f490df7`).

### 2.11 macOS 26 minimum

- `Package.swift`: `platforms: [.macOS(.v26)]`, with swift-tools-version 6.2, the lowest that knows `.v26`.
- `Resources/Info.plist`: `LSMinimumSystemVersion` is `26.0`.
- Redundant `#available` checks were removed. Nothing in M7 needs a 26-only API. The bump is for the user's own machine, and later milestones use it (SpeechTranscriber is planned for M13).

---

## 3. Gotchas and bugs we hit

| Symptom | Root cause | Fix | Commit |
|---|---|---|---|
| A hung Arc held up Chrome's URL lookups for minutes | Every script shares one serial queue, and an Apple Event's default timeout is about 2 minutes | `with timeout of 2 seconds` inside the script. (Setup's Allow probe has no timeout: it must outlast the permission prompt.) | `7a9f30e` |
| The full test suite starved the scroll tests after the Setup rows were added | Every `SettingsModel` init ran the browser lookup (LaunchServices + Apple Events) | Look up only when the Settings window shows; a unit test pins "no lookup at init" | `f490df7` (plan Task 19/B10) |
| A reopened capture (Open Last Capture, editor) showed no chip | The editor used the caller's item instead of the record stored on the file | `item.withStoredProvenance()` in the editor's init | `0e58d59` (plan Task 25/C6) |
| ⌘S and Save As… in the editor lost the record | `EditorExporter` writes with `.atomic`, which replaces the file and drops its xattrs | `keepProvenance(on:)` after every exporter write (§2.7) | `b958ad4` |
| Trimmed copies and GIFs had no source | New files written from a capture start with no xattrs | `ProvenanceStore.copy` after the trimmer and the GIF encoder | `4769bf7` |
| The first browser capture has no URL | macOS's Automation prompt outlasts the 1 s budget, and the capture never waits | Accepted, and documented in the checklist | `dea0226` |
| The normal copy couldn't carry the file URL | The copy happened before the file was written | `OutputRouter.deliver` writes first, then copies (`writeImage(png:fileURL:)`); if the write fails it still copies the image without a URL | `5be74bf` |
| Copying a big capture was slow | TIFF was produced eagerly with the PNG | PNG only, plus TIFF through a lazy provider | `2adb4dd` |
| Window titles were missing in the ranking | `WindowInfo` had no title field | `WindowInfo.title` from `kCGWindowName` (needs Screen Recording) | `3d484de` |
| A parallel test run flaked on main-queue deliveries | Main-actor tests saturate the main thread | Waits of up to 10 s for main-queue delivery in tests | memory note, `aa53e85` |

**Process lesson (plan appendix):** M7 was drafted by three parallel drafters in scratch worktrees, then replayed. Two integration bugs appeared only when parts B and C were merged (the Settings lookup at init, and the editor not reading the stored record). Both were caught by running the merged tree's full suite repeatedly.

---

## 4. Known open issues (from `docs/backlog.md`)

- **A late record can be lost** when the editor is open but the thumbnail is gone (closed within the second, or opened through Open Last Capture). `CaptureCoordinator.attach`'s fallback never tells the editors, so the next ⌘S drops the xattr. Fix: call `quickAccess.onItemChanged?(current)` there, or have `keepProvenance` fall back to `ProvenanceStore.read(from:)`.
- `EditorWindowController.updateItem` sets `viewModel.provenance = newItem.provenance`. It should use `item.provenance`, which keeps the known record. No caller sends an item without one today.
- **Open Source's window raise** (`SystemWorkspace.raiseWindow`) runs AX calls on the main thread with no messaging timeout. A hung app can freeze Bugeye for about 6 s. Set `AXUIElementSetMessagingTimeout(app, 0.5)`.
- **`SourceChip` looks up the app icon through LaunchServices on every render.** Compute it once in `init`.
- **The editor's drag-handle file** (`EditorExporter.dragFile`) carries no record. It needs one `ProvenanceStore.write` after it.
- **`ActionHabitsStore` keys habits by `bundleID ?? appName`.** The spec said bundle ID only; a missing bundle ID falls back to the name. The keys also include the capture kind (`"<app>|<kind>"`), so recordings and GIFs learn separately.
- **Search interplay (M10):** a move or new sources reuse an index record only when the image reads now. An unreadable file is indexed by its sources only.

---

## 5. Do it better next time

**Design**
- **One "capture file writer" that owns every write.** Make one function, `CaptureFiles.write(data, to:, carrying: [xattrs])`, the only way Bugeye writes a capture file. It writes atomically, then re-applies every Bugeye xattr (provenance, "Where from", the snapshot, the capture ID) from one in-memory record. M7, M9 and M10 each had to find and patch every write path by hand (§2.7), and one path (drag-out) was still missed.
- **Keep the record in memory as the truth, and treat the xattr as a cache.** Attaching a late record should go through one store keyed by the capture ID, which every view (Quick Access, the editor, the indexer) observes. That removes the "thumbnail gone, editor open" loss and the `updateItem` bug.
- **Give each lookup its own budget and cancel it.** `within` leaves the slow work running. Use structured cancellation (`withThrowingTaskGroup` + a deadline) where the API allows it, and set `AXUIElementSetMessagingTimeout` on **every** AX element, including in `SourceLauncher`.
- **Retry the URL once after the first-time Automation prompt.** The first capture from a browser could get its URL later, by re-running the lookup when `AEDeterminePermissionToAutomateTarget` turns `noErr` and patching the record, instead of accepting "no URL".
- **Match browser windows by more than the title.** For example, also compare the window's bounds through AppleScript (`bounds of w`) when titles collide or differ (PDF tabs).
- **Plan for the hardened runtime.** If the rebuild is notarised or uses the hardened runtime, add the `com.apple.security.automation.apple-events` entitlement, or every AppleScript silently fails.
- **Cache icons by bundle ID.**

**Portable core vs macOS shell** (see `13-rebuild-strategy-agentic-ci-and-claude.md`):

| Portable core (Linux-testable, no AppKit) | macOS shell (adapters behind ports) |
|---|---|
| `CaptureSource`, `CaptureProvenance` (JSON, versioning), with a plain `Rect` instead of `CGRect` | `CGWindowListCopyWindowInfo` → `[WindowInfo]` (a `WindowLister` port) |
| `ProvenanceRanker` (pure grid maths) | `NSRunningApplication` bundle IDs; the `BrowserURLReader` port (NSAppleScript, a serial queue, the 2 s script timeout); the `AXReader` port for `AXDocument` |
| The collector's orchestration: concurrency, budgets, "first result wins", over the ports with fakes | `FileMetadataStore` port: `setxattr`/`getxattr`, the binary-plist `kMDItemWhereFroms` (encoding the plist itself is portable with `PropertyListSerialization`) |
| `SourceLabel`, `MarkdownLink`, `ContextPack` (pure text) | `ClipboardWriter` port: `NSPasteboardItem`, lazy TIFF/HTML providers, file URL |
| `SourceOpener.action` routing and its notices | `SourceWorkspace` port: NSWorkspace open/activate, the AX raise |
| `ActionHabits` and a `HabitsStore` port (UserDefaults on macOS; in memory on Linux) | `AEDeterminePermissionToAutomateTarget`, the Settings deep link |
| A "capture file writer" policy (which records to re-apply after which write) as a pure function, tested with a fake `FileMetadataStore` | The real atomic write plus xattrs, with a macOS-tier test that asserts every write path keeps every attribute |
| The Quick Access view model: chip label, ring slot, ★ titles, which ⋯ items show per kind | SwiftUI thumbnail and editor chip views |

**Claude API features (opt-in, redacted):**
- **Copy for AI stays a local clipboard action.** The block format (`Source:` / `URL:` / `File:` / `Captured:` / fenced `Text:`) is a good prompt preamble. Reuse `ContextPack` to build the text part of any API request.
- **Run the sensitive-data redaction** (M8 sweep rules) on the `Text:` part and the URL query string before anything leaves the machine.
- **Keep OCR local.**

**Tests to keep**
- Ranker cases: one window; two side by side; occlusion; a sliver under 2 %; own and desktop windows excluded; ties go to the frontmost.
- An xattr round trip on a temp file, including `kMDItemWhereFroms` as a plist array and its removal.
- One test per write path that the xattrs survive. ⌘S over an atomic write is the important one.
- Lazy providers stay idle after a write.
- `ContextPack` with a backtick run longer than 3.
- "No OS lookup at init" for every model that can query Apple Events, LaunchServices or AX.
- The manual paste matrix: Mail, Notes, Slack (one upload), Finder, Obsidian, Gmail/GitHub, a terminal, Claude Code Ctrl+V then ⌘V.
