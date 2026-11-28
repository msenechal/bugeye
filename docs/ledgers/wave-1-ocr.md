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

## Rulings

Plan rulings P1–P14 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: `TextMapBuilder` drops a word that overlaps **any** kept word (not only the previous one) and then sorts the kept words by range, so words the recogniser returned out of order are kept in order rather than dropped (§4.1 step 5 says only overlapping words are dropped). (cost if wrong: none.)
- Ruling: Task 8's `mapped` tests and code were written in one step, so they were not seen failing first (the method didn't exist, so they could not have compiled); each assertion compares against hand-computed boxes. Every other task ran red first. (cost if wrong: low.)
- Ruling: find compares folded Unicode scalars, not `String`s, so the match never depends on Swift's canonical-equivalence `String` comparison across the fold's concatenation (§4.4: "portable and identical on Linux and macOS"). (cost if wrong: none.)

## Waiting on

- Capture's and Quick Access's wiring PRs, before PR 4 (wiring) can merge and its Mac batch can run (contracts §9).

## Backlog

Nothing yet.
