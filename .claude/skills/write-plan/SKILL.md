---
name: write-plan
description: "Turn an approved spec into a TDD implementation plan in docs/plans/ with exact code, verified in a scratch package first, and a Review Focus section. Use when a spec is approved and needs a plan."
---

# Write a plan

File: `docs/plans/YYYY-MM-DD-<topic>.md`. Model: `docs/plans/2026-11-27-wave-0-skeleton.md`. A fresh session with no other context executes it task by task, so it must stand alone.

1. **Draft the code first.** Write every portable target's code and tests in a scratch package outside the repo and get `swift build`, `swift test`, `make lint` and `make guards` green on Linux. The code in the plan is code you compiled and ran. macOS-only code can't compile on Linux: write it conservatively and mark its task "Not compiled here: verified by the macos CI job".
2. **Header:** goal, spec link, branch (`feat/<wave>` from `main`), ledger path (`docs/ledgers/<wave>.md`), commit trailers, and when to open the draft PR.
3. **Facts:** what you checked (versions, runner images, API shapes) with source URLs.
4. **Plan rulings** `P1`…: every gap or ambiguity you decided, each with its cost if wrong. Decide; don't ask.
5. **Steps only the user can do:** secrets, repository settings, the Mac. Say at which task each is needed and what the executing session does if it isn't done (keep going, ledger it).
6. **Tasks**, numbered, small, ordered so CI exists early. Each code task: Goal · Files · Step 1 failing test (exact code) · Step 2 command and expected failure · Step 3 implementation (exact code) · Step 4 command and expected pass · Step 5 commit message. Content-only tasks give the full file text.
7. **Review Focus:** the input classes and risks the tests don't exercise, for the final reviewer.

Rules: exact code, no "similar to above"; every user-visible string copied from the spec; tests that can fail; no scope beyond the spec. Ask the user to approve the plan before execution.
