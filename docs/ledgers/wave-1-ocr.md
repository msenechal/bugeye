# Wave 1 OCR ledger

Plan: `docs/plans/2026-11-28-wave-1-ocr.md` · Spec: `docs/specs/2026-11-27-wave-1-ocr.md` · Branches: `feat/wave1-ocr-{core,reader,store,wiring}`

Trust this file and `git log` over memory.

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 6287f57 | contracts PR #3 merged; §3's names checked against `main` (`44a44d9`); draft PR #5 |
| 2 | done | 6edf604 | |
| 3 | done | cca6832 | |
| 4–5 | done | 2c694fc | |
| 6 | done | aaeebc5 | |
| 7 | done | 88585d7 | |
| 8 | done | 89e4238 | see ruling |
| 9 | done | ec94103 | slice 1 code complete; `make test-core lint guards ownership` green |
| 10 | done | (see rulings) | fresh final review of slice 1: 0 Critical, 2 Important, 7 Minor; fix pass below |

## Rulings

Plan rulings P1–P14 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: `TextMapBuilder` drops a word that overlaps **any** kept word (not only the previous one) and then sorts the kept words by range, so words the recogniser returned out of order are kept in order rather than dropped (§4.1 step 5 says only overlapping words are dropped). (cost if wrong: none.)
- Ruling: Task 8's `mapped` tests and code were written in one step, so they were not seen failing first (the method didn't exist, so they could not have compiled); each assertion compares against hand-computed boxes. Every other task ran red first. (cost if wrong: low.)
- Ruling: find compares folded Unicode scalars, not `String`s, so the match never depends on Swift's canonical-equivalence `String` comparison across the fold's concatenation (§4.4: "portable and identical on Linux and macOS"). (cost if wrong: none.)

- Ruling (slice 1 final review I1, I2, Important): both findings were untested spec rules, not bugs, so their new tests (2.5 → 3 spaces; indentation from the leftmost row, not the first) pass on the correct code. Each was seen failing against the mutant the review named (`.toNearestOrEven`; `rowMinX.first`) before being committed. (cost if wrong: none.)
- Ruling (slice 1 final review M1, M3, M6, Minor): fixed in the fix pass because each was a line or two: unboxed slices are tested with the line off x = 0 (seen failing on the mutant); `summary` splits on any newline (`\r\n` is one `Character`) and its tab trimming is tested (seen failing first); `union` became an internal `Rect2D` method. The other Minor findings are under `Backlog:`. (cost if wrong: none.)
- Ruling (PR #5 claude-review, Minor): `TextLayout.lines` indents nothing when the median character width is under 1 px (`TextLayout.minimumCharacterWidth`), instead of §4.6's "none if `charWidth ≤ 0`": a bad recogniser result could otherwise make tens of thousands of spaces per row. No real text is narrower than 1 image pixel per character. Test failed first. (cost if wrong: none.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before PR 4 (wiring) can merge and its Mac batch can run (contracts §9).

## Backlog

- (PR #5 review M2, 28 Nov 2026) `FindTests`: `emojiAndCombiningMarksCountAsOneCharacter` has no uncomposable combining mark (add `q\u{301}` found by `q`); `aMatchOfOnlySpacesInsideTheLineIsSkipped` only exercises the whitespace-query guard (the nil-box skip looks unreachable); a hand-built line with decomposed text matched by a precomposed query is untested.
- (PR #5 review M4) A line starting with a stray combining mark (`"\u{301}ab"`) makes `matches(of: "ab")` return `0..<3`: characters that fold to nothing are absorbed at a run's start. Follows the spec's wording; at most a comment.
- (PR #5 review M5) `eventually` (test helper) polls with real 1 ms sleeps; it is used from slice 2 on.
- (PR #5 review M7) `FakeTextReaderTests` waits with unbounded `while … { await Task.yield() }` loops; a broken fake would hang the test instead of failing it.
