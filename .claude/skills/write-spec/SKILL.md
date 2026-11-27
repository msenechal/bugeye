---
name: write-spec
description: "Write a wave or feature spec in docs/specs/ in the house shape, with every user-visible string settled. Use after a brainstorm, or when asked to write or revise a spec."
---

# Write a spec

File: `docs/specs/YYYY-MM-DD-<topic>.md`. Model: `docs/specs/2026-11-27-wave-0-skeleton.md`.

Sections, in order:
1. **Title and status line:** status (draft for approval / approved), date, the process line.
2. **Decisions:** a table of the brainstorm answers (`B1`…), then a table of your rulings (`W1`…) with *why* and *cost if wrong* in brackets.
3. **Scope:** numbered in-scope items, then an explicit out-of-scope sentence.
4. **Layout and targets** when files or targets change. Feature branches never edit `Package.swift`; if a target is missing, say so here.
5. **Behaviour:** what the user sees and does. **Every user-visible string verbatim**, in quotes or a table: menu titles with their shortcuts, window titles, labels, buttons, every status or error line, notification titles and bodies. Use the real characters (`…`, `⌘`). No "something like".
6. **Error states:** for each failure the user can hit, the exact message or the explicit rule that nothing is shown.
7. **Build, CI and the Mac:** what Linux tests, what the `macos` job tests, what only the user's Mac can check.
8. **Done when:** a numbered list a reviewer can check, ending with the user's manual pass.

Before asking for approval, reread it as a hostile spec reviewer: unsettled strings, missing error states, claims no test could check, scope that contradicts `design/14`. Fix them first. Then ask the user to approve; don't plan an unapproved spec.
