# 07: Sensitive-data sweep and the word map (M8)

M8 added two features on one shared piece, the **word map** (`TextMap`): every recognised line and word of an image, with pixel boxes.
- **Find in screenshot (⌘F in the editor)** turns matches into highlights, boxes or blurs. Its UI is documented in `03-editor.md`; this file covers only the word map underneath it.
- **The sensitive-data sweep** checks every still screenshot in the background for secrets, credentials, token-like strings, card numbers, emails, phones/IPs and faces. It shows a "⚠ N possible" badge on the thumbnail, and the editor offers Blur all / Review / Ignore.

Sources: spec `docs/superpowers/specs/2026-10-22-find-and-sweep-design.md`, plan `docs/superpowers/plans/2026-10-22-m8-find-redact.md`, checklist `docs/manual-checklist-m8-find-redact.md`, merge `9fd1a60` (2026-10-23).

---

## 1. What it does

### 1.1 The rules the user set

- **Every still screenshot is swept in the background:** area, window, full screen (each display's file) and scrolling.
  - **Not swept:** recordings, GIFs, Capture Text (⇧⌘7).
- **Nothing is ever blocked.** Auto-copy, Copy, Save and drag work as before; the sweep starts after the thumbnail is up.
- **Wording always says "possible".** Bugeye never claims a capture is "safe" or "clean". There is no "clean" state: no badge at zero findings.
- **Acting on findings happens in the editor only.** The badge opens the editor. There is no Blur all on the thumbnail.
- **Ignore is per capture and per session.** There is no allowlist, no "never flag this value" and no per-app exclusion.
- **Success criteria from the spec:**
  - a screenshot showing `neo4j+s://admin:…@…` or an `sk-ant-…` key gets "⚠ 1 possible" within about 2 s;
  - one click on **Blur all** in the editor covers it.

### 1.2 Categories and defaults

| `SensitiveKind` | Default | Settings label | Badge tooltip (singular / plural) | Review title |
|---|---|---|---|---|
| `secret` | on | Keys and secrets | secret / secrets | Secret |
| `connectionString` | on | Connection strings with passwords | connection string / connection strings | Connection string |
| `highEntropy` | on | Token-like strings | token-like string / token-like strings | Token-like string |
| `card` | on | Card numbers | card number / card numbers | Card number |
| `email` | **off** | Email addresses | email / emails | Email |
| `phoneOrIP` | **off** | Phone numbers and IP addresses | phone or IP / phones or IPs | Phone or IP |
| `face` | on | Faces | face / faces | Face |

The enum order above matters:
- merged findings keep the earliest kind in it;
- the tooltip lists counts in it;
- Settings lists toggles in it.

### 1.3 The thumbnail badge

- **When:** shown only when a scan finds at least one item.
- **Look:**
  - an amber capsule at the thumbnail's bottom edge, centred;
  - the text is `⚠ N possible` (`SweepText.badge`);
  - the colour is `EditorChrome.amber` (`0xFF9F0A`), shared with the editor's outlines.
- **Tooltip:** counts per kind, joined by ` · `, for example `2 secrets · 1 face` (`SweepText.tooltip`).
- **Click:** opens the capture in the editor, like Edit, but without recording Edit as the user's "usual action" (M7 `ActionHabits`).
- **Removed when:**
  - the capture is ignored in the editor;
  - the editor's fresh reading of the saved file reaches zero (§1.5).
- **Lifetime:** findings live on the Quick Access entry for the session. They are never written to the file.

### 1.4 The editor's sweep bar

- **When the editor scans:**
  - on open, however it was opened (badge, Edit, double-click, Open Last Capture);
  - after each document change, after the same 0.5 s pause as Live Text (`LiveTextController.debounce`).
- **When the bar shows:** at least one finding and the capture not ignored.
  - It sits under the toolbar; under the find bar when both are open.
- **Text:** `1 item looks possibly sensitive` / `N items look possibly sensitive` (`SweepText.bar`).
- **Outlines:**
  - each finding gets an amber dashed outline, 1.5 pt at a fixed screen width;
  - the dash is `[4 pt, 3 pt]`;
  - while reviewing, the current item is also filled at 25 %;
  - outlines are overlay drawing only and never exported.
- **Buttons:**
  - **Blur all:**
    - blurs every finding as **one undo step**, in the current blur mode and strength;
    - each blur is the finding's box outset by 3 px per side; a face is outset by 20 % of its width/height per side (`SensitiveFinding.blurBox`);
    - blurs are clamped to the visible (cropped) image;
    - the bar vanishes at once, and the re-scan of the edit brings back anything still readable.
  - **Review:**
    - steps through the findings, scrolling each into view;
    - the label is `Secret: sk-ant-…3fQ2`: the first 6 chars, `…`, the last 4 chars (`SweepText.shortened`);
    - text of 12 characters or fewer shows as one `•` per character; a face shows as `Face`;
    - newlines are flattened to spaces;
    - **Blur** adds one blur (its own undo step) and moves on; **Skip** moves on;
    - after the last item the bar closes for this editor window, until a scan finds something not seen in that review.
  - **Ignore:**
    - hides the bar and outlines;
    - adds the capture ID to a session-only set, which also removes the thumbnail badge.

### 1.5 Badge follows the editor, only for the saved file

- An editor reading reaches the thumbnail badge **only when the document is not dirty**: at open, and after ⌘S, since a save re-reads.
- Unsaved edits leave the file as the badge counted it. Blurring everything and closing without saving keeps the badge.
- Ignore always clears the badge.

### 1.6 Settings → Privacy

- **Master switch:** "Check captures for possibly sensitive data" (`SweepText.settingsTitle`), on by default.
  - Off: nothing is scanned, no badge, no sweep bar. Find still works.
- **One toggle per kind**, labels as in §1.2. They are disabled while the master switch is off (`SettingsModel.sweepKindsEditable`).
- **Note:** "A check, not a guarantee: always look before you share." (`SweepText.settingsNote`).
- **When changes apply:**
  - the background sweep: the next scan;
  - an open editor: only after it is reopened (open issue, §4).

### 1.7 Error behaviour

| Situation | Result |
|---|---|
| OCR throws | No text findings, no message. Find shows "No text found in this image". |
| Face detection throws | No face findings (`FaceDetector` returns `[]`). |
| Scan finishes after the thumbnail is gone | Nothing shown. |
| Editor closes mid-scan | The read is cancelled. |
| Sweep off | No scans, badges or bar; find still works. |

---

## 2. How it's built

### 2.1 Files

| Target | File | Role |
|---|---|---|
| CSCore | `TextMap.swift` | `TextWord`, `TextLine`, `TextMap`; find matching; strips, scaling and strip merge |
| CSCore | `SensitiveScanner.swift` | `SensitiveKind`, `SensitiveFinding`; one function per rule; `scan`, merge |
| CSCore | `SweepText.swift` | All user-visible sweep wording; `blurBox` |
| CSCore | `SweepSettings.swift` | `enabled`, `kinds`, `activeKinds`, per-kind subscript |
| CSCore | `AppSettings.swift` | Keys `sweep.enabled`, `sweep.kind.<rawValue>` in `UserDefaults` |
| CSCapture | `TextRecognizer.swift` | `TextRecognizing` protocol; Vision OCR; `readMap` |
| CSCapture | `FaceDetector.swift` | `FaceDetecting`; Vision `DetectFaceRectanglesRequest` |
| App | `Sweep/SensitiveSweep.swift` | The background queue |
| App | `Sweep/SweepIgnores.swift` | Session-only ignored IDs |
| App | `Editor/EditorTextReader.swift` | Reads the flattened edit for find and sweep (debounced, cancellable) |
| App | `Editor/SweepModel.swift` | Sweep bar state: findings, review, ignored |
| App | `Editor/FindBar.swift` | Find bar and `SweepBar` SwiftUI views |
| App | `QuickAccess/ThumbnailView.swift`, `QuickAccessController.swift` | Badge, `updateFindings` |
| App | `Editor/EditorManager.swift`, `AppDelegate.swift` | Glue: kinds, ignore, badge forwarding |

### 2.2 The word map (`TextMap`)

```swift
public struct TextWord: Sendable, Equatable { var text: String; var box: CGRect }  // image pixels, top-left origin
public struct TextLine: Sendable, Equatable { var text: String; var box: CGRect; var words: [TextWord] }
public struct TextMap: Sendable, Equatable {
    var lines: [TextLine]
    static let empty
    var linesInReadingOrder: [TextLine]          // sorted by (minY, minX)
    func matches(of query: String, matchCase: Bool = false) -> [CGRect]
}
```

- **Words** are the line's text split on whitespace (`TextLine.wordRanges(in:)`).
- **`matches(of:)`:**
  - always `.diacriticInsensitive`; `.caseInsensitive` unless `matchCase`;
  - a match never crosses lines, but may span words;
  - an empty or whitespace-only query has no matches.
- **`TextLine.box(for: Range<String.Index>)`:**
  - the union of the words the range touches;
  - a word the range starts or ends inside is cut **in proportion to characters**. `customer` inside `customers` is 8/9 of the word's width;
  - returns nil when the range touches only spaces;
  - a line with no words counts as one word spanning the whole box.
- **Word spans:** each word's text is found in the line's text with `range(of:)` from a moving cursor. Words Vision didn't box are simply skipped.
- **Fakes:** `TextMap(fragments:)` builds one line and one word per fragment. This lets fakes that only implement `recognize` still produce a map.

### 2.3 Reading the map (`TextRecognizer.readMap`)

```swift
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> [TextFragment]
    func readMap(_ image: CGImage, pixelsPerPoint: CGFloat) async throws -> TextMap
}
```

- **Vision request:** `RecognizeTextRequest` (the Swift Vision API, macOS 15+), configured as:
  - `recognitionLevel = .accurate`;
  - `usesLanguageCorrection = false`: correction turns `foo(bar)` into `foo (bar)`;
  - `automaticallyDetectsLanguage = true`.
- **Per observation:**
  - the line is `topCandidates(1).first`;
  - each word's box is `candidate.boundingBox(for: wordRange)?.boundingBox`, which is Vision's box of those characters;
  - a word Vision can't box is dropped from `words`, but the line keeps its text.
- **Coordinates:** Vision's boxes are normalised with a bottom-left origin. `TextRecognizer.pixelRect` turns them into pixels with a top-left origin:
  `x = minX·w, y = (1 − maxY)·h, width·w, height·h`.
- **Small text:**
  - an image under 2 pixels per point is enlarged 2× before reading (`scale(forPixelsPerPoint:)`);
  - boxes are mapped back with `TextMap.mapped(scale:offsetY:)`;
  - the enlargement uses `ImageCodec.downscaled(strip, by: 2)`. Despite the name, a factor of 2 enlarges; that misleading name is worth fixing in a rebuild.
- **Tall images:**
  - strips are 4,000 px tall with a 200 px overlap (`TextMap.strips(height:)`, `stripHeight`, `stripOverlap`);
  - Vision otherwise shrinks a 60,000 px scrolling capture and loses its small text;
  - `Task.checkCancellation()` runs between strips.
- **Strip merge (`TextMap.merged`):**
  - a line entirely inside a strip's top overlap is dropped; the strip above already has it;
  - a line that starts inside the overlap and straddles its bottom replaces any overlapping line from the strip above, which the strip boundary cut;
  - verified by the smoke test `aTallImageReadsEachOverlapLineOnce`.
- **Default `readMap(_:)`** (no ppp) assumes 2, so no enlargement.

### 2.4 Faces (`FaceDetector`)

- `DetectFaceRectanglesRequest().perform(on:)`, with boxes mapped by `TextRecognizer.pixelRect`.
- Any error returns `[]`. It sits behind the `FaceDetecting` protocol.
- There is no face fixture in the repo. Faces are covered only by the manual checklist (a Zoom/Meet window, a profile photo) and by the smoke test `textHasNoFaces`.

### 2.5 The rules (`SensitiveScanner`)

Each rule is a `static func rule(_ line: String) -> [Range<String.Index>]`, testable with tables of must-flag and must-not-flag strings (`Tests/CSCoreTests/SensitiveScannerTests.swift`). All regexes are `NSRegularExpression`. Ranges are converted from `NSRange`, so UTF-16 is handled.

#### `secret`

| Rule | Pattern / logic |
|---|---|
| `prefixSecrets` | `(?<![A-Za-z0-9])(?:(?:sk-ant-\|sk-proj-\|sk-\|ghp_\|gho_\|ghs_\|github_pat_\|xoxb-\|xoxp-\|glpat-\|AIza)[A-Za-z0-9_\-]{16,}\|SG\.[A-Za-z0-9_\-]{16,}(?:\.[A-Za-z0-9_\-]+)?)`: the known prefix plus ≥16 token characters. SendGrid's `SG.` keeps its second dotted part. |
| `awsKeys` | `(?<![A-Za-z0-9])(?:AKIA\|ASIA)[A-Z0-9]{16}(?![A-Za-z0-9])` |
| `jwts` | `(?<![A-Za-z0-9_\-])eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+` |
| `keyValueSecrets` | `(?i)(?:password\|passwd\|pwd\|secret\|token\|api_key\|apikey\|access_key)(?![A-Za-z0-9_])["']?\s?[=:]\s?["']?([^\s"']{6,})`. **Only capture group 1, the value, is flagged.** There is no left boundary, so `NEO4J_PASSWORD=` matches. The lookahead stops `tokenType` from matching. The value needs ≥6 non-space, non-quote characters, so `password: abc` is not flagged. |
| `privateKeyBlocks` | Line-based: a line containing both `-----BEGIN` and `PRIVATE KEY-----` starts a block. The block runs to the first later line containing `-----END`, capped at 30 lines total. The finding is the union of all the block's line boxes; its text is the lines joined with `\n`. Lines inside a block are excluded from `highEntropy`. |

#### `connectionString`

| Rule | Pattern / logic |
|---|---|
| `urlCredentials` | `(?i)(?<![A-Za-z0-9+.\-])[a-z][a-z0-9+.\-]*://([^\s:/@]*:[^\s/@]+)@`. Any scheme (`neo4j+s`, `bolt`, `postgres`, `mongodb+srv`, `redis`, `amqp`, `https`, …). Only `user:password` (group 1) is flagged; the user may be empty (`redis://:pw@h`). `bolt://localhost:7687` has no `@`, so it is not flagged. |
| `authorizationTokens` | `(?i)authorization:\s*(?:bearer\|basic)\s+([A-Za-z0-9\-._~+/]+=*)`. Only the token is flagged. |

#### `highEntropy` (token-like strings), after tightening

`highEntropy(line, excluding: taken)`. A candidate is flagged when all of these hold:
1. **Run shape:** it matches `[A-Za-z0-9+/_\-]{24,}=*`. `=` is allowed only as trailing padding, so in `id=<uuid>` the run is the UUID, not `id=<uuid>`.
2. **No overlap** with any range another rule matched on this line (`taken`).
3. **Entropy:** Shannon entropy ≥ **3.5 bits per character**, computed over the run's characters.
4. **Hex, UUID or path:** if the run is pure hex, a UUID (8-4-4-4-12) or a path, it counts **only if the line holds a key word**.
   - The key word must be whole, or the end of an identifier: `(?i)(?:password|…|access_key)(?![A-Za-z0-9_])`.
   - A path is: it starts with `/`; or it follows `~` or `.`; or it has 2+ slashes and no `+` or `=`.
5. **Otherwise:** at least **3 of 4 character classes** (lowercase, uppercase, digit, symbol in `+/=`). `-` and `_` are **not** symbols: they join words. And none of the "public shapes" below applies.

**Public shapes (`isNotASecret`)**, added by the false-alarm fix `6ba6ede`:

| Shape | Test | Example kept quiet |
|---|---|---|
| Identifier | split on `-`/`_` into ≥4 parts, each ≤12 chars | `api-gateway-deployment-7d9f8b6c5d-x2k4j` (k8s pod), `Q3_Revenue_Forecast_FINAL_v2_reviewed` |
| npm/SRI integrity | prefix `sha256-`, `sha384-`, `sha512-` | `"integrity": "sha512-…=="` |
| Data URI | preceded by `;base64,` | `sourceMappingURL=data:application/json;base64,eyJ…` |
| Gerrit Change-Id | first char a letter, ≥33 chars, rest all hex | `Change-Id: I3f7868…` |
| SSH public key | preceded by `ssh-<alg> ` or `ecdsa-sha2-<curve> ` | `ssh-ed25519 AAAAC3Nz…` |

Must-not-flag lines in the regression test `everydayDeveloperScreensRaiseNoHighEntropyFalseAlarms` also include `request_id=<uuid>`, `traceId=<32 hex> spanId=<16 hex>`, `"tokenType": "bearer"` next to a UUID, and `NEO4J_AUTH_ENABLED_FOR_CLUSTER_2=true`. Padding still ends a run: `c2VjcmV0…Ng==` is flagged.

#### `card`

- **Run:** `(?<![0-9A-Za-z]|\d[ \-])\d(?:[ \-]?\d){12,18}(?![0-9A-Za-z]|[ \-]\d)`. That is 13–19 digits, optionally grouped by single spaces or dashes, never part of a longer number.
- **First digit:** must be **2–6**. Card networks start there; epoch-millisecond timestamps (`1729674842003`) start with 1 and are often Luhn-valid. This is test `timestampsAreNotCardNumbers`.
- **Checksum:** must pass Luhn.

#### `email`

`NSDataDetector(.link)`, keeping results whose `url?.scheme == "mailto"`.

#### `phoneOrIP`

- **Phones:** `NSDataDetector(.phoneNumber)`. The detector's range **includes a trailing space**, so it is trimmed before boxing.
- **IPv4:** `(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9]|\.\d)`, each octet ≤255. `127.0.0.1` and `0.0.0.0` are excluded.

#### `face`

Not a text rule. Face boxes are appended by `SensitiveScanner.findings(text:faces:)`, so faces always come last.

### 2.6 `scan(_:kinds:)`: assembling findings

- **No text kinds:** if `kinds` minus `.face` is empty, it returns `[]` immediately.
- **Line order:** lines are taken in reading order; private-key blocks are found first.
- **Rules feed `highEntropy` even when their own kind is off.** A rule runs if its kind is on **or** `highEntropy` is on. Anything a rule matches is never a "token-like string", so turning `secret` off must not make keys reappear as `highEntropy`.
- **Per line:** the rule ranges become boxes via `TextLine.box(for:)`. Only kinds in `kinds` are kept.
- **Merge:**
  - any two hits whose boxes overlap with **positive area** merge into one;
  - the union box is used, and the earliest kind in `SensitiveKind` order wins, with its text;
  - the merge loops until stable, because a growing union can reach new hits;
  - the result is sorted by (line index, minX).
- **Result:** `SensitiveFinding { kind, text: String?, box }`; `text` is nil for faces.

### 2.7 The background sweep (`SensitiveSweep`, app, `@MainActor`)

**Entry point:**
- `CaptureCoordinator.finish(image:scale:…)` calls it after `quickAccess.show` and after the copy/save.
- It covers area, window and full screen (one call per display file) and scrolling (`deliver:` closure).
- Capture Text never calls `finish`. Recordings go elsewhere.

```swift
@discardableResult
func scan(_ image: CGImage, pixelsPerPoint: CGFloat, for id: UUID) -> Bool   // false = not queued
var onRead: ((UUID, TextMap?) -> Void)?    // M10: hands the map to the indexer
```

- **Queue:** `waiting: [Job]` (each job holds its `CGImage`) plus at most one `running` task.
  - `scan` first drops waiting jobs that are no longer `wanted` (thumbnail gone or ignored), calls `onRead(id, nil)` for each, then appends.
  - `startNext` takes `waiting.popLast()`: **the newest first**.
  - Kinds are read from settings **at start**, so a changed toggle applies to the next scan.
  - The job runs in `Task.detached(priority: .utility)`.
- **One job:** `findings(in:pixelsPerPoint:kinds:reader:faces:)`:
  - text (`readMap`) and faces run concurrently with `async let`;
  - the text read is skipped if only `.face` is on; faces are skipped if `.face` is off;
  - a failed read gives no findings of that kind and no map.
- **Finished:** back on the main actor, `quickAccess.updateFindings(found, for: id)` runs if the capture is still wanted, then `onRead`, then the next job.
- **`wanted(id)`:** `!ignores.isIgnored(id) && quickAccess.isShowing(id)`.
- **Off switch:** `scan` returns false when `activeKinds` is empty or the ID is ignored. The coordinator then tells the indexer `sweepRead(id, map: nil)` so the index job doesn't wait.
- **M10 tie-in:** `Indexer.add(item, afterSweep: true)` holds the capture's index job until `onRead` delivers the sweep's `TextMap`, so a capture is OCR'd once (see `09-search-spotlight-similar.md`).

**Deviation from spec, approved by the user:**
- The spec's §4.3 had **one waiting slot**: a newer capture replaced a not-yet-started scan.
- In the manual pass (A7, A9), quick successive captures and ⌥⇧⌘3's per-display files lost their scans.
- Fix `7f97411`: a newest-first list. Every capture still on screen is scanned eventually.

### 2.8 Quick Access side

- `QuickAccessController.Entry.findings: [SensitiveFinding]` holds the findings.
- `updateFindings(_:for:)` is a no-op if the entry is gone or the findings are unchanged. `[]` removes the badge.
- `ThumbnailView.sweepBadge` is nil for empty findings. The badge button calls `actions.review`, which opens the editor without counting as an Edit habit.

### 2.9 Editor side

- **`EditorTextReader`** (one per editor) reads the **flattened edited image**: `EditorExporter.render(document, with: renderer)`, the same render as Copy Text.
  - **Consequence:** text already blurred is never found again. That makes Blur all self-confirming.
  - **Read now:** `readNow()` on open and `readIfNeeded()` when find opens.
  - **Debounced:** `documentChanged()` schedules a read after `LiveTextController.debounce` (0.5 s), only while `isActive()` (find open or sweep on); otherwise it cancels.
  - **Cancellation:** each read bumps a `generation` counter and cancels the previous task. Stale results are dropped.
  - **One read:** text `async let`, and faces only when `wantsFaces()` (sweep on and `.face` in kinds).
  - **Coordinates:** results are offset by `-CanvasLayout.imageOrigin` into document image pixels. The render includes frame padding and crop.
- **`EditorWindowController.read(_:)`:**
  - `find.update(map)`;
  - snap targets are refreshed (M9);
  - if the sweep is on: `SensitiveScanner.findings(text: scan(map, kinds), faces:)` → `sweep.update(found)` → `onSweepCountChanged`.
- **`sweepIsOn`:** `!sweepKinds.isEmpty && !sweepIgnored`.
  - `sweepKinds` is set by `EditorManager` at open from `settings.sweep.activeKinds`.
  - A collection image gets `[]`: no sweep bar in collections.
- **`SweepModel`** (ObservableObject):
  - `findings`;
  - `review: [SensitiveFinding]?`, fixed when Review starts so re-scans don't move it;
  - `reviewIndex`;
  - `ignored`;
  - `reviewed`, which keeps the bar shut after Review's end until a scan finds something not in it;
  - "same" means same kind, same text and intersecting boxes, because re-reads shift boxes slightly;
  - `isShowing = !ignored && reviewed == nil && !findings.isEmpty`.
- **Blur:**
  - `blur(found)` ends text entry;
  - it takes the current style with `shadow = false` and builds `.blur(blurBox, mode, strength)` annotations;
  - they are clamped to the visible crop, then go through `editorDocument.addAll` as one undo step.
- **Badge forwarding (`EditorManager.forwardSweep`):** `guard !editor.editorDocument.isDirty`, then `onSweepFindings(item, findings)`, then `quickAccess.updateFindings`.
- **Ignore:** `SweepIgnores.shared.ignore(id)` and `quickAccess.updateFindings([], for:)`.

### 2.10 Settings storage

- Stored in `UserDefaults` via `AppSettings`:
  - `sweep.enabled`;
  - `sweep.kind.secret`, `sweep.kind.connectionString`, and so on.
- Each is read with `object(forKey:) as? Bool`, so a missing key keeps the default.

### 2.11 Tests

- **No Vision in unit tests.** Use `FakeTextReader` and `FakeFaces` (in `Tests/CleanShotCopyTests/EditorTextReaderTests.swift`) and `sweepKeyMap` in `SensitiveSweepTests.swift`.
- **Smoke tests (`CSC_INTEGRATION=1`, `Tests/CSCaptureTests/TextRecognizerTests.swift`):**
  - `realVisionFindsAKeyAndACardNumber`: a rendered `sk-ant-api03-…` and `4111 1111 1111 1111`. It also checks that boxes from a 2×-enlarged read come back in the original pixels (within 8 px);
  - `aTallImageReadsEachOverlapLineOnce`: an 8,200 px image with a line in the overlap;
  - `textHasNoFaces`.

---

## 3. Gotchas and bugs we hit

Rows 1–5 came up in review or in the user's manual pass, and have fix commits. Rows 6–10 were handled while the feature was first written; the reasons are recorded only in code comments.

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | The sweep flagged half of a developer's screen as "token-like": k8s pod names, `request_id=<uuid>`, `traceId=<hex>`, `"tokenType"` lines, npm `integrity` hashes, sourcemap data URIs, SSH public keys, Gerrit Change-Ids, long file names, env names | (a) `=` was a token character, so `id=<uuid>` became one high-class run. (b) `-`/`_` counted as "symbols", so any hyphenated identifier had 3 classes. (c) "Has a key word" was `lowercased().contains`, so `tokenType` and `NEO4J_AUTH…` matched, and a key word anywhere bypassed every exemption. (d) There was no notion of public random-looking shapes. | `6ba6ede`: `=` only as trailing padding; `-`/`_` not symbols; key word must not be followed by an identifier character; a key word only re-enables hex/UUID/path, never bypasses the class test; `isNotASecret` shapes (§2.5) |
| 2 | Epoch-millisecond timestamps (`1729674842003`) flagged as card numbers | 13-digit numbers often pass Luhn | `6ba6ede`: the first digit must be 2–6 |
| 3 | Quick successive captures, and the second display's file with ⌥⇧⌘3, never got a badge | The spec's single waiting slot: each new capture replaced the not-yet-started one | `7f97411`: newest-first list; gone or ignored jobs are pruned on each `scan` |
| 4 | A tall scrolling capture never got its badge | Checking ~16 strips takes longer than the 5 s thumbnail timeout, and results for a gone thumbnail are dropped | Not fixed. The checklist tells the tester to hover the thumbnail. See §4 |
| 5 | After Ignore, the badge came back; an early ⌘S cleared a badge although the file still showed the secret | Every editor sweep, and also every save, forwarded its findings to the badge, including readings of unsaved edits and stale readings at save time | `441d197`: only a reading taken while the document is **not dirty** reaches the badge; the save no longer forwards directly (the post-save re-read does). Ignored editors never sweep, so nothing is forwarded. |
| 6 | `NSDataDetector` phone ranges boxed one character too wide | The detector includes a trailing space in the match | Trim trailing whitespace from the range (`phones`) |
| 7 | Turning `secret` off made keys reappear as "token-like strings" | Rules only ran when their kind was on, so `highEntropy` saw the key unclaimed | A rule runs whenever its kind **or** `highEntropy` is on; its ranges go into `taken` |
| 8 | Language correction broke code text | Vision's correction rewrites `foo(bar)` | `usesLanguageCorrection = false` everywhere (inherited from M6 OCR) |
| 9 | Small text on a 1× external display read badly | Vision needs ~2 px per point | Enlarge 2× under 2 ppp; map boxes back |
| 10 | Scrolling captures lost small text in OCR | Vision downsizes very tall inputs | Read 4,000 px strips with a 200 px overlap; merge |

---

## 4. Known open issues (from `docs/backlog.md`, M8 section)

- **Tall captures:** a very tall scrolling capture (~16 strips) is rarely checked before the 5 s timeout, and its scan keeps running after the thumbnail goes. Cancel the running scan on dismiss; consider restarting the timer when a badge appears.
- **Late background result:** a background result that lands after an editor saved can restore the original's badge. Drop background results for a capture an editor has already reported.
- **Double render:** on a tall capture, each settled edit renders the full image twice on the main thread (Live Text and find/sweep), about 0.35 s and 1.4 GB transient at 60,000 px. Share one render, or render off the main thread.
- **Strips before enlargement:** `readMap` cuts strips **before** the 2× enlargement, so a 1× strip reaches Vision at 8,000 px. Strip at `4000 / scale` rows.
- **Stale kinds in open editors:** an open editor keeps the sweep kinds it opened with. Read them at each scan.
- **Stuck "Reading…":** if the editor's render fails, find stays on "Reading…". Deliver an empty reading.
- **Layout jump:** the sweep bar appearing a second after open pushes the canvas down, and `chromeHeight` ignores the bars' height.
- **Extra OCR per save:** every save re-reads the image, even with no change since the last reading.
- **Remaining `highEntropy` false alarms:** YouTube list IDs, base64 cursors, a `tls.crt` body, and a path on a line containing `pwd`.
- **OCR only:** find, the sweep and Live Text still read OCR only. The M9 snapshot's exact lines would make them exact (M9 backlog note).

---

## 5. Do it better next time

1. **Design the rules against a corpus of real developer screens from day one.** Collect OCR'd lines from Terminal, k8s, CI logs, package locks, git logs, JSON APIs and browser dev tools. Make "zero findings on this corpus" a test before shipping. Every false alarm in §3 was predictable from such a corpus.
2. **Keep each rule as a pure `(String) -> [Range]` function with must/must-not tables.** This worked well. Add a per-rule reason string for debugging ("flagged by highEntropy: 4.1 bits, 3 classes").
3. **Use the newest-first queue from the start,** with cancellation of the running scan when its thumbnail is dismissed (`Task.cancel()` plus `Task.checkCancellation()` between strips, which already exists).
4. **Strip after scaling.** Compute strip height in the input image's pixels as `4000 / scale`.
5. **One render per edit, off the main thread,** shared by Live Text, find, the sweep and snapping. A single "edited image reading" service with debounce and generation counters (as `EditorTextReader` has) fed by one render.
6. **Make the badge's source of truth explicit:** a per-capture "file reading" version. Background scan results and editor readings both carry the file's revision (bumped on each save), and the badge only accepts the newest revision. This removes both the late-result bug and the dirty/clean special case.
7. **Read settings at each scan**, in the editor too.
8. **Feed exact text (M9) into the sweep and find.** `ExactText` already produces positioned lines. A sweep that reads a terminal's exact text avoids OCR slips in keys.
9. **Rename `ImageCodec.downscaled(_:by:)`** to `scaled(_:by:)`. Calling it with 2 to enlarge has confused every reader.
10. **Keep the wording rule:** never "safe" or "clean". The user cared about this.
11. **Keep faces covered by a fixture.** A synthetic or licensed face image in the test resources would let a smoke test cover `FaceDetector`.
12. **Split it between the portable core and the macOS shell** (see `13-rebuild-strategy-agentic-ci-and-claude.md`):

    | Piece | Where | Notes |
    |---|---|---|
    | `TextWord`/`TextLine`/`TextMap`, `matches(of:)`, `box(for:)`, strips, `mapped`, `merged` | **core** | Only Foundation geometry (`CGRect`) and `String`. Already pure. |
    | Every `SensitiveScanner` rule, `scan`, merge, `SweepText`, `SweepSettings`, `blurBox` | **core** | Pure. Two portability traps: `NSDataDetector` (email, phone) is **not implemented in swift-corelibs-foundation on Linux**, so replace it with portable regexes (or a `DataDetector` port with a regex fake) and re-run the must/must-not tables on both OSes. `String.CompareOptions.diacriticInsensitive` in `matches(of:)` should be checked on Linux (or replaced by folding both strings first). `NSRegularExpression` works on Linux. |
    | The sweep queue (`SensitiveSweep`: newest-first, prune on dismiss, cancel, kinds read per scan), `SweepModel` (bar, review, ignore), `SweepIgnores`, the badge rule (§5 item 6) | **core**, as state machines | Drive with a fake clock, fake `TextReader` and fake `FaceFinder`. This makes the late-result and dirty-save bugs (§3 rows 3, 5) Linux-testable. |
    | OCR (`RecognizeTextRequest`, word boxes, 2× enlargement, strip reading) | **shell**, behind the `TextReader` port | The port returns a `TextMap` in the input's pixels. Strip planning and box mapping stay in the core, so the adapter only reads one `PixelBuffer` strip at a time. Enlargement is a core `PixelBuffer` resample or an adapter detail. |
    | Face detection (`DetectFaceRectanglesRequest`) | **shell**, behind `FaceFinder` | Returns pixel rects, top-left origin. |
    | Badge view, sweep bar view, outlines drawing | **shell** | Outlines can be display-list commands from the core, marked "overlay, never exported". |
    | Smoke tests with real Vision | macOS CI | Use the fixture app's fake-secrets window, not the user's desktop. |

13. **The sweep is also the redaction step for Claude features.** Per `13-…` §5, anything sent to the Anthropic API is first swept locally, and its findings are blurred in the image sent. Run the same rules over any text sent (OCR text, source URLs, window titles). Design for this from the start:
    - expose `SensitiveScanner.scan(text: String) -> [Range]` for plain text, not only `TextMap`;
    - have a core `Redactor` that returns both the blurred display list or image and the redacted text;
    - in that path, turn **all** kinds on (emails and phones too), whatever the user's badge settings are;
    - never send a finding's text to Claude to "check" it.

14. **Cross-reference:** the find bar, `FindModel`, `FindAction` and `EditorDocument.addAll` (one undo step) are in `03-editor.md`.
