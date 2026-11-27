# 09: Search, Spotlight, Find Similar and Duplicates (M10)

M10 indexes every capture on this Mac by its text, its sources (M7) and its look. The index serves four features: the Find Capture palette (⇧⌘8), Spotlight, Find Similar and the Duplicates cleanup window. M11 later added collections (`.bugeye` packages) to the same index (see `10-collections-and-guide-recorder.md`).

Sources: spec `docs/superpowers/specs/2026-10-26-search-design.md`, plan `docs/superpowers/plans/2026-10-26-m10-search.md` (its appendix holds the drafters' rulings and the threshold measurement), checklist `docs/manual-checklist-m10-search.md` (all 30 tests passed by the user), merge `88267a1`.

Ground rules the user set:
- It is a **search index, not a capture history**. The palette lists nothing until something is typed. A browsable history UI was rejected scope.
- Everything stays on the Mac. No upload, no semantic/AI search, no Vision classifier labels as chips.
- Recordings and GIFs are indexed by source, date and size only (no text from frames).
- Bugeye never scans folders other than its save folder.

---

## 1. What it does

### 1.1 What gets indexed

| Capture | When | What |
|---|---|---|
| Screenshot (area, window, full screen, scrolling) | after delivery, after the sensitive-data sweep has read it; again after every editor ⌘S | text, word boxes, sources, feature print, pixel hash, pixel size |
| Recording (`.mp4`) | when delivered (also a Trim copy) | kind, date, size (video track natural size), sources |
| GIF | when delivered (GIF export) | kind, date, pixel size, sources |
| Collection (M11 `.bugeye`) | after each save | title + text blocks + OCR of each image; sources of the first image block that has one |
| Capture Text (⇧⌘7) | never | it saves no file |
| Quick Access Save As… copy | when saved | indexed as a **new** capture with a **new ID** |
| Editor Save As… copy | never (backlog) | the launch pass picks it up only if it lands in the save folder's top level |
| Temp captures (auto-save off) | like the rest | the 24 h purge removes the files; the next launch pass drops the records |

Indexing never delays delivery, the thumbnail, the clipboard or the save.

### 1.2 Find Capture palette

- **Open:** ⇧⌘8 (Carbon hotkey, `HotkeyManager.Action.findCapture = 7`, `kVK_ANSI_8`, `cmdKey | shiftKey`), or the menu bar item **Find Capture…** (shown with ⇧⌘8, placed right after "Open Last Capture", followed by **Duplicates…**). ⇧⌘8 works in every recording phase (it captures nothing). A second ⇧⌘8 closes it.
- **Window:** night-chrome floating `NSPanel`, 720 × 520 pt, centred on the visible frame of the screen under the mouse. Non-activating: it takes the keyboard without bringing Bugeye forward. Esc or losing key status (a click outside) closes it.
- **Before typing:** only the hint "Type to search your captures' text, apps and sites".
- **Other messages:** "No captures match" (also Find Similar with no neighbours); "Search is off in Settings" (index disabled or not wired).
- **Chips** (do nothing until something is typed):
  - App chips: the main app (`apps.first`) of the current results, at most 8, most results first, ties in first-shown order. Counted over the results **without** the app chip, so picking one keeps the others visible to switch to.
  - Kind: **Screenshots**, **Recordings** (includes GIFs), **Collections** (M11).
  - Date: **Today**, **This week**, **This month** (`Calendar.current` start of day / week / month).
- **Results:** a grid, 3 columns, cells 212 × 132 pt, at most 60 results. Each cell:
  - the thumbnail (ImageIO, ≤ 400 px long side; a recording's first frame; a collection's first image plus a `square.stack.fill` glyph bottom-left);
  - the matched words' boxes outlined in the accent (yellow) colour;
  - the first text line that matches, matched tokens bold; if the match is only in a source, that source line, dimmed;
  - a caption "neo4j.com · Today 14:02": the first URL's host without `www.`, else the main app; then the date.
- **Dates** (`en_US_POSIX`, 24 h): "Today 14:02"; "Mon 13:20" within the last 6 days; "12 Oct" this year; "12 Oct 2025" another year.
- **Keys:**

| Key | Action |
|---|---|
| ↑ ↓ | move the selection by a row (always) |
| ← → | move by one cell, only while there are results (else they move the caret) |
| Return | open (screenshot → editor; recording → player with Trim; GIF → default app; collection → its window). Closes the palette |
| ⌘C | copy the image (JPEG/HEIC converted to PNG); a recording copies its file reference. If text is selected in the field, ⌘C copies the text instead |
| ⌘R | Reveal in Finder |
| ⌘L | Find Similar (keeps the palette open) |
| ⌘[ | back from Find Similar |
| Esc | back from Find Similar, else close |
| double-click | open |

- Each cell has a ⋯ menu: Open, Copy, Reveal in Finder, Find Similar (disabled unless the record is a screenshot with a feature print).
- A result whose file is gone: it leaves the grid and the index; notification title "That capture is no longer on this Mac", body = file name. The palette stays open.
- The footer shows "↩ Open  ⌘C Copy  ⌘R Reveal  ⌘L Similar" and a **Duplicates…** button.

### 1.3 Find Similar

- From the palette (⌘L or ⋯), the editor's File → Find Similar (after Open Source), and Quick Access ⋯ → Find Similar.
- Screenshots only. Disabled for recordings, GIFs, collections and for a capture not indexed yet (no record or no feature print). Quick Access's item enables itself once the capture is indexed.
- The palette shows "Similar to <file name>" with a back chevron: up to 20 screenshots, closest first, each within distance 0.30. Chips are hidden; no highlight boxes or bold.
- If the palette is already open, it switches to Similar (Esc returns to the search with the same words and chips). If it opened for Find Similar (editor, Quick Access), Esc/⌘[ closes it.
- Find Similar from the editor uses the indexed file, not unsaved edits.

### 1.4 Duplicates

- Menu bar **Duplicates…** or the palette footer button. A normal titled night window, resizable, min 560 × 360, frame autosaved as `BugeyeDuplicates`. It regroups every time it is shown.
- Groups, newest group first. Each group's captures side by side (tiles 168 × 104 pt) with "Today 14:02 · 1920 × 1050". The newest is marked **Keep** (yellow outline). Clicking another tile moves Keep (one per group).
- **Move Others to Trash** per group; **Clean Up All** in the header.
- One confirmation per click: "Move 14 captures to the Trash? You can restore them from the Trash." (singular "capture" for 1). Buttons **Move to Trash** / **Cancel**.
- Trashed files: records and Spotlight items removed; a thumbnail still in Quick Access is dismissed. A file already gone is dropped from the index without asking. A file that fails to trash stays in its group and one notification says "Delete failed" with the error.
- "No duplicates found" when empty; a spinner while grouping.

### 1.5 Spotlight

- Each record is donated to `CSSearchableIndex.default()`. ⌘Space finds captures by file name, text, app keywords.
- Picking a result opens it like Return in the palette (follows moved files).
- If Spotlight refuses, Settings → Search shows "Spotlight isn't accepting Bugeye's captures". The palette is unaffected. With the self-signed dev identity Spotlight **did** accept donations and continuation worked (checklist A3–A4, smoke test).

### 1.6 Settings → Search

| Setting | Key (`UserDefaults`) | Default | Notes |
|---|---|---|---|
| Index captures for search | `search.indexEnabled` | on | off deletes the index and Bugeye's Spotlight domain; palette says "Search is off in Settings"; back on runs the launch pass |
| Add captures to Spotlight | `search.spotlight` | on | off deletes the domain; back on re-donates every record (no re-reading). Greyed out while indexing is off |
| Duplicates: how close | `search.duplicatesThreshold` (Double) | 0.03 | slider "Identical only" (0) … "Loosely similar" (0.12); out-of-range stored values are clamped on load |
| Rebuild Index | — | — | deletes everything, then runs the launch pass now |

The section also shows "Indexed: N screenshots, M recordings" (singular when 1; recordings include GIFs and, as coded, collections) and the Spotlight failure line.

---

## 2. How it's built

### 2.1 Code map

| Target | File | Role |
|---|---|---|
| CSCore | `CaptureRecord.swift` | `CaptureRecord`, `IndexedWord`, `setSources`, `captureItem(isSaved:)`, `textAndWords(_:map:)` |
| CSCore | `CaptureKind.swift` | `screenshot / recording / gif / collection` (`String` raw values, `CaseIterable`) |
| CSCore | `SearchQuery.swift` | `SearchQuery`, `SearchFilter`, `KindChip`, `DateChip` |
| CSCore | `SearchHighlight.swift` | `boxes`, `snippet` (`Snippet`) |
| CSCore | `Similarity.swift` | `SimilarityThresholds`, `SimilarCaptures.nearest`, `DuplicateGroups.groups` |
| CSCore | `SearchSettings.swift` | `SearchSettings` in `AppSettings.search` |
| CSCapture | `FeaturePrinter.swift` | `FeaturePrinting`, `FeaturePrinter` (+ `DecodedPrints` cache), `PixelHash` |
| App `Search/` | `CaptureIndex.swift`, `CaptureIndex+Search.swift` | SQLite store and FTS5 search |
| App `Search/` | `CaptureIdentity.swift` | xattr ID, bookmark, `locate` |
| App `Search/` | `Indexer.swift` | queue, reading, launch pass, settings changes |
| App `Search/` | `SpotlightDonor.swift` | `SpotlightDonating`, `SpotlightDonor` |
| App `Search/` | `CaptureSearching.swift` | protocol the palette and Duplicates read (`CaptureIndex` conforms) |
| App `Search/` | `FindCaptureModel.swift`, `FindCapturePanel.swift`, `FindCaptureText.swift`, `ThumbnailCache.swift` | the palette |
| App `Search/` | `DuplicatesModel.swift`, `DuplicatesWindowController.swift` | Duplicates |
| App | `AppDelegate.swift` | `startSearchIndex`, `openCapture`, `toggleFindCapture`, `findSimilar`, `showDuplicates`, Spotlight continuation |
| App | `CaptureCoordinator.swift` | hands delivered screenshots to the indexer after the sweep |

### 2.2 `CaptureRecord` (CSCore, pure, `Codable`)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | the capture's ID = its `CaptureItem.id` (§2.4) |
| `path` | String | where the file was last seen (`path(percentEncoded: false)`) |
| `bookmark` | Data? | `url.bookmarkData(options: [])`; nil if it couldn't be made |
| `kind` | CaptureKind | |
| `createdAt` | Date | the item's date; for backfilled files the file creation date |
| `pixelSize` | CGSize | |
| `pixelsPerPoint` | CGFloat | default 1 (backfilled PNGs don't record their scale) |
| `apps`, `titles`, `urls`, `paths` | [String] | from the M7 provenance, de-duplicated, blanks dropped, order kept |
| `text` | String | screenshots: what Copy Text gives |
| `words` | [IndexedWord] | text + box in image pixels, top-left origin, reading order |
| `featurePrint` | Data? | stored in its own SQLite column, not in the JSON |
| `pixelHash` | String? | lowercase hex SHA-256 |
| `indexedAt` | Date | |
| `version` | Int | `CaptureRecord.currentVersion = 1`; older records are re-read by the launch pass |

`textAndWords(snapshot, map:)`:
- `text` = `ExactText.merge(snapshot, map:).text` (exactly what Copy Text reads, M9).
- Exact (AX) lines kept by the merge (`ExactText.agreeing`) are split into words with `TextLine.wordRanges`; each word gets a proportional box: line width / character count per character, counting leading spaces (as M9's crop does).
- OCR words are kept unless their centre lies inside a covered region. An OCR line with no words counts as one word (fakes only).
- Words sorted by `(minY, minX)`.

### 2.3 The SQLite index (`CaptureIndex`, app)

- **Path:** `~/Library/Application Support/Bugeye/index.sqlite` (`FileManager.urls(for: .applicationSupportDirectory)` + `Bugeye/index.sqlite`).
- **Linking without packages:** `import SQLite3` in Swift. The macOS SDK's `SQLite3` module map autolinks `libsqlite3`, so `Package.swift` has no `linkerSettings` and no dependency. The system SQLite has FTS5 and JSON1 compiled in. This works with Command Line Tools only.
- **Schema:**

```sql
CREATE TABLE IF NOT EXISTS captures(
    rowid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, path TEXT NOT NULL, kind TEXT NOT NULL,
    created REAL NOT NULL, apps TEXT NOT NULL, record BLOB NOT NULL, print BLOB, hash TEXT);
CREATE INDEX IF NOT EXISTS captures_path ON captures(path);
CREATE VIRTUAL TABLE IF NOT EXISTS captures_fts USING fts5(
    text, apps, titles, urls, paths, tokenize = 'unicode61 remove_diacritics 2');
```

- `record` = the whole `CaptureRecord` as JSON **with `featurePrint` set to nil**; the print goes in `print`. `apps` = JSON array of strings (used by `json_each` for the app chip). `created` = seconds since 1970. `kind` = raw value.
- FTS row: `rowid` = the `captures.rowid`; `text` and each source list joined with `\n`.
- **Upsert:** `BEGIN` → delete FTS row + captures row for the id → insert captures → `sqlite3_last_insert_rowid` → insert FTS row → `COMMIT`.
- **Search SQL** (`CaptureIndex+Search.swift`):

```sql
SELECT c.record, c.print FROM captures_fts JOIN captures c ON c.rowid = captures_fts.rowid
WHERE captures_fts MATCH ?
  [AND EXISTS (SELECT 1 FROM json_each(c.apps) WHERE json_each.value = ?)]   -- app chip
  [AND c.kind = ? | AND c.kind IN (?, ?)]                                    -- kind chip
  [AND c.created >= ?]                                                        -- date chip
ORDER BY bm25(captures_fts), c.created DESC LIMIT ?                          -- 60
```

- Other reads: `record(id:)`, `record(path:)`, `allRecords()` (newest first), `counts()`, `allPrints()` (screenshots with a print, newest first), `duplicateItems()` (screenshots only: id, created, hash, print), `deleteAll()`.
- **Threading:** opened with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX`. Every statement runs inside `queue.sync` on one serial queue (`dev.msenechal.bugeye.index`), so any thread may call it. Row JSON is decoded **after** the queue is released (see §3).
- **Binding text/blobs:** Swift does not import the `SQLITE_TRANSIENT` macro. Use `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` so SQLite copies the bytes.
- **Corruption:** at open, `sqlite3_exec(schema)` then `PRAGMA quick_check` must return `ok`. If open fails or any statement returns `SQLITE_CORRUPT` / `SQLITE_NOTADB`, the file and its `-wal`, `-shm`, `-journal` siblings are deleted and an empty database is created; logged under subsystem `dev.msenechal.bugeye`, category `search`. A mid-session recreate stays empty until the next launch pass or Rebuild Index (backlog).

### 2.4 Identity (`CaptureIdentity`, app)

- **ID:** the UUID string in the extended attribute `dev.msenechal.bugeye.id`, read/written with `getxattr` / `setxattr` (Darwin) through `url.withUnsafeFileSystemRepresentation`. A file system that refuses xattrs leaves the file without an ID; it is then found by path only.
- **The record's ID is the capture's `CaptureItem.id`.** `Indexer.add` writes the item's ID onto a file that has none, at once (not when it's read). If the file already has an ID, the file's ID wins. The editor's and Quick Access's Find Similar then look the capture up by the item they hold.
- **Rewrites keep the ID:** atomic writes drop xattrs. The editor's ⌘S reads the ID before `EditorExporter.save` and writes it back after (with the M7 provenance and M9 snapshot xattrs). The editor's "file is gone → Save As…" assigns the editor's item ID to the new file.
- **Copies get a new ID:** Quick Access Save As… (`QuickAccessController.saveCopy(of:to:)`) copies the file, copies provenance and snapshot xattrs, then assigns a **fresh** UUID and returns it; `onSavedCopy` indexes the copy under that ID. The launch pass gives a new ID to a Finder copy that carries an indexed capture's ID.
- **Bookmark:** `url.bookmarkData(options: [])`; nil when impossible (then the record follows its path only; a moved file's record is dropped).
- **`locate(record) -> URL?`:**
  1. The file at `record.path` if it exists, its ID matches (or it has none), and it isn't in the Trash.
  2. Else resolve the bookmark with `[.withoutUI, .withoutMounting]`; accept it if the file exists, its xattr ID equals the record's ID, and it isn't in the Trash.
  3. Else nil: the capture is gone.
- **Trash rule:** bookmarks follow a file into the Trash. A path containing a `.Trash` or `.Trashes` component counts as gone.

### 2.5 The indexer (`Indexer`, app, `@MainActor`)

**Inputs** (wired in `AppDelegate` and `CaptureCoordinator`):

| Call | From | Effect |
|---|---|---|
| `add(item, map:, afterSweep:)` | delivery (`CaptureCoordinator`), editor ⌘S, recordings/GIFs (`deliverMedia`), Quick Access Save As copy, collection saves | queue a full read; writes the ID xattr now |
| `sweepRead(id, map:)` | `SensitiveSweep.onRead` | releases a job held for the sweep, with the sweep's `TextMap` |
| `moved(item)` | Quick Access Save (move into folder), late provenance (`CaptureCoordinator.attach`), `openable` | re-link path and sources without re-reading the image |
| `removed(fileURL)` | Quick Access Delete, Duplicates, palette gone-file | delete record (looked up **by path**) and Spotlight item |
| `openable(id, tempDirectory:)` | Spotlight continuation, palette Return | locate the file, re-link if moved, else remove and return nil |
| `armLaunchPass(saveFolder:delay: 10 s)` | launch | launch pass after the first capture or 10 s |
| `rebuild`, `settingsChanged` | Settings → Search | |

**Delivery order for a screenshot** (`CaptureCoordinator`): thumbnail → clipboard/save (already done by the router) → provenance/snapshot tasks → `indexer.add(item, afterSweep: sweep != nil)` → `sweep.scan(...)`; if the scan was not queued, `indexer.sweepRead(id, map: nil)` releases the job immediately. Faces-only, failed or dropped scans send nil.

**Queue:**
- `Job` = item, optional `TextMap`, rank `(live: Int, order: Double)`, `waitsForSweep`, optional `reuse` record.
- Rank: deliveries and saves have `live = 1` and a growing sequence number; launch-pass jobs `live = 0` and `createdAt` seconds. The next job is the max rank among jobs not waiting for the sweep: **live before launch-pass, newest first within each**.
- A capture already waiting is replaced by its latest state (`enqueue` removes the old job).
- One job runs at a time in `Task.detached(priority: .utility)`. `current` tracks the running job; a `moved` or `removed` meanwhile is recorded and applied in `finished`.

**Reading one capture** (`Indexer.record(for:map:reuse:reader:printer:)`, nonisolated static):
1. File must exist. ID: the file's xattr, else the item's (written now).
2. Record with path, bookmark, kind, date, scale; sources from `item.provenance ?? ProvenanceStore.read(from: url)`.
3. By kind:
   - **Screenshot:** decode the first image with `CGImageSourceCreateImageAtIndex`. Unreadable → record by sources only. With `reuse`: copy text, words, print and hash from the old record (only path/sources change). Else: `TextMap` = the sweep's map, or `reader.readMap(image, pixelsPerPoint:)`; text and words = `CaptureRecord.textAndWords(UISnapshotStore.read(from: url), map:)`; `featurePrint`; `PixelHash.sha256`. Spotlight thumbnail = PNG ≤ 256 px long side.
   - **GIF:** pixel size from the first frame.
   - **Recording:** `AVURLAsset.loadTracks(withMediaType: .video).first?.load(.naturalSize)`, absolute values.
   - **Collection:** `CollectionPackage.readAny`; text = title + each text block (`InlineBold.plain`) + OCR text of each image (`readMap` at the block's `pixelsPerPoint`, `textAndWords(nil, map:)`); pixel size and thumbnail from the first readable image; sources from the first image block with a `source`. No words, print or hash.
4. `index.upsert`, then `spotlight.donate` (only while the Spotlight setting is on). A donation error marks `spotlightFailed` once and calls `onSpotlightFailed`.

`onChange` fires after each job; the app refreshes the Settings counts and re-renders Quick Access thumbnails (so ⋯ → Find Similar enables).

**Launch pass** (`launchPlan` runs detached at utility priority, then the main actor applies it):
1. **Gone:** every record `locate` can't find → removed (and from Spotlight).
2. **Re-linked:** a record found elsewhere → `reuse` job with the new path (no re-read).
3. **Old version:** `record.version < currentVersion` → full re-read.
4. **Backfill:** the save folder's **top level only**, hidden names skipped, extensions `png`, `jpg`, `heic` → screenshot, `mp4`, `mov` → recording, `gif` → gif (not `jpeg`: backlog). A file without a record is read; ID from its xattr, else new; a file carrying the ID of another known record (a Finder copy) gets a new ID written. `createdAt` = file creation date.
5. **Collections** (M11): `<save folder>/Collections/*.bugeye`, top level of that folder only, same rules, kind `.collection`.
6. Jobs already waiting or running keep their place (and the sweep's map). Paths are compared after `resolvingSymlinksInPath()` (`/var` vs `/private/var` in tests).

The pass is armed at launch and runs once: after the session's first `add`, or after 10 s, whichever comes first. The 24 h temp purge (`TempJanitor.purge`) runs at launch before the index exists; the pass then drops the purged records as gone.

**Settings changes** (`settingsChanged(from:to:saveFolder:)`):
- Index off: clear the queue, mark the running job removed, `deleteAll`, Spotlight `removeAll` (even though Spotlight may be "on").
- Index on: launch pass.
- Spotlight off: delete the domain. On: every record re-queued as a `reuse` job (records decoded off the main actor), so each is donated again without OCR.

### 2.6 Query, matching and highlighting (CSCore)

- `SearchQuery(typed)`: lowercase, split on whitespace, drop words with no letter or digit.
- **Every word is a prefix** (not only the last). `ftsMatch` = each word double-quoted, inner `"` doubled, followed by `*`, joined by spaces (implicit AND): `"cyph"* "err"*`. Quoting turns any typed FTS5 syntax (`OR`, `NEAR`, `-`, `:`) into plain tokens.
- A word like `foo-bar` stays one quoted phrase; FTS5 tokenizes it as `foo` then `bar*`.
- `SearchQuery.matches(record)` mirrors FTS5 in Swift for tests and highlights: fold case and diacritics (`folding([.caseInsensitive, .diacriticInsensitive])`), tokens = runs of letters/digits; a word's tokens must appear consecutively in one field, the last token as a prefix. **The FTS tokenizer must stay `unicode61 remove_diacritics 2`** or the Swift mirror, the bold snippets and the yellow boxes disagree with what SQL returns.
- `SearchHighlight.boxes` = boxes of `record.words` whose text matches a query word. `snippet` = the first trimmed text line with a match (bold ranges are whole tokens, so a URL bolds only `neo4j` in `https://neo4j.com/docs`), else the first matching source in order apps, titles, URLs, paths (`isSource = true`).
- `ThumbnailGeometry.outlines` maps word boxes (image pixels) onto the aspect-fit thumbnail; boxes drawn at least 4 × 4 pt.

### 2.7 Feature prints and pixel hash (CSCapture)

- **Feature print:** the Swift Vision API: `try await GenerateImageFeaturePrintRequest().perform(on: cgImage)` returns a `FeaturePrintObservation`, which is `Codable`. Stored as a **binary property list** (`PropertyListEncoder`, `.binary`), about 3.4 KB. Not `NSKeyedArchiver` (that is for the old `VNFeaturePrintObservation`). This API compiles under Command Line Tools.
- **Distance:** `observation.distance(to:)`. Per the drafters' measurement it behaves as the squared Euclidean distance of the 768-float vectors. Range seen 0 … 1.55.
- **Decoded-print cache:** decoding a print costs about 24 µs, a distance about 0.14 µs, so `DecodedPrints` keeps decoded observations in an `NSCache<NSData, Entry>` keyed by the archive bytes (failures cached too). The app shares **one** `FeaturePrinter` between the indexer, the palette and Duplicates, so the cache serves all. 2,000 screenshots (2 M pairs) group in about 2 s.
- **Pixel hash:** SHA-256 (CryptoKit) over the width and height (two `UInt64`) followed by RGBA8 sRGB premultiplied pixels, drawn **2,048 rows at a time** with `.copy` blend and no interpolation, so a 3,840 × 30,000 scrolling capture never allocates its whole bitmap. Lowercase hex. Same pixels in a PNG and a re-encoded copy give the same hash.

### 2.8 Find Similar and Duplicates (CSCore + app)

- `SimilarCaptures.nearest(to:prints:limit: 20, within: 0.30, distance:)`: every other print within the limit, sorted by distance, ties in input order. Runs on the main thread over `allPrints()` (fine at hundreds; backlog for thousands).
- `DuplicateGroups.groups(items, threshold:, distance:)`: union-find with path halving. Same `hash` → joined. Then every pair of printed items whose distance ≤ threshold → joined (single linkage, transitive). Groups of ≥ 2; each group newest first; groups ordered by their newest capture. Recordings never enter (`duplicateItems()` returns screenshots only).
- `DuplicatesModel.load()` runs the grouping in `Task.detached(priority: .userInitiated)`; clears old groups first; the Keep mark starts on the newest.
- Cleanup (`clean`): only groups whose kept capture still `locate`s; nothing while loading; one `confirm`; `FileManager.trashItem` per file; gone files only dropped from the index; `onRemoved(urls)` → `Indexer.removed`; `dismissQuickAccess(url)`.

**Thresholds** (`SimilarityThresholds`, measured on the user's own `~/Pictures/Bugeye`, read only: 62 PNGs, 1,891 pairs, median 0.565, p10 0.289):

| Pair type | Distance seen |
|---|---|
| Same-window retakes | 0 – 0.011 |
| Window retakes a few pixels different in size | 0.053 – 0.098 |
| Different screens of the same app (same chrome) | as low as 0.049 |
| Same app, clearly different content | 0.16 – 0.27 |

| Constant | Value | Why |
|---|---|---|
| `duplicatesDefault` | 0.03 | groups the 0–0.011 retakes, never two different screens (closest different pair 0.049). Duplicates trashes files, so a missed retake is the cheaper error |
| `looselySimilar` (slider max) | 0.12 | every measured retake groups; same-app screens join too |
| `identicalOnly` (slider min) | 0 | same pixels, or a print at distance 0 |
| `similarLimit` (Find Similar) | 0.30 | about the closest 10 % of pairs; at most 20 shown anyway |

There is **no clean gap** between "window retake at another size" and "different screen of one app". Window retakes need the slider moved up.

### 2.9 Spotlight (`SpotlightDonor`)

- Domain `dev.msenechal.bugeye.captures`; `uniqueIdentifier` = the capture's UUID string.
- `CSSearchableItemAttributeSet(contentType:)`: `.image` / `.movie` / `.gif` / `.package` (collection).
- Attributes: `title` = file name; `textContent` = text (nil if empty); `contentDescription` = first two non-empty lines, else the sources joined with " · "; `keywords` = apps; `contentURL` = the file; `thumbnailData` = PNG ≤ 256 px (screenshots and collections; recordings rely on `contentURL`); `contentCreationDate` = `createdAt`.
- Calls: `indexSearchableItems`, `deleteSearchableItems(withIdentifiers:)`, `deleteSearchableItems(withDomainIdentifiers:)`, all `async throws`.
- Spotlight work runs in the background and only while its toggle is on, except the deletions that turning it (or indexing) off causes.
- **Continuation:** `Info.plist` has `NSUserActivityTypes = [com.apple.corespotlightitem]` (added as a harmless guarantee; may not be required on macOS). `AppDelegate.application(_:continue:restorationHandler:)` accepts `activityType == CSSearchableItemActionType` and reads `userInfo[CSSearchableItemActivityIdentifier]` as the UUID, then `openCapture(id)` → `indexer.openable` → `open(item)`. A gone file posts "That capture is no longer on this Mac" (empty body).
- `isSaved` of an opened item = the located file is not under the temp folder (compare after `resolvingSymlinksInPath()`).

### 2.10 Palette and window plumbing

- `FindCaptureModel` (ObservableObject) holds `text`, `filter`, `results`, `appChips`, `selected`, `mode` (`.search` / `.similar(UUID)`), `title`, pick-mode state. All app actions are injected closures (`open`, `reveal`, `clipboard`, `locate`, `notify`, `onRemoved`, `close`, `onPick`), so it is tested without AppKit.
- `FindCapturePanel`: `NSPanel` with `[.nonactivatingPanel, .borderless]`, `level = .floating`, `canBecomeKey = true`, `canBecomeMain = false`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`. `windowDidResignKey` closes it. Key handling: the `NSSearchField` delegate's `control(_:textView:doCommandBy:)` maps `moveUp/Down/Left/Right`, `insertNewline`, `cancelOperation`; `performKeyEquivalent` maps ⌘C/⌘R/⌘L/⌘[; `keyDown` handles arrows and Return when focus left the field.
- Thumbnails: `ThumbnailCache` with `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceThumbnailMaxPixelSize: 400`, `CreateThumbnailFromImageAlways`, `WithTransform`, `ShouldCacheImmediately`), built off the main thread, kept only while the panel is open. Recordings use `RecordingThumbnail.firstFrame`.
- Quick Access's ⋯ → Find Similar: SwiftUI builds the menu when the thumbnail renders, so the glue calls `quickAccess.refreshThumbnails()` on every index change; the editor's menu item validates when the menu opens.

---

## 3. Gotchas and bugs we hit

| Symptom | Root cause | Fix |
|---|---|---|
| Find Similar stayed greyed out for a fresh capture | The launch pass (or a backfill) could run between delivery and the indexer's read, find the new file without an ID, and give it a different UUID than the `CaptureItem`. The editor/Quick Access look records up by item ID | `Indexer.add` writes the item's ID xattr **immediately**, before queueing (`98336cc`) |
| Rebuild Index lost the capture being read; toggling indexing off/on mid-read dropped it; turning indexing off while the launch pass was planning still indexed files | No tracking of the in-flight job vs. the reset | `current` tracks the running job with `removed` / `movedTo`; rebuild keeps a fresh in-flight read; launch pass re-checks `indexEnabled` after planning and re-queues an in-flight job that was let go (`98336cc`) |
| Main thread stalled behind the launch pass | Records' JSON (with every word box) was decoded inside `queue.sync`; on a large index that takes seconds while the queue is held, and the main actor's reads waited | Collect raw rows inside the queue, decode after releasing it; Spotlight's refill decodes `allRecords()` in a detached task (`98336cc`) |
| Duplicates could act on stale groups, or trash the "others" of a group whose kept file was already gone | `load()` didn't clear old groups; `clean` didn't check the kept file | Clear groups at load start; skip cleanup while loading; skip groups whose Keep doesn't `locate` (`98336cc`) |
| Spec said "the last word matches as a prefix" but its example "cyph err" → "Cypher error" needs the first word as a prefix too | Spec contradiction | Ruling: every word is a prefix (plan Part A) |
| Highlights or Swift `matches` disagreed with SQL results | Different tokenization | Mirror `unicode61 remove_diacritics 2` exactly in `SearchQuery.tokens` (letter/digit runs, case + diacritic folding); comment in schema forbids changing the tokenizer |
| A trashed capture was still "found" | Bookmarks resolve into `~/.Trash` | Treat paths with `.Trash` / `.Trashes` components as gone |
| Atomic saves lost the capture's ID | Atomic writes replace the inode and drop xattrs | Read the ID before saving, write it back after (editor ⌘S, collection saves), same as the M7/M9 xattrs (`36034db`) |
| A Finder copy of an indexed capture shared its ID | `copyItem` copies xattrs | Backfill gives any file whose ID is already known a fresh ID; Quick Access Save As assigns a new ID explicitly |
| `swift test` paths didn't match | `/var/folders` vs `/private/var/folders` | Compare paths after `resolvingSymlinksInPath()` |
| Comparing thousands of prints was slow | Decoding the archived print dominated (100× a distance) | `NSCache` of decoded observations, one shared `FeaturePrinter` |
| `SQLITE_TRANSIENT` unavailable in Swift | C macro not imported | `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` |
| `make smoke` didn't run the Spotlight smoke test | Its filter only covered `CSCaptureTests|CSRecordingTests` (M11 widened it for its own tests only) | Run `CSC_INTEGRATION=1 swift test --filter realSpotlightTakesACaptureAndDropsIt` by hand |
| A synthetic smoke-test pair (window + 8 px red dot) measured 0.11 | Feature prints are sensitive to small local changes | Smoke test asserts only near < far, not the threshold |

Process notes:
- Parts A (pure), B (index/indexer) and C (palette/Duplicates) were drafted in parallel scratch worktrees; C talked to the index only through `CaptureSearching` and closures, so it built without B. Glue (Task 33) wired them. This "replay execution" worked well.
- The suite after M10: about 893 tests.

---

## 4. Known open issues (from `docs/backlog.md`)

Search (M10) notes:
- Palette searches and Find Similar distances run on the main thread. Fine at a few hundred captures; move off it past a few thousand.
- Window retakes at a slightly different size sit at 0.05–0.10 distance, the same as different screens of one app; they group only with the slider moved up.
- A snapshot (M9) that arrives after a capture was indexed doesn't trigger a re-read; that capture's index text is OCR-only until re-indexed (editor save or Rebuild Index).
- Editor Save As copies are not indexed.

M10 review minors:
- Removal looks records up **by path**: a capture moved and then trashed by Duplicates keeps its record and Spotlight item until the next launch, and a gone record's path can match a different capture now at that path. Pass IDs through `onRemoved` and remove by ID.
- A job already being read when Spotlight is turned off still donates its item after the removal; that one item lingers.
- A move or new sources reuse a record only when the image reads now: an unreadable file (iCloud-evicted, mid-write during backfill) is stored by sources only at the current version and never read again.
- Two Finder copies of a capture whose record is gone (or after Rebuild Index) get the same ID from the backfill; one is missing from results until the next launch.
- Launch costs: `PRAGMA quick_check` reads the whole database; the pass's gone deletes commit one at a time; `enqueue` is O(n²) on a first backfill of thousands of files; every indexed file re-renders every Quick Access thumbnail.
- Palette and Duplicates thumbnails read `record.path`, so a capture moved since indexing shows a blank tile until re-linked.
- The backfill skips `.jpeg`.
- Corruption found mid-session leaves the index empty until the next launch or Rebuild Index.

Also observed while writing this (not in the backlog): `CaptureIndex.counts()` counts every non-screenshot kind, collections included, as "recordings".

---

## 5. Do it better next time

1. **Remove by ID everywhere.** Make `onRemoved` carry UUIDs and key all removals on ID; keep the path index only for lookups by file. This closes two backlog items.
2. **One identity module for every xattr.** M7 provenance, M9 snapshot and the M10 ID all have to be copied back after atomic writes. Build a single `CaptureAttributes.preserve(around: write)` helper used by every writer (editor, Quick Access, collections) from day one.
3. **Store words compactly.** Keep `words` out of the JSON blob (a separate table or a binary column) so listing records never decodes thousands of word boxes. Keep `record` JSON small.
4. **Batch launch-pass writes.** One transaction for all gone deletes; replace `enqueue`'s linear de-dupe with a dictionary keyed by ID. Use `PRAGMA integrity_check` only after an error, not `quick_check` on every launch.
5. **Do searches and Find Similar off the main actor** from the start (the index is already thread-safe).
6. **Re-read text when the snapshot arrives late.** Either wait for the snapshot (it lands within about a second) before reading, or queue a cheap re-merge when it arrives (the `TextMap` could be cached).
7. **Thresholds:** keep the measurement script and table in the repo. Consider combining print distance with a size check (same pixel size ± a few px) to separate window retakes from same-app screens instead of one global threshold.
8. **Index editor Save As copies** through the same `onSavedCopy` path as Quick Access, with a new ID.
9. **Backfill extensions:** accept `jpeg`, `tif`/`tiff`, and match case-insensitively (already lowercased).
10. **Recreate mid-session → trigger the launch pass** via a callback from `CaptureIndex` instead of staying empty.
11. **Test the real tokenizer once:** the CSCore `SearchQuery` tests already run `ftsMatch` against an in-memory FTS5 table via `import SQLite3`. Keep that pattern: it is the only guard that the Swift mirror and SQLite agree.
12. **Widen `make smoke`** to include every app-target `CSC_INTEGRATION` test (Spotlight, AX) so they are not forgotten.

### Portable core vs macOS shell (rebuild on Linux, see `13-rebuild-strategy-agentic-ci-and-claude.md`)

Search is one of the most portable parts of Bugeye. Almost everything except the Apple services can run and be tested on Linux.

| Piece | Where | Notes |
|---|---|---|
| `CaptureRecord`, `IndexedWord`, `textAndWords`, `CaptureKind` | portable core | already pure; use Foundation geometry only |
| `SearchQuery`, `SearchFilter`, chips, `SearchHighlight`, snippets, date captions (`FindCaptureText`) | portable core | date formatting with a fixed `en_US_POSIX` locale works on Linux Foundation |
| `CaptureIndex` (SQLite + FTS5 + JSON1) behind a `CaptureIndexStore` port | portable core | system SQLite exists on Linux. On Linux `import SQLite3` is not available: use a small system-library target (`module CSQLite [system] { link "sqlite3" }` with `libsqlite3-dev`) on both platforms, or a thin wrapper chosen by `#if canImport(SQLite3)`. Check the Linux SQLite build has FTS5 and JSON1 enabled (Ubuntu's does). Test the **real** index, tokenizer and ranking on Linux |
| `Indexer` queue, ranking, launch-plan logic, settings-change logic | portable core (as an actor or state machine) | all file-system access through a `FileMetadataStore` port (xattr ID, bookmark resolve, directory listing, trash check) with a fake; bookmarks are macOS-only, so the port returns opaque `Data` |
| `DuplicateGroups`, `SimilarCaptures`, `SimilarityThresholds` | portable core | take prints as `[Float]` or opaque `Data` plus an injected distance |
| `PixelHash` | portable core over `PixelBuffer` | SHA-256: use `swift-crypto` (`import Crypto`) on Linux, CryptoKit on macOS, same API. Hash the RGBA8 bytes; the macOS shell must convert `CGImage` to the same premultiplied sRGB RGBA8 layout, or hashes differ between platforms |
| `FindCaptureModel`, `DuplicatesModel` (state, keys, pick mode, cleanup decisions) | portable core | inject `trash`, `confirm`, `open`, `clipboard` as ports |
| Feature prints (`GenerateImageFeaturePrintRequest`) | macOS shell, behind a `FeaturePrinting` port | fake on Linux (as `FakeFeaturePrinter` did: one-byte prints). Store prints as the 768 floats rather than a Vision plist so the core can compute distance itself and the cache is trivial |
| OCR `TextMap` source | macOS shell (`TextReader` port) | fake on Linux |
| `CaptureIdentity` xattr and bookmarks | macOS shell adapter of `FileMetadataStore` | Linux has `setxattr` (`user.` namespace) if real-file tests are wanted, but bookmarks aren't; keep the fake |
| `SpotlightDonor`, continuation (`CSSearchableItemActionType`) | macOS shell (`SpotlightDonor` port) | `FakeSpotlight` on Linux; real donation only in the self-hosted Mac smoke run |
| `FindCapturePanel`, `DuplicatesWindowController`, thumbnails (ImageIO) | macOS shell | render the core's view models only |

Claude (opt-in): the search index itself should never be sent. A possible later use is query expansion or natural-language search over the **local** index's text, but that's not a built or committed feature; don't add it without a brainstorm.
