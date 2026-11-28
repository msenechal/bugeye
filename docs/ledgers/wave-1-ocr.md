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
| 10 | done | (see rulings) | fresh final review of slice 1: 0 Critical, 2 Important, 7 Minor; fix pass below; PR #5 marked ready |
| 11 | done | 7900a39 | branch `feat/wave1-ocr-reader`, stacked on PR #5 |
| 12 | done | 0217667 | |
| 13–14 | done | 872f26a | bilinear expectations computed independently (floating point, round half up) |
| 15 | done | 8efe060 | |
| 16 | done | 7438a05 | goldens generated with `BUGEYE_UPDATE_GOLDENS=1` and checked by eye |
| 17 | done | (see rulings) | fresh final review of slice 2: 0 Critical, 2 Important, 8 Minor; all fixed in the fix pass |
| 18 | done | 30b7c56 | branch `feat/wave1-ocr-store`, stacked on the reader branch |
| 19 | done | 00bf617 | 27 tests, one or more per Q1–Q9; 25 repeated runs without a failure |
| 20 | done | 8a03fdd | |
| 21 | done | 0daf33a | slice 3 code complete |
| 23–25 | done | see `git log` | branch `feat/wave1-ocr-wiring`; not compiled here, the `macos` job is the check |

## Rulings

Plan rulings P1–P14 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: `TextMapBuilder` drops a word that overlaps **any** kept word (not only the previous one) and then sorts the kept words by range, so words the recogniser returned out of order are kept in order rather than dropped (§4.1 step 5 says only overlapping words are dropped). (cost if wrong: none.)
- Ruling: Task 8's `mapped` tests and code were written in one step, so they were not seen failing first (the method didn't exist, so they could not have compiled); each assertion compares against hand-computed boxes. Every other task ran red first. (cost if wrong: low.)
- Ruling: find compares folded Unicode scalars, not `String`s, so the match never depends on Swift's canonical-equivalence `String` comparison across the fold's concatenation (§4.4: "portable and identical on Linux and macOS"). (cost if wrong: none.)

