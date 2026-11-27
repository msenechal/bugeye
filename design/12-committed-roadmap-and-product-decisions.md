# Committed roadmap and product decisions

What the user committed to but hasn't been built yet, the rulings that shape it, and what must stay out of the product. Uncommitted R&D ideas aren't listed here on purpose.

## 1. Product decisions that apply everywhere

| Decision | Detail |
|---|---|
| One user, one Mac | Personal tool. No distribution, App Store, auto-update, cloud or accounts. |
| macOS 26 minimum | The user is on 26.7.1. It unlocks `SpeechTranscriber` and Vision's newer requests. `Package.swift`: `.macOS(.v26)`. |
| Name | The product is **Bugeye** everywhere the user sees it. The package, app target and signing identity are still `CleanShotCopy`; the bundle id is `dev.msenechal.cleanshotcopy`. A rebuild may rename them, but changing the bundle id or identity resets every TCC permission once. |
| Save folder | `~/Pictures/Bugeye/`, collections in `~/Pictures/Bugeye/Collections/`. |
| Browsers | Only Arc and Chrome get special handling (tab URL, and later the extension). No Safari, Edge, Brave or Firefox work. |
| Privacy wording | Findings are "possible", never "safe". Typed text and secure fields are never stored. |
| AI | First build: nothing leaves the Mac; on-device Vision and Speech only. **Rebuild (user's direction, Nov 2026):** AI features may call Claude through the Anthropic API. They're opt-in, redacted before sending, and have a local fallback. OCR, the sweep, the AX snapshot, the index and speech stay local. See `13-rebuild-strategy-agentic-ci-and-claude.md` §5. |
| Search | A search index is fine. A browsable capture history UI is rejected: nothing is listed before the user types. |

## 2. Never build

The user rejected these. Don't propose them in a rebuild.

- **Out of scope in the original spec** (the user said "forget them"): pin-to-screen, cloud upload and share links, a capture history UI, self-timer, hiding desktop icons, auto-update.
- **Rejected R&D ideas:**
  - Capture to a note / Markdown destinations
  - Data detectors in Quick Access
  - Retention policy and stars
  - Instant replay (a rolling screen buffer)
  - Watch a region; live region mirror
  - ~~Auto-zoom recordings~~ (reversed Nov 2026: now wanted, see `14` R3)
  - Onion-skin a design over the screen
  - Measure and pick colours in the loupe
  - Contrast and accessibility audit
  - Table capture
  - Clean capture (exclude apps and notifications)
  - Automation surface (URL scheme, Services, AppleScript)
  - In-place translation
  - Continuity Camera import
  - Keyboard-only selection
  - Read aloud and zoom view
  - Alt text on copy
- **Re-editable captures** (annotations kept editable after save, a sidecar with the original). Approved first, then dropped before M11: "overkill as I will be using it only for myself". Consequence: annotations are flattened on save, including images inside collections.
- **Cut parts of approved features:**
  - No alt text in the HTML clipboard.
  - No replay buffer in bug reports.
  - No Vision classification chips in search.

## 3. Committed, not built yet

These come in this order, each through the full milestone process (`11-process-and-testing-lessons.md` §5). They're described as the user approved them, plus the rulings since. None has a spec yet, so each starts with a brainstorm.

### M12: Before/after diff

- **What:** recapture the same area or window later and compare the two images.
- **Flow:** ⋯ → **Compare with new capture** reuses the stored area (like Return-to-recapture) or the same window.
- **Diff window:** three modes:
  - a swipe slider
  - onion-skin
  - a difference mask that highlights changed pixels
- **Export:** a side-by-side PNG, or a two-frame GIF through the existing `GifEncoder`.
- **Builds on:** recapture-last-area in the selection controller, `ScreenCapturer` window capture, `GifEncoder`, `EditorRenderer`. The M7 source record and the M10 identity can link the "before" capture to the "after" one.
- **Known risks:** anti-aliasing and subpixel noise, which need a tolerance setting and a settle delay before the second capture. A window that moved or resized needs aligning, or must be refused.

### M13: Video by transcript and on-device captions

- **Edit by transcript:**
  - After a recording, `SpeechTranscriber` (macOS 26) transcribes it on device with word timings.
  - The trim window shows the transcript. Striking out words creates cut ranges.
  - Silence gaps over 1.5 s are offered as cuts.
  - Export uses several ranges through `AVMutableComposition`.
- **Captions:** export with captions off, burned in (night style, through a compositor), or a `.srt` file alongside. They reuse the same transcript.
- **Builds on:** `RecordingTrimmer` (extend it from one range to several), `TrimRange`, `TrimWindowController`, `RecordingFinalizer`.
- **Order inside the milestone:** silence removal needs no speech recognition, so ship it first.
- **Known risks:**
  - downloading the speech model assets
  - language support
  - frame-accurate cuts, which need a re-encode rather than a passthrough at keyframes

### Bug report composer (RD-08)

- **What:** one hotkey bundles a capture, its source details and system info into a report.
- **User's ruling:** bug reports are for reproducible bugs. A report attaches a recording the user makes to reproduce the bug, or just a screenshot when that's enough. There's **no replay buffer**.
- **Flow:**
  1. A capture, or a pick of a recent recording.
  2. A small sheet with title, expected and actual, pre-filled from the window title.
  3. Output: a folder with `report.md`, the image or clip, and `env.txt` (app and OS versions).
  4. A Linear draft can come later through a URL template.
- **Hotkey:** the original idea used ⇧⌘8, which is now Find Capture. Pick a new one during the brainstorm.
- **Known risk:** scope creep in the sheet UX.

### Copy for AI, phase 2: browser logs (RD-06 phase 2)

- **What:** when the capture is an Arc or Chrome window, Copy for AI also includes recent console errors and warnings plus a network summary (failed, slow and 4xx/5xx requests: method, URL, status, timing).
- **How:**
  - An opt-in companion browser extension keeps a small rolling buffer per tab.
  - It talks to Bugeye through native messaging. Recent Chrome ignores the remote-debugging port on the default profile, so that route is closed.
  - Bugeye matches the captured window to its tab using the M7 URL and title.
- **Privacy:**
  - Strip auth headers, cookies and tokens in query strings with the M8 rules before copying.
  - Leave request and response bodies off by default.
  - Cap the size.
- **Arc and Chrome only.**

## 4. Order and dependencies

```
M11 (collections + guide recorder) ──► merged
M12 before/after diff ── independent
M13 transcript + captions ── needs the multi-range trimmer
RD-08 bug report ── uses M7 source, recordings, M11 package or folder writer
RD-06 phase 2 ── uses M7 source matching, M8 secret rules
```

In a rebuild, the base app (M1–M6), the source record (M7), the text map and sweep rules (M8), the AX snapshot (M9) and the index (M10) are the foundations everything else reuses. Build them in that order. See `README.md`.
