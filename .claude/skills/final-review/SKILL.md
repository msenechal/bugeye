---
name: final-review
description: "Do the one fresh, whole-branch final review of a wave or feature branch and sort findings into Critical, Important and Minor. Use after execution finishes, in a fresh session, or when asked for a final review."
---

# Final review

The final review found real Critical bugs in a fully green suite in every milestone of the first build. Never skip it. Do it in a fresh session with no memory of writing the code.

1. Read `CLAUDE.md`, the spec, the plan (especially its Review Focus) and the ledger's rulings.
2. Read the **whole** branch diff against `main` (`git diff main...HEAD`), not just the last commits, and the code around it.
3. Check, at least:
   - the spec: every behaviour and every user-visible string, character for character;
   - the `design/11` §6 bug classes: attributes lost outside `CaptureFileWriter`, late async results, windows without a size, slow calls on the main thread, name clashes, typed text leaking;
   - the `CLAUDE.md` rules and `make guards`;
   - tests: each one can fail, tests what it claims, uses its own temp folder, doesn't spin the run loop;
   - concurrency: `Sendable`, actor isolation, `@unchecked` uses justified;
   - security: secrets only in the Keychain, workflows limited to this repository's branches with minimal permissions;
   - the plan's Review Focus items one by one.
4. Write findings as **Critical** (wrong behaviour, data loss, security), **Important** (likely bug, missing test for a risky path, spec deviation) or **Minor** (clarity, small cleanups). Each with file:line, the problem, why it matters and a concrete fix.
5. Post them on the PR (one comment per finding where possible, plus a summary).
6. **Fix pass:** each Critical and Important finding gets a test that fails first, then the fix, one commit each. Minor findings go to `docs/backlog.md` with a date and the PR number.
