# Backlog

Minor findings from final reviews, and work noticed but out of scope. Newest first. Each entry: date, source (PR or review), the finding, where.

- 27 Nov 2026, PR #2 claude-review: `scripts/guards.sh` checks workflow conditions by substring (comment lines now excluded). Parse the YAML per job (e.g. `yq`) and require the same-repository and draft conditions on each job's `if:`, so a weakening `||` branch can't pass. Where: `scripts/guards.sh` rule 5.

- 27 Nov 2026, PR #2 claude-review (round 3, Minor): `CaptureFileWriter` doesn't fsync the temp file before `rename(2)` (the POSIX mode is now kept; creation date and ACLs are not). Where: `Sources/BugeyeCore/Files/CaptureFileWriter.swift`.
- 27 Nov 2026, PR #2 claude-review (round 6, Minor): the debug channel `chmod`s its socket to 0600 after `bind` (wrap `bind` in `umask(0o177)`), and `stop()` closes the listener fd while the accept thread may still poll it (let the accept loop close it on exit). Where: `Sources/BugeyeApp/DebugChannel.swift`.
- 27 Nov 2026, PR #2 claude-review (round 8, Minor): a Keychain read error (locked keychain, access denied) is treated as "no key": `AIKeySettings.hasKey` and `AnthropicClient.send` use `try?`, so the pane shows "No key saved." and the user may overwrite a good key. Needs a spec status line such as "Couldn't read the Keychain." Where: `Sources/Core/AICore/AIKeySettings.swift`, `Sources/Core/AICore/AnthropicClient.swift`.
