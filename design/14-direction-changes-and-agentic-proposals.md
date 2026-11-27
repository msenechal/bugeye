# 14 — Direction changes and agentic proposals

Feedback from the user after the first read of the design docs, and proposals that follow from it. **Rulings** (§1) are the user's decisions and override earlier docs where they conflict. Everything else is a **proposal** for the next brainstorm, not a decision.

_Round 1 · November 2026 · from the user's review of the dashboard overview_

## 1. Rulings from the user

| # | Area | Ruling | What it changes |
|---|---|---|---|
| R1 | Development | **Parallel cloud sessions, one branch per epic.** Epics and features are scoped so several Claude cloud sessions can implement them at the same time, each on its own branch. | Doc 11 §5 ran execution inline in one session; doc 13 §4 already had the Implementer role push a branch. Now the plan must be cut for parallel work. |
| R2 | Development | **Agents push and open the PR themselves; CI does the rest.** Each session pushes and opens its PR. Agentic CI/CD then builds, tests, reviews the code, and fixes what the review found (possibly as stacked PRs). | Extends doc 13 §3–4: review and auto-fix become automatic on every PR, not only on a failed job. |
| R3 | Recording | **Auto-zoom in recordings.** Recordings get an auto-zoom capability. | Reverses doc 12 §2: “Auto-zoom recordings” was on the never-build list of rejected R&D ideas. |
| R4 | Recording | **Auto subtitles and captions, enhanced with AI.** Recordings get automatic subtitles/captions, perhaps enhanced with AI. | M13 (doc 12 §3) already commits to on-device captions from SpeechTranscriber. New: an optional Claude pass on the transcript, and captions treated as a core recording feature. |
| R5 | Collections | **Collections export as a designed presentation.** Instead of a plain document, collections become a beautiful HTML/PDF/doc presentation, like the pages Claude generates. | Replaces the M11 exporters' plain layout (doc 10). Uses Claude through the API, under the doc 13 §5 rules. |
| R6 | Guide | **Record Guide produces a video walkthrough.** The guide's outcome is a video flow with zoom-ins and text/captions explaining every action. Today's output, a vertical HTML/PDF of every step, is judged poor. | Changes the M11 guide recorder's primary output (doc 10). The step document becomes a secondary export at most. |

## 2. Proposal: one motion engine for zoom, captions and guide video

Auto-zoom (R3), captions (R4) and the guide video (R6) are one pipeline with three front doors. Build it once, as a shared motion engine, and the guide recorder becomes ‘a recording with step markers’ instead of a separate feature.

