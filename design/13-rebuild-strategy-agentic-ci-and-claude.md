# Rebuild strategy: Linux-first agentic development, CI/CD, and Claude-powered features

The first build was written by agents on the user's Mac, with the Command Line Tools only, and tested by hand. The rebuild changes three things:

1. **Development happens in a Claude cloud environment linked to the repo, which runs Linux.** Agents must be able to build and test most of the code there, with no Mac.
2. **Testing, bug finding and fixing are agentic and run in CI/CD**, not only in a human's manual pass.
3. **AI features use Claude through the Anthropic API** (an API key), instead of on-device models only.

The product doesn't change: a native macOS 26 menu-bar app on the user's Mac. This file explains how to reconcile that with a Linux build environment.

---

## 1. The hard constraint

- **A macOS app can't be built on Linux.** The macOS SDK, AppKit, ScreenCaptureKit, Vision, VisionKit, AVFoundation, Accessibility (`AXUIElement`), Core Graphics, Core Text, Core Image, ImageIO, Core Spotlight and code signing exist only on macOS. Apple doesn't support cross-compiling a macOS app from Linux.
- **What Linux can do:** build and test a Swift package that uses only Swift, the standard library, Foundation (`swift-corelibs-foundation`) and C libraries such as SQLite.
  - Swift Testing works on Linux with Swift 6.
  - Foundation on Linux has `CGFloat`, `CGPoint`, `CGSize` and `CGRect`, but not `CGImage`, `CGContext`, `CTFont` or anything that draws.
- **So the design question is how much of Bugeye can be Linux-testable logic**, and how thin the macOS-only layer can be made.

### Where the first build stands

| Target | Tests | Runs on Linux today? |
|---|---|---|
| `CSCore` (pure logic) | 324 | No. 26 of its 58 files import CoreGraphics or ImageIO, mostly just for `CGRect` and `CGPoint`. A few (`ScrollStitcher`, `ImageCodec`) touch `CGImage`. |
| `CSEditor` (editor model, renderer, collections) | 196 | No. It renders with Core Graphics and Core Text. |
| `CSCapture`, `CSRecording` | 70 | Never (Apple frameworks by nature). |
| App (`CleanShotCopy`) | 457 | Never (AppKit). |

About half the tests check logic that's pure in spirit, but none of them compile on Linux. The rebuild should fix that on purpose.

## 2. Language and stack choice

| Option | Linux-testable share | macOS integration | Agent ergonomics | Verdict |
|---|---|---|---|---|
| **A. Swift: a portable core package plus a macOS shell** | high (≈60–70 % of logic, if designed for it) | native, as today | one language, Swift Testing everywhere | **Recommended** |
| B. Rust core plus a Swift/AppKit shell over FFI (UniFFI or swift-bridge) | high | native shell, but every boundary crosses FFI | two toolchains, generated bindings, harder debugging | Only if the core grows large and shared |
| C. Tauri or Electron (web UI plus native plugins) | high for the UI | poor: overlays, menu bar, ScreenCaptureKit, AX, Vision and the editor canvas all still need native code | familiar to agents, but the hard 40 % stays native | Rejected |

**Why A:**
- Everything that makes Bugeye work is an Apple framework. The shell will be Swift whatever you choose.
- A second language only adds an FFI boundary.
- Swift on Linux is mature enough for a pure core with tests.

### Rules for a portable core (option A)

1. **One package, with targets split by platform.** Portable targets have no `import AppKit`, `CoreGraphics` (beyond the Foundation geometry types), `CoreText`, `ImageIO`, `Vision`, `ScreenCaptureKit` or `AVFoundation`. macOS targets are declared only under `#if os(macOS)` in `Package.swift`, so `swift build` and `swift test` on Linux simply skip them.
2. **Own value types at the boundary.** Images cross as `PixelBuffer` (width, height, bytes per row, RGBA8 bytes). Text runs cross as plain structs. Fonts cross as descriptors. The macOS shell converts to and from `CGImage` and `NSFont`.
3. **Rendering as a display list.** The editor, the collection exporter, step badges and frames produce a list of draw commands (fill path, stroke, image, text run, blur region) in the core. The macOS shell executes it with Core Graphics.
   - On Linux, test the display list (golden JSON snapshots).
   - On macOS CI, test the rasterised pixels (golden PNGs with a tolerance).
