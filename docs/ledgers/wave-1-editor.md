# Wave 1 Editor ledger

Plan: `docs/plans/2026-11-28-wave-1-editor.md` · Spec: `docs/specs/2026-11-27-wave-1-editor.md` · Contract: `docs/specs/2026-11-27-wave-1-contracts.md`

Trust this file and `git log` over memory.

## Pull requests

| Slice | Branch | PR | State |
|---|---|---|---|
| A executor | `feat/wave1-editor-executor` | https://github.com/msenechal/bugeye/pull/7 | draft; final review done |
| B core | `feat/wave1-editor-core` | | |
| C app | `feat/wave1-editor-app` | | |
| D wiring | `feat/wave1-editor-wiring` | | |

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 065188c | plan and ledger; draft PR #7 |
| 2 | done | edd00d2, 12783ca | not compiled here; macOS run 46121444277 failed to compile a nested `#require` (fixed 12783ca); run 46121832947 green |
| A review | done | (see rulings) | fresh final review: 0 Critical, 1 Important, 9 Minor |

## Rulings

Plan rulings P1–P13 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: the contracts' §3 names were checked against `main` at `44a44d9` before the first PR (spec §9 item 1); all exist with the shapes the spec lists. (cost if wrong: none.)

- Ruling (final review A, Important 1): a probe test draws into a context set up like a flipped `NSView` (y down, at 1× and 2×) with `contextIsFlipped: true`: fill, image, text and shadow land the right way up, and the text matrix is restored. (cost if wrong: none.)
- Ruling (final review A, Minors 1, 2, 3, 4, 7): fixed in the fix pass because the executor's API freezes once merged (E11): `execute` restores the text matrix and text position; `contextIsFlipped` has no default, so a flipped caller can't forget it, and the doc states the list must span a y-up context's height; `render` returns nil for non-finite or over-65 536 px sizes and falls back to sRGB for a non-RGB or non-output space (tested); a `clip` outside a group is documented as ignored. (cost if wrong: none.)
- Ruling (final review A, Minor 5): the text probe keeps its loose width bound (ink between 0.8 × and the measured width + 1 px) instead of the plan's "within 1 px": ink bounds exclude the side bearings that `CTLineGetTypographicBounds` includes, so an exact match would test Core Text, not the executor. Font agreement is by construction: both call `CoreTextFonts.font(for:)`. (cost if wrong: low.)
- Ruling (final review A, Minor 8): the executor calls the blur provider synchronously; slice C's canvas provider returns a cached result or nil and computes off the main actor. (cost if wrong: none.)

- Ruling (claude-review A, Important): nested group opacities now multiply. The executor keeps a stack of effective alphas, and an isolated group's children start again from 1 inside its layer, as Core Graphics resets alpha in a transparency layer. A nested group's shadow replaces its parent's for the drawing inside it (documented). Probe tests cover 0.5 inside 0.5 (non-isolated and isolated inner group) and an isolated parent. They can't be seen failing on Linux; the macOS job is the check. (cost if wrong: none.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before slice D merges and before the manual pass (contracts §9).

## Backlog

- Executor tests: a non-isolated group's single-fill alpha, line joins, a vertical gradient (final review A, Minor 6).
