# 14 — Direction changes and agentic proposals

Feedback from the user after the first read of the design docs, and proposals that follow from it. **Rulings** (§1) are the user's decisions and override earlier docs where they conflict. Everything else is a **proposal** for the next brainstorm, not a decision.

_Round 1 + 2 · November 2026 · from the user's review of the dashboard_

## 1. Rulings from the user

| # | Area | Ruling | What it changes |
|---|---|---|---|
| R1 | Development | **Parallel cloud sessions, one branch per epic.** Epics and features are scoped so several Claude cloud sessions can implement them at the same time, each on its own branch. | Doc 11 §5 ran execution inline in one session; doc 13 §4 already had the Implementer role push a branch. Now the plan must be cut for parallel work. |
| R2 | Development | **Agents push and open the PR themselves; CI does the rest.** Each session pushes and opens its PR. Agentic CI/CD then builds, tests, reviews the code, and fixes what the review found (possibly as stacked PRs). | Extends doc 13 §3–4: review and auto-fix become automatic on every PR, not only on a failed job. |
| R3 | Recording | **Auto-zoom in recordings.** Recordings get an auto-zoom capability. | Reverses doc 12 §2: “Auto-zoom recordings” was on the never-build list of rejected R&D ideas. |
| R4 | Recording | **Auto subtitles and captions, enhanced with AI.** Recordings get automatic subtitles/captions, perhaps enhanced with AI. | M13 (doc 12 §3) already commits to on-device captions from SpeechTranscriber. New: an optional Claude pass on the transcript, and captions treated as a core recording feature. |
| R5 | Collections | **Collections export as a designed presentation.** Instead of a plain document, collections become a beautiful HTML/PDF/doc presentation, like the pages Claude generates. | Replaces the M11 exporters' plain layout (doc 10). Uses Claude through the API, under the doc 13 §5 rules. |
| R6 | Guide | **Record Guide produces a video walkthrough.** The guide's outcome is a video flow with zoom-ins and text/captions explaining every action. Today's output, a vertical HTML/PDF of every step, is judged poor. | Changes the M11 guide recorder's primary output (doc 10). The step document becomes a secondary export at most. |
| R7 | Collections | **Claude writes the presentation's HTML/CSS itself.** Freeform: Claude writes its own HTML/CSS, in the style of its artifacts. Not deterministic and hard to test, and that's fine: test that it generates something, and have a small agent score the output against the inputs. | Settles the R5 open question against the spec-renderer recommendation. Testing moves from golden outputs to structural checks plus an AI judge score. |
| R8 | Development | **No paid CI runners.** No GitHub-hosted macOS runner and no self-hosted runner: you don't have them and don't want to pay for them. | Replaces doc 13 §3 Tiers 1 and 2. Private repo: CI on GitHub is Linux only. Public repo (you don't mind switching): free hosted macOS brings back the macOS build and unit tests. Either way, real-capture smoke tests, E2E and demos run on your own Mac, on demand, with your approval. |
| R9 | Development | **Work from the phone with the Mac off.** You will sometimes start dev sessions from your phone while your Mac is off. | Nothing in the per-PR pipeline may wait on your Mac. macOS checks on PRs come from hosted runners (free if the repo is public); real-capture checks queue up and run in a batch when the Mac is back. A self-hosted runner doesn't help: it needs the same Mac to be on. |

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

## 3. Collections as designed presentations (R5, R7)

Claude designs each export as a complete, self-contained HTML document, in the style of its artifacts: its own layout, type and CSS, optional inline script for slide navigation. Bugeye's job shrinks to preparing the inputs, locking the output down, checking it, and printing it to PDF.

| Step | What happens |
|---|---|
| Prepare | Run the M8 sweep and blur findings; downscale images; collect text blocks and captions. Images go to Claude once, as images, and come back only as placeholders (img-1.png …). |
| Generate | One Claude call with a cached design brief (the style you like) plus an optional style hint: report, keynote, onboarding guide, dark. Long output streams. |
| Lock down | Swap placeholders for the real embedded images, strip any external URL, and inject a Content-Security-Policy that blocks all network access. Whatever Claude wrote, the file can't load or send anything. |
| Check | Structural checks, then a small judge model scores it (below). A failed check retries once with the error, then falls back to the plain local layout. |
| Show and export | In-app preview in a WebKit view with networking off. Export the HTML file, a PDF printed by WebKit, or both. ‘Adjust…’ takes a short note (‘more minimal’, ‘bigger images’) and regenerates from the previous version. |

Structural checks (the ‘it generated something’ test):

- Parses as HTML and stays under a size cap.
- Every input image placeholder is used; no image is invented.
- No external URLs after lock-down; the CSP is present.
- Renders in WebKit with no script errors; the PDF has at least one page.
- Text from the collection appears in the page (fuzzy match).

Judge criteria:

- **Fidelity:** All images and text are present, captions match their images, nothing is invented.
- **Privacy:** Nothing the sweep blurred is readable; no typed text appears.
- **Legibility:** Contrast, text size, nothing clipped or overlapping, in a screenshot of the render.
- **Design:** Hierarchy, consistency, fits the requested style.

A cheaper model (a setting, e.g. Haiku) gets the inputs, the final HTML and screenshots of the render, and returns a structured score per criterion (0–10) with one-line reasons. In the app, a low fidelity or privacy score regenerates once, then warns. In CI, a nightly eval over a fixed set of collections tracks the average; a drop opens an issue.

Tests: On Linux: the sanitiser, CSP injection, placeholder swap, size cap and judge-score parsing, all with FakeLLM fixtures. On your Mac: WebKit rendering and PDF. Real-API evals run on demand.

Fallback: With no key, offline, or after a refusal or two failed checks: the plain local layout (today's M11 exporter, tidied up). The guide's secondary export (R6) uses the same pipeline.

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

1. **Session works.** A cloud session implements its plan task with TDD and keeps Tier 0 (Linux build and tests in the session) green.
2. **Push + open PR.** The session pushes feat/<epic>-<slice>, opens a draft PR linked to its issue, and watches it.
3. **GitHub CI.** Linux job: build and test the portable core, format, lint and the bug-class guards. If the repo is public, a free macOS job also builds the app and runs every unit test, including AppKit view models and render goldens.
4. **Claude review.** A fresh reviewer session reads the whole diff with the doc 11 checklist and posts findings.
5. **Auto-fix.** The authoring session fixes Critical and Important findings as commits, each with a test that fails first.
6. **Re-review.** The reviewer checks the delta. After two rounds without convergence it hands the PR to you.
7. **Queue the Mac check.** PRs that touch capture, Accessibility, overlays or recording get a needs-mac-check label. They can still merge once GitHub CI is green: nothing waits for your Mac.
8. **You merge.** From your phone if you like: read the review, watch the demo if there is one, merge. Your manual pass (feel and taste) happens per milestone, at the Mac.
9. **Batch at the Mac.** When your Mac is on, one session asks to use your bugeye folder through Remote Control. You approve once; it works through every needs-mac-check PR, runs smoke tests and E2E on the fixture app, records demos, and opens fix PRs for anything that broke. A milestone isn't done until its queue is empty.

- Fix commits on the same branch by default; stacked PRs only for large or contested fixes.
- Loop limits: two auto-fix rounds per PR and one CI-fix attempt per failure, then you.
- The Mac batch is the only step that needs your Mac, and it gates milestones, not PRs. Your Mac answers only while the Claude app is running there.
- Trade-off: real-capture bugs (permissions, ScreenCaptureKit, Accessibility timing) can reach main and surface at the next Mac batch. Fix PRs from the batch keep that window short; keeping the macOS shell thin keeps it small.
- If the repo stays private, PRs get no macOS check at all until the Mac batch, so AppKit compile errors also wait. That's the main argument for going public.

## 5b. CI without paid runners (R8, R9)

What the terms mean:

- **GitHub-hosted runner.** A virtual machine GitHub starts for each CI job. Linux, Windows and macOS are offered. Free for public repos; bugeye is private, so jobs spend a small monthly credit and then cost money. macOS is about ten times the price of Linux ($0.062 vs $0.006 per minute).
- **Self-hosted runner.** GitHub's runner program installed on a machine you own (here, your Mac), which then picks up CI jobs from the repo. No GitHub fee by most sources (a planned per-minute fee was postponed), but it runs repo code automatically under your account and needs a dedicated macOS user to be safe.
- **Why doc 13 wanted them.** A macOS app can't be built on Linux. Something with macOS must compile the app target and run AppKit, ScreenCaptureKit and Accessibility tests.

| Option for macOS checks | Verdict | Cost | How |
|---|---|---|---|
| Make the repo public: GitHub-hosted macOS free | Recommended | Free (public repos) | Standard GitHub-hosted runners, macOS included, cost nothing on public repos. It's the only free option that works with your Mac off: macOS build and unit tests on every PR, started from your phone. Real capture is assumed not to work there (permissions can't be granted through the normal prompts); worth one experiment, since GitHub's macOS images do preconfigure some permissions. |
| Your Mac through Remote Control | For real capture, batched | Free | A cloud session asks to use your bugeye folder on your Mac; you approve each time; it runs the checks there and reports back. No runner to install or secure, and nothing runs without you. |
| A local Claude Code session on your Mac | Fallback | Free | You start a session on the Mac and run a /verify-pr command that checks out the PR, runs the checks and comments. The same work, triggered by you. |
| Self-hosted runner on your Mac | Doesn't help | Free, more setup | It runs on the same Mac, so it's down whenever the Mac is. It also must never be attached to a public repo. |
| GitHub-hosted macOS runner, private repo | Not used | Paid | Excluded by R8. |

What costs money:

- GitHub, private repo: Linux CI only, within the free monthly allowance for short jobs. Public repo: standard Linux and macOS runners are free.
- Claude reviews and fixes run as cloud sessions on your Claude plan. Running them inside GitHub Actions (Claude Code Action, gh-aw) needs an API key billed per token, or a subscription token if the action accepts one: check before adopting.
- In-app AI features (presentations, captions, guide prose, the judge) call the API with your key and cost tokens. The judge uses a cheaper model.

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
| Dogfooding | Every PR ships a demo video | On Tier 2, the guide recorder (R6) records the new feature running in the fixture app and attaches the captioned, zoomed MP4 to the PR. Your review starts by watching it. | Mac check + Bugeye itself |
| Dogfooding | Visual diffs with M12 | UI changes get before/after screenshots from the fixture app, compared with Bugeye's own diff engine, posted on the PR. | Mac check + M12 |
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
- [GitHub Changelog: update to Actions pricing](https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/)
- [GitHub Actions pricing changes 2026 (postponed self-hosted fee)](https://cicdcost.com/github-actions-pricing-changes-2026)