4. **Pure algorithms take `PixelBuffer`:** scroll stitching, pixel hashes, the diff mask for M12, frame-change detection and the frame ring.
5. **Ports for every system service**, each a protocol in the core with a fake. Many already exist as fakes; promote them to first-class ports:

   | Port | macOS adapter |
   |---|---|
   | `ScreenSource` | ScreenCaptureKit |
   | `TextReader` (OCR word map) | Vision |
   | `FaceFinder`, `RectangleFinder` | Vision |
   | `AXReader` | Accessibility |
   | `ClipboardWriter` | NSPasteboard |
   | `FileMetadataStore` (xattrs, Where-from) | `setxattr` and Spotlight keys |
   | `CaptureIndexStore` | SQLite. It **runs on Linux too**, with the system SQLite: test the real index on Linux. |
   | `SpotlightDonor` | Core Spotlight |
   | `SpeechTranscriber` (M13) | Speech |
   | `LLMClient` (Claude, §5) | URLSession. It also works on Linux through `FoundationNetworking`. |

6. **App logic as view models and state machines in the core:** Quick Access stack and selection, the selection overlay lifecycle, the recording phase machine, the guide session, collection editing and undo. AppKit views only render them and forward events. That puts most of the bugs in `11-process-and-testing-lessons.md` §6 (overlays outliving controllers, late results, lost state) into Linux-testable code.

Target: about 60–70 % of tests run on Linux in seconds, and the rest run on macOS CI.

### Toolchain notes

- **Linux:**
  - Install Swift 6.x with `swiftly` or use the official `swift:6.x` Docker image.
  - Pin the version in a `.swift-version` file, and use the same version on macOS.
  - URLSession on Linux needs `import FoundationNetworking`.
  - `NSRegularExpression`, `JSONEncoder` and `FileManager` exist but have small behaviour differences; test them on Linux.
- **macOS CI:** GitHub-hosted macOS runners have Xcode. That removes the CLT-only limits there (SwiftUI macros, XCTest), but the user's Mac builds with the Command Line Tools only. Pick one:
  - (a) keep the code CLT-compatible, so `make install` works on the Mac as today; or
  - (b) install Xcode on the Mac.

  (a) is the safe default. Keep a CI job that builds with the CLT toolchain so nothing Xcode-only slips in.
- **Signing:** CI can't use the user's "CleanShotCopy Dev" identity, and shouldn't. CI builds are ad-hoc signed for tests only. The installable build is signed on the user's Mac (or a self-hosted runner there), so TCC permissions survive. See `01-architecture-and-toolchain.md`.

## 3. CI/CD in three tiers

| Tier | Where | When | What |
|---|---|---|---|
| 0 | the Claude cloud environment (Linux) | every agent edit | `swift build`, `swift test` for portable targets; format and lint (`swift-format`); fast, under a minute |
| 1 | GitHub Actions, hosted macOS runner | every PR | full build including the app target; all unit tests including AppKit view models and display-list rasterisation goldens; the app bundle script; a CLT-only build check. No real capture: hosted runners can't be granted Screen Recording or Accessibility. |
| 2 | self-hosted runner on the user's Mac | merge to main, nightly, or on demand | signed build with the stable identity; `make smoke` (real ScreenCaptureKit, Vision, Accessibility, Spotlight); agentic end-to-end scenarios (§4); install to `/Applications` only when the user opts in |

### Tier 2 safety

A self-hosted runner on a personal Mac executes code from the repo with the user's permissions. Rules:
- private repo only;
- no workflows triggered by forks or outside pull requests;
- a dedicated macOS user account for the runner, with Screen Recording and Accessibility granted to the runner once;
- jobs never touch `~/Pictures/Bugeye`: they use a temp save folder through a settings override.

### Fix the flaky smoke tests with fixtures

