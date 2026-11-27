# Process, testing and toolchain lessons

How Bugeye was built, what worked, and what cost time. Read this before you write the first line of a rebuild. The feature files (01–10) cover the product itself.

## 1. The machine and toolchain

- **Command Line Tools only, no Xcode.** The build uses Swift 6.x from `/Library/Developer/CommandLineTools`. Every decision below follows from that.
- **No XCTest.** Tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`).
- **The testing macro plugin is flaky under SwiftPM without Xcode.** SwiftPM sometimes leaves the Swift Testing macro plugin out of test compiles. Every test target passes `-plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` as an unsafe flag in `Package.swift`. Keep it from day one.
- **Only three macro plugins ship:** `libObservationMacros`, `libSwiftMacros` and `testing`.
  - SwiftUI's `@State`, `@Binding` macros, `@Observable` and `#Preview` fail with "SwiftUIMacros plugin not found". The message doesn't say the plugin is missing from the toolchain.
  - Use `ObservableObject` with `@Published` and `@ObservedObject`/`@StateObject`, or plain AppKit classes.
  - Foundation Models' `@Generable` and App Intents (no `appintentsmetadataprocessor`) are unavailable too.
- **No asset catalogs, no storyboards, no Xcode project.** The app bundle is assembled by `scripts/bundle.sh` from the SwiftPM binary, a hand-written `Resources/Info.plist` and `Resources/Bugeye.icns`. The icon is drawn in code (`BugeyeIconTool`, `make icon`).
- **Signing with a stable self-signed identity ("CleanShotCopy Dev", `make cert`).** TCC (Screen Recording, Accessibility, Automation) keys permissions to the code signature. Ad-hoc signing gives a new identity on every build, and the user would have to re-grant permissions after each `make install`. Create the identity once and sign every build with it.
- **lldb can't attach to the installed app** (sandbox, and the user denied a sandbox bypass). For crashes, reason from the code, add `os_log` (subsystem `dev.msenechal.bugeye`) and read `log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'`.

## 2. Architecture rules that paid off

- **Pure logic in Swift 6 library targets (`CSCore`, `CSEditor`), Apple-framework wrappers in Swift 5 targets (`CSCapture`, `CSRecording`), AppKit in the app target (Swift 5).**
  - Swift 6 strict concurrency on ScreenCaptureKit, AVFoundation and AppKit delegate code produced endless non-`Sendable` noise. Keeping those targets in Swift 5 mode was the practical choice.
  - The pure targets stayed Swift 6, and that's where most tests live.
  - About 1,050 tests in total (M11). Most are fast pure tests.
- **Every Apple API sits behind a protocol with a fake**, so unit tests never touch the real system:

  | Real | Fake used in tests |
  |---|---|
  | Clipboard | fake `ClipboardWriting` |
  | Notifications | fake notifier |
  | Vision OCR | `FakeTextReader` |
  | Vision faces | `FakeFaces` |
  | Accessibility tree | `FakeAXTree` |
  | Rectangle detection | `FakeRectangles` |
  | Feature prints | `FakeFeaturePrinter` |
  | Spotlight | `FakeSpotlight` |
  | Search index | `FakeCaptureSearching` |
  | Guide frames | `FakeFrameSource` |
  | Guide input | `FakeGuideInput` |
  | Clicked element | `FakeAXPoint` |

- **Real-system tests are opt-in smoke tests** behind `CSC_INTEGRATION=1` (`make smoke`). They need Screen Recording and Accessibility granted to the terminal.
- **Indexes and the real save folder are never used by tests.** Use temp databases and temp folders, with unique names per test: parallel tests collide otherwise. One M11 helper had to be renamed because a `tempDir()` already existed in another test file of the same target.

## 3. Swift Testing gotchas

- `#expect` can't take a call to a `mutating` method. Hoist the call into a `let` first.
- `--filter` is a regex over test names, and it also has to match tests declared with traits (`@Test(.timeLimit(…))` and so on). When you replay a task, use the filter that names all its tests, regression tests included, not just the new ones.
- Tests run in parallel by default, and main-actor tests saturate the main thread. Rules learned the hard way:
  - **Never spin `RunLoop.main` synchronously in a test.** It stalls main-queue waits in other parallel tests (M6 part 4).
  - **Give any test that waits for a main-queue delivery a generous budget (10 s).** Under full-suite load the main queue is sampled late, not blocked (M7, again M11's `aStreamFailureEndsTheGuide`).
  - Make failure paths synchronous where you can (M11: a stream failure stops input at once), so tests don't depend on timing.
- **"All cases" tests break on purpose** when an enum grows (capture kinds, chips, the shortcuts notice text). That's fine; update them in the same task.
- Missing `import Foundation` in a test file compiles in some targets and not others, depending on transitive imports. Import what you use.

## 4. Flaky tests and how to tell a flake from a regression

| Test | Why it flakes |
|---|---|
| `scrollingAWindowStitchesTheWholeDocument` (smoke) | depends on what's on screen; can come out short |
| Recording-overlay colour smoke tests, M9's AX smoke test | fail when the screen is busy |
| `doneDeliversTheStitchedImageAtScreenScaleAndEndsOnce` | main-queue timing under full-suite load |

- Rerun the failing test alone, and compare with `master` before calling it a regression.
- Two runs per bisect step can't locate a flake this frequent. Measure with a main-queue probe plus `sample`.
- **A full-suite hang was seen once** (65 threads in `-[NSAnimation _runBlocking]`, also on a known-green commit). It was machine state (DaVinci Resolve open), not code. Workaround: `--skip` the window and animation tests and run them alone.

## 5. The milestone process

Every milestone went through the same steps, using the superpowers skills:

1. **Brainstorm** with the user: one question at a time, multiple choice where possible, a visual companion for layout questions.
2. **Spec** in `docs/superpowers/specs/`, approved by the user.
3. **Plan** in `docs/superpowers/plans/`, in TDD steps with exact code, approved by the user. The plan has a Review Focus section (the input classes the tests don't exercise).
4. **Execution** inline (executing-plans), task by task, test first, with a ledger in `.superpowers/sdd/<plan>/progress.md` that survives context compaction. Every deviation from the plan is a ledgered `Ruling:`.
5. **One final review** of the whole branch by a fresh, most-capable reviewer.
6. **One fix pass** for Critical and Important findings, each with a test that fails first. Minor findings go to `docs/backlog.md`.
7. **The user's manual pass** with `docs/manual-checklist-<milestone>.md`.
8. **The user says "all good"**, the branch merges to `master`, and CLAUDE.md and memory are updated in the same merge.

What worked:
- **Feature branches only** (`feat/<milestone>`), never feature work on `master`.
- **"Replay execution"** (M8–M10): draft each task green in scratch worktrees, merge them, then execute the plan by replaying each task's commit tests-first (RED) then source (GREEN). It was fast and kept TDD honest.
- **The final review always found real bugs.** M11's review found 3 Critical and 8 Important issues after a fully green suite. Never skip it.
- **The ledger plus `git log` beat memory** after compaction. Trust them over your recollection of what's done.

### Manual checklists: the format the user wants

The first one-line-per-item draft was judged unclear. Each checklist has:

1. **Before you start**: what to launch, which permissions, what test data to prepare.
2. **A shortcuts table** for the keys used below.
3. **How to check**: Terminal commands to inspect results (xattrs, packages, logs).
4. **Numbered tests in sections**, each with numbered steps naming the exact shortcut or menu item, and one **Expected** line.

`docs/manual-checklist-m7-provenance.md` is the model.

## 6. Recurring classes of bugs

These kept coming back across milestones. Design against them from the start.

- **Atomic writes drop extended attributes.** Bugeye keeps its metadata in xattrs (`…provenance`, `…uisnapshot`, `…id`, `kMDItemWhereFroms`). Every path that rewrites a capture must copy them back: editor save, downscale, Save As (which deliberately gets a new ID), the collection package swap. Centralize "rewrite a capture file" in one function that preserves xattrs.
- **Late asynchronous results overwriting newer state.** A snapshot arriving after the editor saved, a sweep result after the thumbnail was dismissed, an indexer pass after the file moved. Give every async result an identity or generation check before applying it.
- **Windows shown before they have a size.** An `NSTableView` row-height calculation in a window with zero width gave a negative height and crashed (signal 5, M11). Clamp layout widths to a minimum.
- **Overlays that outlive their controller.** The stuck selection overlay (M1–M9) was a late `mouseEntered` re-ordering a finished overlay window to the front with no controller left to close it. Rules: a finished overlay ignores events, `finish` closes its windows, and every selection's start and end close leftovers. Add a right-click and global-Esc safety net to any full-screen overlay.
- **Name clashes with AppKit.** `NSWindowController.document` already exists, so M11's collection document property is `doc`. `Collection` shadows Swift's protocol, so the model is `CaptureCollection`. Check AppKit and stdlib names before naming a type or property.
- **Main-thread work in "small" calls.** An AX read can take up to 0.25 s per call times dozens of calls in a slow Electron app. Image decoding of a large collection, full-resolution re-renders and exports all blocked the main thread until moved off it. Assume every Accessibility, Vision, ImageIO and export call is slow.
- **ScreenCaptureKit scaling.** Asking SCK for a window capture at the window's size squeezes window plus shadow into that size (about 0.83×), which looks blurry. Capture at the display's full scale (`WindowShadow.atFullScale`). The user also has a 1× external 1080p monitor beside the Retina screen, so test both scales.
- **Data the user typed must never leak into output.** Guide captions read the clicked element through Accessibility. Text-entry roles must never contribute their value or static text (M11 Critical 3). Secure fields are never read (M9).

## 7. Working with this user

- **Single user, personal tool.** Features that mainly help other people, or that are "overkill for just me", get rejected (RD-21 was dropped for exactly that reason). Don't add sharing, cloud or multi-user features.
- **No vault logging** for this project (it's under `perso/`).
- **Commit messages** end with the Co-Authored-By trailer the session gives. PR descriptions end with the Claude Code line.
- **Leave `docs/rd/` and `t.md` untracked and untouched.** They're the user's working notes.
- **Every user-visible string follows the spec exactly.** Settle the wording in the spec, not during implementation.
- **The repo-root CLAUDE.md is the hand-off guide** for a fresh session. Update its Features, Next and code map at each merge.
- **When there's a conflict or an ambiguity during execution, decide, ledger it and keep going.** Present every ruling, with its cost if wrong, in the final message. The user prefers that to being asked mid-run.
