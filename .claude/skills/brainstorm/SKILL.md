---
name: brainstorm
description: "Run a brainstorm with the user before a wave or feature is specified: one question at a time, multiple choice, decisions recorded for the spec. Use when the user wants to start a new wave, epic or feature, or says 'brainstorm'."
---

# Brainstorm

The user owns the brainstorm and the spec (`design/14` §4). Your job is to find every decision the spec needs and get the user's answer to each, quickly.

1. Read `design/README.md`, `design/14` (it overrides older docs), `design/11` and every design file the topic touches. Read `CLAUDE.md` and the last wave's spec and ledger.
2. List the open decisions for yourself: behaviour, user-visible strings, scope edges, platform limits, privacy, what Linux can test and what needs the Mac.
3. Ask **one question per message**. Make it multiple choice where you can: 2–4 lettered options, your recommendation first and marked as such, one line on the cost of each. Say why the question matters in one sentence.
4. Don't ask what the design docs already settle; cite them instead. Don't ask about implementation details the plan can decide.
5. After each answer, note it as `B<n>` with the user's words. When a question has an obvious answer the user would accept, decide it yourself as a ruling `W<n>` with its cost if wrong; the user sees it at approval.
6. When nothing is open, write the spec with the `write-spec` skill and ask the user to approve it. Nothing is planned or built before approval.

Keep in mind the user's taste (`design/11` §7): a personal tool, no sharing or cloud features, nothing "overkill for just me".