The first build's flakiest tests depended on whatever was on screen (`scrollingAWindowStitchesTheWholeDocument`, the overlay colour tests). The rebuild ships a small **fixture app** (a test target, never in the product) that opens windows with known content:
- a scrollable page of numbered lines;
- labelled buttons and checkboxes for the guide recorder;
- a text field;
- fake secrets for the sweep;
- known colours.

Smoke and end-to-end tests drive the fixture, not the user's desktop.

## 4. Agentic testing, bug finding and fixing

### End-to-end scenarios from the manual checklists

Every `docs/manual-checklist-*.md` from the first build is a ready-made scenario list. Each test has steps and one **Expected** line. Turn them into executable scenarios in two layers:

1. **A debug-only test channel in the app.** A local socket or XPC interface compiled only into debug and test builds. It lets a test:
   - trigger a hotkey action;
   - read the Quick Access stack, open windows and their view models;
   - read the files and xattrs written;
   - set settings.

   This isn't the rejected automation surface: it doesn't exist in release builds, and it isn't a user feature. Most assertions go through this channel and are deterministic.
2. **Claude computer use for what only a screen can show:** an overlay's look, a thumbnail's badge, the editor's rendering, the guide bar's position, a dark-mode HTML export.
   - An agent on the Tier 2 runner runs the scenario and screenshots the result.
   - It judges the Expected line, and attaches the screenshots to the run.
   - Use it for visual checks only, never for the logic the test channel can assert.

The user's own manual pass stays as the final gate before a milestone merges ("all good"), but it gets much shorter: only feel and taste, not regressions.

### Agent roles in the pipeline

| Role | Trigger | Does | Never |
|---|---|---|---|
| Implementer | a planned task (cloud environment) | TDD on the plan's task, Tier 0 green, push a branch and PR | merge; push to main |
| Reviewer | every PR (Claude Code GitHub Action or `/code-review`) | the whole-diff review that found real Critical bugs in every milestone; posts findings | approve its own PR |
| CI fixer | a failed Tier 1 or Tier 2 job | reproduces the failure with a failing test, fixes it, and opens a fix PR linked to the failure | mark a test flaky without measuring; skip or delete a test |
| E2E runner | nightly and pre-merge on Tier 2 | runs scenarios, files an issue per failure with screenshots and logs | change code |
| Triage | nightly | reads new issues and `docs/backlog.md`, labels severity, proposes the next fix batch | close issues the user opened |

Guardrails:
- `main` is protected, and required checks are Tiers 0 and 1. The user merges milestone branches after the manual pass.
- Every fix carries a test that failed first (the TDD rule from the first build). The reviewer rejects a fix without one.
- **Flake policy:** a test is quarantined only after an agent measured it (several runs, same commit, with the failure rate recorded), and the quarantine opens an issue. The first build's flakes were all real timing or environment problems.
- Cost and loop limits: a CI-fixer gets one attempt per failure, then hands it to the user.

## 5. Claude-powered features through the Anthropic API

### This reverses a product rule; settle it in the first spec

The first build's rule was "nothing leaves the Mac". Screenshots are the most secret-dense data a developer produces: tokens, customer data, connection strings. Using Claude means some of it leaves the Mac. Rules for the rebuild:

1. **Opt in for each feature, off by default.** Settings → AI lists each Claude-powered action. The API key lives in the **Keychain**, never in UserDefaults or the repo.
2. **Show what leaves before it leaves:** the first time per feature, then a "Sent to Claude" line in the result.
3. **Redact before sending:**
   - Run the local sensitive sweep (M8 rules plus faces) first and blur its findings in the image that's sent.
   - Run the same rules over any text sent (source URLs, OCR text).
   - Never send secure fields or typed text. The guide recorder's rule stays: typed text is never stored, so it can't be sent.
4. **Keep the private-by-default paths local:**
   - OCR and the word map (Vision)
   - the sensitive sweep itself
   - the AX snapshot
   - the search index
   - speech transcription (M13)

   They're fast, free and private. Claude works on their results, not instead of them.
