# Bugeye

Bugeye is a personal macOS 26 menu-bar app for one user on one Apple Silicon Mac: screenshots, annotation, recording, OCR, provenance, search and collections, a replacement for CleanShot X. It is being rebuilt by Claude agents from the design atlas in `design/`, which holds everything the first build learned. Read `design/README.md` first; `design/14` holds the user's newest rulings and wins over older docs; `design/11` has the process, the toolchain traps and the recurring bug classes. Each wave is specified in `docs/specs/` and planned in `docs/plans/`.

## Commands

| Command | What | Where |
|---|---|---|
| `make test-core` | Build and test the portable targets | Linux and Mac (what CI's `linux` job runs) |
| `make lint` / `make format` | `swift format` check / fix (`.swift-format`) | Linux and Mac |
| `make guards` | Bug-class guards (`scripts/guards.sh`) and their self-test | Linux and Mac |
| `make build`, `make test` | Every target and every test | Mac with Xcode |
| `make bundle` | `build/Bugeye.app`, ad hoc signed (`CONFIG=debug` for a debug bundle) | Mac |
| `make cert` | Once: the self-signed "Bugeye Dev" signing identity | the user's Mac |
| `make install` | Bundle, sign with "Bugeye Dev", copy to `~/Applications`, relaunch | the user's Mac |
| `make fixture` | Run the fixture app | Mac |
| `make check-release-symbols` | Release builds contain no debug channel | Mac |

A cloud session runs on Linux: it can run the first three rows. Everything else is checked by the `macos` CI job on the pull request.

## Layout

```
Package.swift              every target is declared here; feature branches never edit it
Sources/BugeyeCore/        portable: geometry, PixelBuffer, display list, CaptureID, settings, ports, CaptureFileWriter
Sources/BugeyeFeatures/    portable: FeatureModule, FeatureRegistry, the status menu, shell strings
Sources/BugeyeTestSupport/ portable: every fake, TempDirectory, the fixture app's content
Sources/Core/<Area>Core/   portable: one per area (Capture, QuickAccess, Editor, Recording, Motion, Text,
                           Provenance, Search, Collections, Guide, AI); empty until its wave
Sources/Mac/MacAdapters/   macOS: the real adapters behind the ports
Sources/BugeyeApp/         macOS: the app shell (menu bar, Settings, wiring, debug channel)
Sources/BugeyeFixture/     macOS: the fixture app for smoke and end-to-end tests; never shipped
Sources/BugeyeIconTool/    macOS: draws the icon and the menu-bar glyph
Tests/<Target>Tests/       one test target per target; area tests keep recorded data in Fixtures/
scripts/                   guards, bundle, cert, install, CI helpers
docs/specs/ docs/plans/ docs/ledgers/ docs/checklists/ docs/backlog.md
design/                    the design atlas (read-only)
```

## Rules that cut across everything

- **Portable first.** Logic goes in a portable target with tests that run on Linux. macOS targets only adapt Apple frameworks and render. Portable targets import Foundation and Swift modules only (`make guards` checks).
- **One capture-file writer.** Only `CaptureFileWriter` writes or rewrites a capture file, so the `dev.msenechal.bugeye.*` attributes and `kMDItemWhereFroms` survive. No `.atomic`, `atomically: true` or `replaceItemAt` anywhere else (`make guards` checks).
- **Every system service behind a port.** A protocol in `BugeyeCore`, a fake in `BugeyeTestSupport`, the adapter in `MacAdapters`. Settings go through `SettingsStore`, secrets through `SecretStore` (the Keychain); `UserDefaults` appears only in `Sources/Mac`.
- **Nothing slow on the main thread.** Accessibility, Vision, ImageIO, export and network calls are slow; run them off the main actor with timeouts.
- **Identity checks on async results.** A result that arrives late checks a generation or identity before it changes state, so it never overwrites newer state (see `AIKeySettings.testKey`).
- **Settled strings.** Every user-visible string is copied exactly from the spec. Keep them in one place (`ShellStrings`, `AIKeyStatus.message`) and test them character for character.
- **Never store typed text.** Text-entry and secure fields are never read, stored or sent (`AXElementInfo.text` is nil for them).
- **No name clashes.** Darwin already has `Point` and `Rect`, SwiftUI has `Color` and `Path`, AppKit has `document`. Check before naming a type (`Point2D`, `Rect2D`, `RGBAColor`, `VectorPath` exist for this reason).
- **AI is opt-in per feature, off by default.** Before writing Claude API code, load the `claude-api` skill; `AnthropicClient` checks `stop_reason` and retries only 429, 5xx and connection errors.
- **Debug-only code** lives in files named `Debug*.swift` that start with `#if DEBUG`.

## Swift and tests

- Swift 6.4 (`.swift-version`), Swift 6 language mode in every target, deployment target macOS 26. The Mac uses Xcode; Linux uses the `swift:6.4.3-noble` image.
- Swift Testing only (`import Testing`). `#expect` can't take a `mutating` call: hoist it into a `let`. Never spin `RunLoop.main` in a test. Give each test its own `TempDirectory`. Import what you use.
- `swift test --filter` is a regex over `Target.Suite/test()` names.

## Git and process

- Work on a branch (`feat/<wave>-<slice>`), never on `main`. Push and open a draft pull request early; CI (`linux`, `macos`) runs on every push, and `claude-review` comments when the PR is opened or marked ready. Never merge: the user merges.
- Commit messages end with the trailer lines your session's instructions give (Co-Authored-By, Claude-Session). Pull request descriptions end with the Claude Code line they give.
- The process is in `.claude/skills/`: `brainstorm` → `write-spec` → `write-plan` → `execute-plan` → `final-review` → fix pass → `manual-checklist`. During execution, decide ambiguities yourself, record each as `Ruling:` in the ledger (`docs/ledgers/`) and keep going.
- Leave `docs/rd/` and `t.md` untracked and untouched: they are the user's notes.
