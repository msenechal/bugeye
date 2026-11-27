# Bugeye rebuild findings

This folder holds everything a future agent needs to rebuild Bugeye from scratch, with the same capabilities and fewer mistakes. It records:
- what was built through M11, and how;
- the exact behaviour the user approved;
- every bug that cost time;
- what to do differently.

Uncommitted R&D ideas are left out on purpose.

**Written:** November 2026, from the specs, plans, checklists, code, git history (≈375 commits) and review findings of M1–M11.

## What Bugeye is

A personal macOS 26 menu-bar replacement for CleanShot X, for one user on one Apple Silicon Mac, with no cloud. It covers:

- **Capture:** area, window, full screen, every display, scrolling capture, Capture Text (OCR).
- **Quick Access:** a thumbnail stack after each capture, with actions.
- **Editor:** 11 annotation tools, frames, Live Text selection, ⌘F find with Highlight/Box/Blur all, snapping to UI elements.
- **Recording:** MP4/GIF, mic and system audio, click rings, keystrokes, webcam bubble, trim, GIF export.
- **Context:** every capture records its source (app, window, Arc/Chrome URL, document), with Open Source, a rich clipboard, Copy for AI and Copy as Markdown.
- **Privacy:** a background sensitive-data sweep (secrets, emails, cards, faces) with one-click blur.
- **Exact text:** an Accessibility snapshot at capture, merged with OCR, so copied text is byte-exact where possible.
- **Search:** a full-text index of every capture (Find Capture ⇧⌘8), Spotlight donation, Find Similar and Duplicates.
- **Collections:** `.bugeye` documents of images and text, exported to image, PDF, Markdown or HTML.
- **Record Guide (⇧⌘9):** each click becomes a numbered step with a caption read from Accessibility.

## Files

| File | Covers |
|---|---|
| `01-architecture-and-toolchain.md` | Targets, language modes, build, signing, Info.plist, permissions, hotkeys, menu bar, settings, app wiring |
| `02-capture-and-quick-access.md` | M1 capture, selection overlay, multi-display and scale, output routing, Quick Access, the stuck-overlay saga |
| `03-editor.md` | M2 editor, Live Text, find bar, snapping, collection-image mode |
| `04-recording-and-media.md` | M3–M5 recording, overlays, trim, GIF export |
| `05-scrolling-capture-and-ocr.md` | M6 scrolling capture and stitching, Capture Text and OCR |
| `06-provenance-and-clipboard.md` | M7 source record, Open Source, rich clipboard, Copy for AI, learned next action |
| `07-sensitive-sweep-and-find.md` | M8 text map, secret rules, background sweep, badge and sweep bar |
| `08-ax-snapshot-and-exact-text.md` | M9 Accessibility snapshot, exact-text merge, snapping data |
| `09-search-spotlight-similar.md` | M10 index, identity, indexer, Find Capture, Spotlight, similar and duplicates |
| `10-collections-and-guide-recorder.md` | M11 collection model, package, exporters, window, guide recorder |
| `11-process-and-testing-lessons.md` | Toolchain traps, test architecture, flakes, the milestone process, recurring bug classes, working with the user |
| `12-committed-roadmap-and-product-decisions.md` | Global product rulings, the never-build list, the committed but unbuilt milestones |
| `13-rebuild-strategy-agentic-ci-and-claude.md` | **Read before writing code.** Linux cloud development for a macOS app (portable Swift core plus a macOS shell), three-tier CI/CD, agentic testing and fixing, Claude API features and the privacy rules around them |
| `14-direction-changes-and-agentic-proposals.md` | **The user's later rulings, which override earlier docs where they conflict** (parallel agent sessions, auto PR pipeline, auto-zoom, AI captions, presentation-style collections, guide as video), plus proposals for the next brainstorm |

Each feature file follows the same shape:
1. What it does
2. How it's built
3. Gotchas and bugs we hit
4. Known open issues
5. Do it better next time

## How to use this for a rebuild

1. **Read `14`, then `13`, `11` and `12`.** `14` holds the user's newest rulings; where it conflicts with an earlier doc, `14` wins. `13` changes the shape of the rebuild: it's developed by agents in a Linux cloud environment, so the code is split into a portable core and a thin macOS shell, and AI features call Claude. The toolchain traps alone (no Xcode, no SwiftUI macros, the testing plugin flag, a stable signing identity) cost days the first time.
2. **Read `01` and set up the skeleton:**
   - the package with pure Swift 6 targets and Swift 5 framework-wrapper targets;
   - the bundle script, `Info.plist`, the signing identity and `make install`;
   - the fakes for every Apple API.
3. **Build in this order.** Each layer is reused by the ones after it:
   1. Capture, output routing and Quick Access (`02`), with the selection overlay safety nets from day one.
   2. Editor (`03`).
   3. Recording, then trim and GIF (`04`).
   4. Scrolling capture and OCR (`05`). OCR's word map is reused by the sweep, find, exact text and search.
   5. Source record and clipboard (`06`). Design the "rewrite a capture file and keep its xattrs" helper here, once.
   6. Text map and sweep (`07`).
   7. Accessibility snapshot and exact text (`08`).
   8. Index, identity and search (`09`).
   9. Collections and guide recorder (`10`).
   10. The committed roadmap (`12`).
4. **Keep the process:** spec, plan, TDD, one fresh final review, one fix pass, then the user's manual checklist. The final review found real Critical bugs in a fully green suite every time.

## What to do better: the short version

Each feature file has its own list. These cut across all of them:

- **One choke point for writing capture files**, which preserves the `dev.msenechal.bugeye.*` xattrs and `kMDItemWhereFroms`. Their loss through atomic writes recurred in M7, M9, M10 and M11.
- **Assume Accessibility, Vision, ImageIO and exports are slow.** Keep them off the main thread from the start, with explicit timeouts and cancellation.
- **Give every async result a generation or identity check** before applying it, so late results never overwrite newer state.
- **Model overlay and window lifecycles explicitly** (a state machine with a single owner). Close leftovers at every start and end.
- **Design for both display scales** (Retina 2× and a 1× external monitor) and test window capture on both.
- **Settle every user-visible string in the spec.**
