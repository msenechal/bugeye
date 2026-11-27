# Wave 0: the skeleton

**Status:** draft for approval · **Date:** 27 November 2026 · **Process:** brainstorm → spec (this) → plan → execution → final review → fix pass → manual pass

Wave 0 builds no user feature. It builds the frame every later wave plugs into, so that parallel cloud sessions can work without colliding (`design/14` R1) and without your Mac (R9). It runs serially, in one session.

## 1. Decisions

From the brainstorm (your answers):

| # | Question | Decision |
|---|---|---|
| B1 | The first build's source code | **Unavailable.** The design docs are the whole specification; gaps are decided in brainstorms and written into specs. |
| B2 | App identity | **Bugeye everywhere.** Package `Bugeye`, app `Bugeye.app`, bundle id `dev.msenechal.bugeye`, signing identity "Bugeye Dev". The old app keeps running side by side until the rebuild replaces it. |
| B3 | Mac toolchain | **Install Xcode.** SwiftUI macros, Foundation Models and App Intents are allowed. Local and CI builds both use Xcode. |
| B4 | Claude reviews | **Claude Code GitHub Action, authenticated with a token from your Claude subscription.** No API key for reviews. |

Rulings I made (each can be overturned at approval; cost if wrong in brackets):

| # | Ruling | Why |
|---|---|---|
| W1 | All targets use the Swift 6 language mode. A macOS adapter target may drop to Swift 5 mode only with a ledgered ruling naming the errors. | Newer Swift and Xcode reduce the concurrency noise that pushed the first build to Swift 5. [Low: switching one target's mode is a one-line change.] |
| W2 | Swift version: the one that ships with the current Xcode 26 release, pinned in `.swift-version` and used for Linux too. The plan's first task records the number. | One compiler everywhere avoids Linux-only or macOS-only surprises. [Low] |
| W3 | Every target the waves need is declared in `Package.swift` now, most of them empty. | Feature branches never edit the manifest (R1). [Medium: a missed target means one manifest edit later.] |
| W4 | Specs in `docs/specs/`, plans in `docs/plans/`, execution ledgers in `docs/ledgers/`, backlog in `docs/backlog.md`, manual checklists in `docs/checklists/`. Ledgers are committed. | Shorter than the first build's `docs/superpowers/…`. Committed ledgers survive across cloud sessions and let parallel sessions see each other's progress. [Low] |
| W5 | The process (brainstorm, spec, plan, execute, review, fix, checklist) is written down as repository skills in `.claude/skills/`, plus a root `CLAUDE.md`. | A session started from your phone has none of the first build's plugins or memory. The repo itself must carry the process. [Medium: without it, sessions drift.] |
| W6 | Reviews and other workflows only run for pull requests whose branch lives in this repository. | The repo is public; strangers' PRs must never reach an agent or a secret (`design/14` §5b). [High if skipped] |
| W7 | Bug-class guards start in Wave 0 as a small script run in CI, beginning with the rules Wave 0 can already break. | Cheap, deterministic, and grows with each wave (`design/14` ideas). [Low] |

## 2. Scope

In scope:
1. The package: portable and macOS targets, ports and fakes, the shared value types.
2. The feature registry, settings, the capture-file writer.
3. The AI port: `LLMClient`, an Anthropic HTTP adapter, `FakeLLM`, Keychain storage for the key.
4. A menu-bar app that launches, shows its icon and menu, and opens Settings.
5. The fixture app (first version) and the debug test channel (stub).
6. Build scripts: bundle, signing certificate, install.
7. CI: Linux job, macOS job, Claude review job.
8. `CLAUDE.md`, the process skills, the docs folders.

Out of scope: any capture, editor, recording or AI feature; hotkeys (none are registered in Wave 0); the Mac batch automation (it needs real features to check).

## 3. Repository layout

```
Package.swift              every target declared (W3)
.swift-version
Makefile
CLAUDE.md                  hand-off guide for any new session
.claude/skills/            the process (W5)
Sources/
  BugeyeCore/              portable: geometry, PixelBuffer, display list, identities, settings model, ports
  BugeyeFeatures/          portable: FeatureModule protocol and registry
  Core/<Area>Core/         portable, empty until their wave (see §4)
  Mac/<Adapter>/           macOS adapters, declared only on macOS
  BugeyeApp/               the macOS app shell
  BugeyeFixture/           the fixture app (test-only, never shipped)
  BugeyeIconTool/          draws the app icon in code
Tests/<Target>Tests/       one test target per target
scripts/                   bundle.sh, cert.sh, guards.sh
Resources/Info.plist
docs/specs/ docs/plans/ docs/ledgers/ docs/checklists/ docs/backlog.md
design/                    the design atlas (unchanged)
.github/workflows/         linux.yml, macos.yml, claude-review.yml
```

## 4. Targets

Portable targets build and test on Linux. macOS targets are declared inside `#if os(macOS)` in `Package.swift`, so `swift build` on Linux skips them (`design/13` §2).

| Target | Platform | Wave 0 content |
|---|---|---|
| `BugeyeCore` | portable | geometry types, `PixelBuffer`, display-list commands, `CaptureID`, settings model, all port protocols |
| `BugeyeFeatures` | portable | `FeatureModule`, `FeatureRegistry` |
| `BugeyeTestSupport` | portable | every fake (`FakeScreenSource`, `FakeTextReader`, `FakeAXReader`, `FakeClipboard`, `FakeFileMetadataStore`, `FakeLLM`, …) |
| `CaptureCore`, `QuickAccessCore`, `EditorCore`, `RecordingCore`, `MotionCore`, `TextCore`, `ProvenanceCore`, `SearchCore`, `CollectionsCore`, `GuideCore`, `AICore` | portable | empty except `AICore` (the HTTP adapter and request types) |
| `MacAdapters` | macOS | Keychain, `UserDefaults` settings store, xattr metadata store; other adapters arrive with their wave |
| `BugeyeApp` | macOS | menu bar, Settings window, module wiring, debug test channel |
| `BugeyeFixture` | macOS | fixture app |
| `BugeyeIconTool` | macOS | icon renderer |

### Ports declared now

`ScreenSource`, `TextReader`, `FaceFinder`, `RectangleFinder`, `AXReader`, `ClipboardWriter`, `FileMetadataStore`, `CaptureIndexStore`, `SpotlightDonor`, `SpeechTranscriber`, `LLMClient`, `SecretStore`, `SettingsStore`.

Each is a protocol in `BugeyeCore` with a fake in `BugeyeTestSupport`. Only `FileMetadataStore`, `LLMClient`, `SecretStore` and `SettingsStore` get real adapters in Wave 0. The others keep their protocol and fake until their wave; a wave may change a port's shape, with a ledgered ruling.

### Shared value types

- `PixelBuffer`: width, height, bytes per row, RGBA8 bytes. The only way images cross the core boundary.
- Display list: fill path, stroke path, image, text run, blur region; `Codable`, so golden JSON tests work on Linux.
- `CaptureID`: the stable identity used by provenance, search and collections.

## 5. Behaviour

### 5.1 Feature modules

```swift
protocol FeatureModule {
    var id: String { get }                       // "capture", "editor", …
    func menuItems() -> [MenuItemSpec]            // where and what
    func hotkeys() -> [HotkeySpec]                // default keys, setting key
    func settingsSection() -> SettingsSectionSpec?
    func quickAccessActions() -> [QuickAccessActionSpec]
}
```

The specs are plain values in the portable target. The app shell turns them into `NSMenuItem`s, hotkey registrations and Settings panes. Tests check that two modules can't claim the same hotkey or menu slot. Wave 0 registers one module, `general`, which contributes the Settings pane in §5.3.

### 5.2 Capture-file writer

`CaptureFileWriter` is the only code allowed to write or rewrite a capture file (`design/README` "one choke point"). It writes through a temp file, then copies back every `dev.msenechal.bugeye.*` extended attribute and `com.apple.metadata:kMDItemWhereFroms` from the previous version, unless the caller asks for a new identity (Save As). It works through `FileMetadataStore`, so it is tested on Linux with the fake. The guard script fails CI if `.atomic` or `replaceItemAt` appears anywhere else.

### 5.3 The app

Menu-bar only (no Dock icon). The icon is the Bugeye mark drawn by `BugeyeIconTool`.

Menu, top to bottom:

| Item | Key |
|---|---|
| About Bugeye | |
| — | |
| Settings… | ⌘, |
| — | |
| Quit Bugeye | ⌘Q |

Settings window, titled "Bugeye Settings", two panes:

- **General:** "Save captures to" showing `~/Pictures/Bugeye/`, with a "Choose…" button. The folder is created on first launch if missing.
- **AI:** an "Anthropic API key" field. Saving stores the key in the Keychain, never in `UserDefaults` or a file. A "Test key" button sends one minimal request through `LLMClient`. Status line, exactly one of:
  - "No key saved."
  - "Key saved. Not tested yet."
  - "Key works."
  - "Key was rejected. Check it and save it again."
  - "Couldn't reach Anthropic. Check your connection."

The AI pane states: "Bugeye only sends data to Claude for features you turn on. Each one is off until you enable it."

### 5.4 LLMClient

`AnthropicClient` in `AICore`: `POST /v1/messages` over `URLSession` (with `FoundationNetworking` on Linux), the headers and rules in `design/13` §5: check `stop_reason`, retry 429 and 5xx with backoff and `retry-after`, never retry other 4xx. The model is a setting. Tests use recorded request and response fixtures on Linux; no test calls the real API. Before writing it, the implementing session loads the `claude-api` skill for current request shapes and model IDs.

### 5.5 Fixture app

A window with: a scrollable list of 300 numbered lines; three labelled buttons and two checkboxes; a text field; a panel of fake secrets (an AWS-style key, a GitHub-style token, an email, a card number, all invalid); four colour swatches with known values. Never bundled into `Bugeye.app`.

### 5.6 Debug test channel

Compiled only in debug builds: a Unix-domain socket in the app's temp directory. Wave 0 answers two commands, `ping` and `modules` (the registered module ids). Release builds contain none of it; a test checks that the symbol is absent in a release build.

## 6. Build, sign, install

- `make build`, `make test` (all targets), `make test-core` (portable targets only, what Linux runs).
- `make bundle`: assemble `Bugeye.app` from the SwiftPM product, `Resources/Info.plist` and the generated icon.
- `make cert` (once, on your Mac): create the self-signed "Bugeye Dev" identity in your login keychain.
- `make install`: bundle, sign with "Bugeye Dev", copy to `/Applications`, relaunch. Signing with a stable identity keeps permissions across installs (`design/11` §1).
- CI builds are ad-hoc signed and never installed.

## 7. CI

| Workflow | Runs on | Trigger | Does |
|---|---|---|---|
| `linux.yml` | GitHub-hosted Linux, `swift` Docker image at the pinned version | push, pull request | `make test-core`, `swift-format lint`, `scripts/guards.sh` |
| `macos.yml` | GitHub-hosted macOS with the macOS 26 SDK | pull request, push to `main` | `make test`, `make bundle` |
| `claude-review.yml` | GitHub-hosted Linux | pull request opened or updated, head branch in this repo only (W6) | Claude Code Action reviews the diff against `CLAUDE.md` and the `design/11` §6 bug classes; posts findings as review comments, never an approval |

Required checks on `main` once green: `linux`, `macos`. The review is not a required check: it comments, the authoring session fixes, you merge.

Things to confirm in the plan's first tasks (not decisions, facts to check):
- the macOS runner label that ships the macOS 26 SDK;
- that the Claude Code Action accepts a subscription token, and the exact secret name. If it doesn't, the session stops and asks you (B4);
- the current Swift version (W2).

## 8. The process in the repo (W5)

`CLAUDE.md` covers: what Bugeye is (one paragraph, pointing at `design/`), the commands in §6, the layout in §3, the rules that cut across everything (one capture-file writer, nothing slow on the main thread, identity checks on async results, settled strings, never store typed text), and the git rules (feature branches, PRs, commit trailers).

Skills in `.claude/skills/`:

| Skill | Encodes |
|---|---|
| `brainstorm` | one question at a time, multiple choice, record decisions in the spec |
| `write-spec` | the spec shape used here, every user-visible string settled |
| `write-plan` | TDD tasks with exact code, a Review Focus section |
| `execute-plan` | test first, ledger in `docs/ledgers/`, decide-ledger-continue on ambiguity, push and open a PR |
| `final-review` | fresh whole-branch review, Critical/Important/Minor, Minor to `docs/backlog.md` |
| `manual-checklist` | the `design/11` §5 checklist format |

## 9. Done when

1. `linux` and `macos` checks are green on the Wave 0 PR, and the review workflow has posted a review on it.
2. The final review's Critical and Important findings are fixed, each with a test that failed first.
3. At your Mac (the only Mac step), following `docs/checklists/wave-0.md`:
   1. Install Xcode if it isn't already.
   2. `make cert`, then `make install`.
   3. The Bugeye icon appears in the menu bar; the menu matches §5.3.
   4. Settings opens; General shows `~/Pictures/Bugeye/`; the AI pane shows "No key saved."
   5. Optional, only if you have an Anthropic API key: save it, press "Test key", see "Key works." (one tiny request).
   6. The old app still runs alongside.
4. You say "all good", and the branch merges.
