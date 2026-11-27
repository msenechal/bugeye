---
name: manual-checklist
description: "Write the user's manual checklist for a wave in docs/checklists/ in the format they asked for. Use when a wave is ready for the user's manual pass, or when asked for a checklist."
---

# Manual checklist

File: `docs/checklists/<wave>.md`. Model: `docs/checklists/wave-0.md`. The user found one-line-per-item checklists unclear; use this shape (`design/11` §5):

1. **Before you start:** what to install or build, which permissions to grant, what test data to prepare, which commands to run first (in a code block).
2. **Shortcuts:** a table of every key and menu item used below.
3. **How to check:** the Terminal commands that inspect results (`xattr -l`, `log show --predicate 'subsystem == "dev.msenechal.bugeye"'`, `defaults read`, `security find-generic-password`).
4. **Tests**, numbered, in sections. Each has numbered steps that name the exact menu item or shortcut, then one **Expected:** line quoting the exact strings the user should see.

Only list what agents could not verify: feel, taste, real permissions, real capture, the installed app. Everything a test or CI checks stays out. End with what to say when done ("all good", or the numbers that failed).