| Stage | Runs in | What it does |
|---|---|---|
| Event timeline | core | Timestamped clicks, keys (never typed text), cursor path, scrolls, window focus, and the AX element under each click. The recording overlays (click rings, keystrokes) and the guide recorder already capture most of this. |
| Zoom planner | core | Pure function from events to camera keyframes: zoom to click clusters and dwell points, ease in and out, hold a minimum time, follow the cursor while zoomed, stay wide during fast motion. Deterministic and Linux-testable. |
| Caption track | core | Timed caption cues from the on-device transcript, from step captions, or both. Line breaking (≤ 42 chars, ≤ 2 lines), timing, and SRT/VTT writers are pure code. |
| AI pass (opt-in) | Claude | Cleans the transcript (punctuation, filler, product names taken from the recording's OCR and AX text), writes action captions in prose, step titles, chapters and a summary. Sends text and small crops, never audio, after redaction. |
| Compositor | macOS | AVMutableComposition plus a video composition that applies the camera transform per frame and draws caption and step overlays from the core's display list. Burned-in or sidecar captions. |
| Timeline editor | macOS | Extends the trim window: zoom segments you can drag, delete or add; caption text you can edit; steps you can reorder or drop. Preview before export. |

### Auto-zoom (R3)

- Off, Auto, or Manual per recording; Auto plans zooms from the event timeline after recording ends, so capture stays cheap.
- Zoom segments appear in the timeline editor and can be adjusted before export; the default must look good with no edits.
- Settings: max zoom (e.g. 2×), ease duration, minimum hold. Respect a 1× external display: plan in points, render at the source's pixel scale.
- Risk: motion sickness from over-zooming. Keep zoom changes rare and smooth, and test on long real recordings, not just fixtures.

### Captions (R4)

- Local first: SpeechTranscriber word timings give a usable caption track offline, with no key (the doc 13 fallback rule).
- Claude pass, opt-in: fixes terms and punctuation using the recording's own vocabulary (OCR and AX text), splits into readable cues, proposes chapters.
- Silent recordings still get captions: action captions from the event timeline (“Click Save in the toolbar”), the same generator the guide uses.
- Export: burned-in, .srt or .vtt alongside, or off. This pulls M13's caption half forward; transcript-based cutting can stay in M13.

### Guide video (R6)

- Record Guide records continuous video; each click drops a step marker with its AX element and a crop.
- Output is an MP4: auto-zoom on each step, a caption card per step (“Step 3 · Open Settings”), optional title and outro cards written by Claude.
- Optional voice-over from the captions with on-device speech synthesis, so narration needs no network. Treat as a stretch goal.
- Chapters per step in the MP4. A secondary export renders the steps through the presentation engine (R5), not the old vertical page.
- Privacy rules stay: typed text and secure fields never reach captions, video overlays or Claude.

## 3. Proposal: collections as designed presentations (R5)

Claude composes, Bugeye renders. Claude returns a structured presentation spec (structured outputs, JSON schema) that picks layouts, writes titles, intros and captions, and orders content. A local renderer turns the spec into a self-contained HTML page or slides, and a PDF.

Why a spec rather than model-written HTML:

- Deterministic and testable: the spec is plain data, golden-tested on Linux; the renderer is tested once.
- Safe: no model-written script runs in the app or in exports.
- Works offline: without a key, a default layout renders the same spec shape from the collection as is.
- Consistent quality: a small set of curated themes and components looks designed every time.

Components: Title / cover, Image with numbered callouts, Before / after (pairs with M12), Step (image + caption), Text block, Code / log block, Comparison grid, Summary / next steps.

Outputs:

- Scrolling HTML page (single file, images embedded)
- Slides HTML (arrow keys)
- PDF (rendered by WebKit)
- Markdown stays as a plain fallback

Brainstorm question: allow a ‘freeform’ mode where Claude writes the HTML/CSS itself (closer to Claude's own artifacts, less predictable), sanitised to no script? Recommendation: ship the spec renderer first; add freeform only if the themes feel limiting.

## 4. Proposal: scoping for parallel cloud sessions (R1)

- **Contracts before code.** A serial Wave 0 lands every port, shared value type (PixelBuffer, display list, capture identity), and the CaptureFileWriter that preserves xattrs. Parallel sessions build against frozen contracts.
- **Features register themselves.** A FeatureModule protocol lets each feature add its menu items, hotkeys, settings pane and Quick Access actions. No session edits a shared AppDelegate or menu file.
- **Declare every target up front.** Wave 0 creates all SwiftPM targets (empty) in Package.swift, so feature branches never touch the manifest, the usual merge-conflict hotspot.
- **One directory per epic.** Each epic owns its targets and test folders. A CODEOWNERS-style map tells the reviewer when a branch strays outside its area.
- **Humans own the brainstorm and spec.** Brainstorm and spec approval stay with you (doc 11 §5). Plans, implementation, review and fixes run in parallel without you.
- **Small PRs, merge often.** Each epic lands as several PRs behind its own feature flag rather than one long-lived branch, which keeps parallel branches close to main.

| Wave | Mode | Epics |
|---|---|---|
| 0 | serial, 1 session | Package with all targets, ports and fakes; FeatureModule registry, settings store, CaptureFileWriter; PixelBuffer, display list, LLMClient + FakeLLM + Keychain; Tier 0/1 CI, fixture app, debug test channel |
| 1 | parallel, ~5 sessions | Capture + selection overlay state machine; Quick Access; Editor core (display list, tools, undo); Recording core (phase machine, event timeline); OCR word map + text map |
| 2 | parallel, ~5 sessions | Scrolling capture; Provenance + clipboard; Sensitive sweep; AX snapshot + exact text; Search index + Find Capture; Trim + GIF |
| 3 | parallel, ~4 sessions | Motion engine: zoom planner + compositor (R3); Caption track + AI pass (R4); Presentation engine (R5); Collections |
| 4 | parallel, ~4 sessions | Guide video (R6); M12 before/after diff; Bug report composer; Copy for AI browser logs |

Wave contents follow the README build order and the doc 12 dependencies; the exact split is for the first brainstorm.

## 5. Proposal: the PR pipeline (R2)

1. **Session works.** A cloud session implements its plan task with TDD and keeps Tier 0 (Linux build and tests) green.
2. **Push + open PR.** The session pushes feat/<epic>-<slice> and opens a draft PR linked to its issue, then watches the PR for activity.
3. **Tier 1 CI.** Hosted macOS runner: full build, all unit tests, rasterisation goldens, CLT-only build check. The PR leaves draft when green.
4. **Claude review.** A fresh reviewer reads the whole diff with the doc 11 bug-class checklist and posts findings as review comments.
5. **Auto-fix.** The authoring session fixes Critical and Important findings as new commits, each with a test that fails first. Large or disputed fixes go to a stacked PR onto the feature branch.
6. **Re-review.** The reviewer checks only the delta. After two fix rounds without convergence it hands the PR to you.
7. **Tier 2 E2E.** Self-hosted Mac runner: smoke tests, scenario runs on the fixture app, screenshots and a short demo video attached to the PR.
8. **You merge.** Your manual pass (feel and taste only) and merge through a merge queue. Docs and CLAUDE.md update in the same merge.

- Recommendation: fix commits on the same branch by default (the reviewer sees a small delta); stacked PRs only for large or contested fixes. Stacks multiply rebases when several sessions run at once.
- Loop limits: two auto-fix rounds per PR and one CI-fix attempt per failure, then a human (doc 13 guardrail).
- Cost: Anthropic's managed Code Review averages $15–25 per review by its own figures; the Claude Code GitHub Action is lighter. Use the deep review on milestone PRs and the light one on slices.

## 6. More agentic coding ideas

| Area | Idea | How | Mechanism |
|---|---|---|---|
| Orchestration | Spec-to-issues planner | After you approve a plan, an agent turns each task into a GitHub issue with sub-issues, dependency links and a wave label. | gh-aw workflow (create-issue safe output) |
| Orchestration | Dispatcher session | One session reads the issue graph and starts a cloud session for every unblocked issue, each on its own branch and subscribed to its PR. You watch one board instead of many terminals. | Cloud session + create_session |
| Orchestration | Merge queue with rebasing agent | PRs enter a merge queue; when one conflicts after another merges, an agent rebases it and re-runs Tier 0 before asking for a human. | GitHub merge queue + Claude Code Action |
| Quality | Bug-class guards | Turn doc 11 §6 into deterministic checks: no atomic writes outside CaptureFileWriter, no AX or Vision calls on the main actor, no layout with zero width, text-entry roles never reach captions. They run in Tier 0, before any model reads the code. | Custom lint step in CI |
| Quality | Specialist reviewers | Separate review prompts for concurrency, privacy and redaction, xattr preservation, and ‘strings match the spec’. Each posts only findings in its lens, so nothing gets drowned out. | gh-aw (engine: claude) or Claude Code Action |
| Quality | Spec reviewer | Before planning, a fresh agent reads the spec for unsettled user-visible strings, missing error states and untestable claims. This is the cheapest place to catch the doc 11 ‘settle every string’ lesson. | Claude Code Action on spec PRs |
| Quality | Flake hunter | When a test fails then passes, an agent reruns it N times on the same commit, records the failure rate, and opens a quarantine issue with the data, never a silent skip. | gh-aw scheduled workflow |
| Dogfooding | Bugeye files its own bugs | Point the bug report composer (RD-08) at the bugeye repo: a hotkey files a GitHub issue with screenshot, source and env. A triage agent labels it and the dispatcher starts a fix session. | RD-08 + gh-aw triage |
| Dogfooding | Every PR ships a demo video | On Tier 2, the guide recorder (R6) records the new feature running in the fixture app and attaches the captioned, zoomed MP4 to the PR. Your review starts by watching it. | Tier 2 runner + Bugeye itself |
| Dogfooding | Visual diffs with M12 | UI changes get before/after screenshots from the fixture app, compared with Bugeye's own diff engine, posted on the PR. | Tier 2 runner + M12 |
| Maintenance | Nightly triage | Labels new issues by severity, groups duplicates, proposes the next fix batch from docs/backlog.md. Never closes your issues. | gh-aw scheduled (add-labels, add-comment) |
| Maintenance | Docs gardener | On each merge, updates CLAUDE.md, the code map, the affected design doc, and regenerates this atlas's data, then opens a PR. | gh-aw on push to main (create-pull-request) |
| Maintenance | Checklist writer | From the spec and the merged diff, writes your manual checklist in the doc 11 format, limited to what agents could not verify. | Claude Code Action |
| Maintenance | Toolchain bumps | When a new Swift 6.x lands, an agent bumps .swift-version, runs Linux and macOS tiers, and fixes or reports breakage. | gh-aw scheduled |
| AI quality | Eval suite for Claude features | A fixed set of captures, recordings and collections; nightly, the features run against the real API and a grader scores captions, guide titles and presentations against a rubric. A drop opens an issue. | Opt-in CI job with an API secret |
| AI quality | Weekly cost report | Summarises tokens and dollars per workflow and per feature, and flags loops that hit their limits. | gh-aw scheduled (create-issue) |

### GitHub Agentic Workflows, in brief

- gh-aw workflows are Markdown files with frontmatter (trigger, engine, tools, network, safe outputs), compiled to Actions lock files with `gh aw compile`.
- `engine: claude` runs Claude Code as the agent. The agent job is read-only and sandboxed by default; writes (issues, comments, PRs, labels) are declared as safe outputs and applied by separate, scoped jobs.
- Strict mode rejects workflows that ask for write permissions directly, which fits the Tier 2 safety rules in doc 13.
- Status: secondary sources date general availability to 28 October 2026; confirm in the GitHub changelog before relying on it.

Sources:

- [github/gh-aw](https://github.com/github/gh-aw)
- [gh-aw: Using Claude Code](https://github.github.com/gh-aw/engines/claude/)
- [gh-aw: Safe outputs (pull requests)](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)
- [Anthropic: Bringing Code Review to Claude Code](https://claude.com/blog/code-review)