- Ruling (slice 1 final review I1, I2, Important): both findings were untested spec rules, not bugs, so their new tests (2.5 → 3 spaces; indentation from the leftmost row, not the first) pass on the correct code. Each was seen failing against the mutant the review named (`.toNearestOrEven`; `rowMinX.first`) before being committed. (cost if wrong: none.)
- Ruling (slice 1 final review M1, M3, M6, Minor): fixed in the fix pass because each was a line or two: unboxed slices are tested with the line off x = 0 (seen failing on the mutant); `summary` splits on any newline (`\r\n` is one `Character`) and its tab trimming is tested (seen failing first); `union` became an internal `Rect2D` method. The other Minor findings are under `Backlog:`. (cost if wrong: none.)
- Ruling: `PixelResample.rows` throws `PixelBuffer.Error.emptySize` when no row is left, instead of silently returning something; `TextMapReader` only ever passes non-empty strips. (cost if wrong: none.)
- Ruling: `TextMapReader` checks cancellation again **after** `beforeStrip`, not only before it, so a cancellation that arrives while the hook awaits (the store's URL check, Q5b) stops the read before decoding the strip. The test that found this failed first. (cost if wrong: none.)
- Ruling: `TextMapError` is `CustomStringConvertible` with the log texts of plan P9 now (slice 2), since the reader throws it; its test was written with the code, not run red first. (cost if wrong: low; each assertion is a literal from P9.)
- Ruling: the hand-made `french` fixture leaves its second word (`vu,`) unboxed, so the goldens cover a word Vision couldn't box; `label-fields` uses `user@example.com`, no personal data. (cost if wrong: none.)
- Ruling (slice 2 review I1, Important): the strip timeout races the recogniser in its own unstructured task instead of a task group, because a group waits for every child: a recogniser that ignores cancellation (Vision's `perform` may) would have held the read, and the store's single read slot, forever. On timeout the recogniser task is cancelled and **left to finish on its own**; its late result is ignored. An outer cancellation still surfaces as `CancellationError`, even if the timer already fired (M4). Tests with a stubborn reader failed first. (cost if wrong: low; a stuck Vision call keeps a CPU core busy until it returns, but no read waits on it.)
- Ruling (slice 2 review I2, Important; **deviates from spec §5.3.1**): a line that starts in a strip's top band and ends below it replaces only kept lines it overlaps **and is on the same line with** (§4.2's `sameLine`: vertical overlap ≥ half the smaller height). The spec's "every kept line it intersects" removed a neighbouring line that touched it by a few pixels, and that line's own copy in the band had already been dropped, so it vanished from the map. Vision boxes of tightly spaced text (terminals, code) often overlap by 1–3 px. Test failed first. (cost if wrong: low; a cut line that overlaps its own uncut copy by less than half its height would be kept twice.)
- Ruling (slice 2 review M1–M8, Minor): all fixed: the band-drop and band-edge rules have a test that kills their mutants; the timeout is shown to be per strip; `enlarged2x` traps instead of returning the 1× buffer; the clock tests wait with a bound; the fingerprint test is named for the sub-microsecond step `Date` can hold; the traceback fixture's caret line is the real one (14 carets at column 11) and its goldens were regenerated. (cost if wrong: none.)
- Ruling (PR #5 claude-review, Minor): `TextLayout.lines` indents nothing when the median character width is under 1 px (`TextLayout.minimumCharacterWidth`), instead of §4.6's "none if `charWidth ≤ 0`": a bad recogniser result could otherwise make tens of thousands of spaces per row. No real text is narrower than 1 image pixel per character. Test failed first. (cost if wrong: none.)
- Ruling: the store's read runs in a `@concurrent` static function, so it leaves the actor explicitly (T9) rather than relying on the default for `nonisolated async`, which a later language-mode change (`NonisolatedNonsendingByDefault`) would flip. `LatestReading` does the same. (cost if wrong: none.)
- Ruling: `saved` and `moved` for a capture that is only cached don't evict its map: a rename keeps the file's size and modification date, so the fingerprint still matches and the map is still right; `map(for:)` checks the fingerprint at the new URL anyway. `edited` for a capture the store has never seen is ignored, like the bus's own mirror (contracts plan P5). (cost if wrong: none.)
- Ruling: the Q5b strip check (`checkURL`) has no public path that reaches it without an event having cancelled the read first (every URL change arrives through `handle`, on the same actor), so it is tested directly; likewise the `dropped <id>: gone` branch of Q6 is kept as a guard but can't be reached while `deleted` cancels the running read. (cost if wrong: none.)
- Ruling: `TextServices` drains its stream in a detached task, and an `isolated deinit` cancels the subscription and the task. (cost if wrong: none.)
- Ruling: the tests that run Vision and ImageIO **through `TextMapReader`** (a 1× image's boxes within 8 px, the 8,200 px overlap read once, the `BUGEYE_RECORD_OCR` recorder) and the wiring test live in `Tests/BugeyeAppTests/Text/`, not `Tests/MacAdaptersTests/`: `MacAdaptersTests` depends only on `MacAdapters` and `BugeyeTestSupport`, so it can't import `TextCore`, and `Package.swift` is contract. Both folders are OCR's. The Core Text drawing helper is duplicated in the two test targets for the same reason. (cost if wrong: none.)
- Ruling: the word-box test checks each word's left and right edges within 4 px of Core Text's offsets, and that the box covers the line's ink vertically within 4 px, rather than ±4 px on all four sides: Vision boxes a word to the line's height, while the ink of `me` is shorter than that of `Remember`. (cost if wrong: low; the Mac batch checks boxes over real captures.)
- Ruling: `TextWiring` logs `failed` lines at `.error` and every other line at `.notice` (so `log show` keeps them without `--info`), all `privacy: .public` since they hold only ids, sizes and timings (§6). (cost if wrong: none.)
- Ruling: `ImageIOFileReader` takes its fingerprint from `URLResourceValues` (`fileSize`, `contentModificationDate`) after clearing cached values; `Date` keeps the modification time to about 240 ns, which is enough because every `CaptureFileWriter` rewrite renames a new file into place. (cost if wrong: low.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before PR 4 (wiring) can merge and its Mac batch can run (contracts §9).

## Backlog

- (PR #5 review M2, 28 Nov 2026) `FindTests`: `emojiAndCombiningMarksCountAsOneCharacter` has no uncomposable combining mark (add `q\u{301}` found by `q`); `aMatchOfOnlySpacesInsideTheLineIsSkipped` only exercises the whitespace-query guard (the nil-box skip looks unreachable); a hand-built line with decomposed text matched by a precomposed query is untested.
- (PR #5 review M4) A line starting with a stray combining mark (`"\u{301}ab"`) makes `matches(of: "ab")` return `0..<3`: characters that fold to nothing are absorbed at a run's start. Follows the spec's wording; at most a comment.
- (PR #5 review M5) `eventually` (test helper) polls with real 1 ms sleeps; it is used from slice 2 on.
- (PR #5 review M7) `FakeTextReaderTests` waits with unbounded `while … { await Task.yield() }` loops; a broken fake would hang the test instead of failing it.
