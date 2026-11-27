---
name: execute-plan
description: "Execute an approved plan task by task with TDD, a committed ledger, decide-ledger-continue on ambiguity, and a draft PR that CI checks on every push. Use when told to execute or continue a plan."
---

# Execute a plan

1. **Start:** read `CLAUDE.md`, the spec, the whole plan, and the ledger if it exists. `git log` and the ledger beat memory: after a context compaction, trust them.
2. **Branch** as the plan says (`feat/<wave>` from `main`). Never commit to `main`; never merge.
3. **Per task**, in order:
   - Write the test exactly as given. Run the Step 2 command and see it fail for the stated reason. A test that passes before the implementation is a finding: stop and work out why.
   - Write the implementation. Run Step 4 and see it pass, then `make test-core lint guards` on Linux.
   - Tasks marked "Not compiled here" can't fail first on Linux: commit test and code together, push, and take the `macos` check on that commit as the result.
   - Commit with the plan's message plus your session's trailer lines. Push.
   - Update the ledger: task done, commit hash, CI run link when there is one.
4. **Ambiguity or conflict:** decide, write `Ruling: <what and why> (cost if wrong: …)` in the ledger, keep going. Don't stop to ask. If the plan's code is wrong, fix it with a test that fails first and ledger the ruling.
5. **CI:** watch the checks on the draft PR. A red check is the next task: reproduce it with a failing test, fix it, push. Never skip, quarantine or delete a test to get green (`design/13` §4 flake policy).
6. **Blockers:** something only the user can do (a secret, a setting, the Mac) is ledgered under `Waiting on user` and the work continues with the next task.
7. **End:** all tasks done, CI green. Write the PR description (what changed, the rulings, what the user must check), mark the PR ready for review, and hand off to the `final-review` skill in a fresh session. Report every ruling with its cost if wrong in your final message.