5. **Degrade gracefully.** Every Claude feature has a non-AI result (the first build's template captions, plain transcript). With no key, offline, or after a refusal, the product works exactly as the first build did.

### Calling the API from Swift

There's no official Anthropic Swift SDK, so call the HTTP API directly with `URLSession` inside the `LLMClient` port:
- `POST https://api.anthropic.com/v1/messages`
- headers `x-api-key`, `anthropic-version: 2026-10-21`, `content-type: application/json`
- images as content blocks: `{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": …}}`, placed before the text that refers to them. Downscale to what the feature needs first; it saves tokens and upload time.
- **Model:** `claude-opus-5-5` by default.
  - Thinking is always on for it; control depth with `output_config: {effort: "low" | "medium" | "high"}`. Its default is `medium`.
  - Don't send `thinking: {type: "disabled"}`, `budget_tokens` or `temperature`: they're rejected.
  - Make the model a setting, so the user can choose a cheaper one (`claude-haiku-5-5`, `claude-sonnet-5-5`) for high-volume features.
- **Machine-read results** use structured outputs (`output_config: {format: {type: "json_schema", …}}`), never parsing of prose. Forced `tool_choice` is rejected on this model.
- **Long outputs** (a bug report, a guide intro) stream, so a request doesn't hit timeouts.
- **Always check `stop_reason`** before reading `content`. `refusal` falls back to the non-AI result. Consider server-side fallbacks (beta `server-side-fallback-2026-07-01`, `fallbacks: "default"`).
- **Retries:** retry 429, 5xx and connection errors with backoff, and respect `retry-after`. Don't retry 400s.
- **Caching:** put the stable system prompt first with `cache_control`, to cut cost on repeated calls (every guide step, every collection).
- **Tests:**
  - `FakeLLM` in unit tests on Linux.
  - Recorded request and response fixtures for the HTTP adapter.
  - A separate, opt-in eval job that calls the real API with a CI secret and grades outputs against a small rubric. It costs money, so it runs on demand or nightly, never per edit.

Before writing this code, load the `claude-api` skill in the session. It has the current request shapes, model IDs and breaking changes, and the API moves fast.

### Where Claude helps, mapped to built or committed features

Only features that exist or are committed. Each is a proposal for its milestone's brainstorm, not a decision.

| Feature | Claude's job | Input sent (after redaction) | Fallback |
|---|---|---|---|
| Guide recorder (M11) | Rewrite each step's caption in natural prose; write a caption when Accessibility gave nothing (Electron or canvas apps) by looking at the screenshot around the click point; write the guide's title and a short intro | the step's screenshot crop around the click, the AX role and title, the app name | template captions ("Click **Save**") |
| Collections (M11) | Draft the intro paragraph and per-image captions | the images, the existing text blocks | nothing added |
| Bug report composer (committed RD-08) | Draft `report.md`: title, steps to reproduce, expected vs actual, from the screenshot or recording frames, the source record and environment | image or key frames, source, `env.txt` | the empty template |
| Before/after diff (M12) | Say in words what changed between the two captures | both images, the pixel-diff regions, the exact text of both | the pixel diff only |
| Transcript editing (M13) | Suggest cuts (false starts, filler, repeats) and chapter titles from the local transcript | transcript text with timings, never the audio | silence cuts only |
| Find Capture (M10) | Optional: turn a vague query into search terms, and re-rank the top 20 results by their text | the query, result texts (redacted) | the FTS ranking |

**Keep local:**
- the sensitive sweep (sending a suspected secret to check it defeats the purpose)
- OCR and exact text
- the AX snapshot
- Copy for AI, whose whole point is to prepare a paste for an external assistant

These are single API calls or short workflows. None needs an agent loop inside the app. Start with one call per action, and only add tool use where a feature really needs several steps.

## 6. What this changes in the rebuild order

1. **Skeleton first:**
   - the package with portable and macOS targets;
   - a Tier 0 job green on Linux, and a Tier 1 job on a hosted macOS runner;
   - the fixture app;
   - the debug test channel;
   - the self-hosted runner on the Mac;
   - the `LLMClient` port with `FakeLLM`, and Keychain storage for the key.
2. **Then the order from `README.md`.** For each feature, write the core (view model, state machine, algorithm, display list) Linux-first with tests, then the macOS adapter, then its end-to-end scenario on Tier 2.
3. **AI features join each milestone's spec as opt-in additions**, with their redaction rule, fallback and eval written in the spec.
