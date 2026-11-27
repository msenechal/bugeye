# Backlog

Minor findings from final reviews, and work noticed but out of scope. Newest first. Each entry: date, source (PR or review), the finding, where.

- 27 Nov 2026, PR #2 claude-review: `scripts/guards.sh` checks workflow conditions by substring (comment lines now excluded). Parse the YAML per job (e.g. `yq`) and require the same-repository and draft conditions on each job's `if:`, so a weakening `||` branch can't pass. Where: `scripts/guards.sh` rule 5.

- 27 Nov 2026, PR #2 claude-review (round 3, Important, deferred): `AIKeySettings` calls the synchronous `SecretStore` (Keychain) on the main actor in `init`, `save` and `testKey`. A locked keychain or an access prompt would block the UI. Make `SecretStore` async (or run it off the main actor) and apply results with the generation check. Where: `Sources/BugeyeCore/Ports/Ports.swift`, `Sources/Core/AICore/AIKeySettings.swift`, `Sources/Mac/MacAdapters/KeychainSecretStore.swift`.
- 27 Nov 2026, PR #2 claude-review (round 3, Minor): `CaptureFileWriter` doesn't copy the original's POSIX mode onto the temp file and doesn't fsync it before `rename(2)`. Where: `Sources/BugeyeCore/Files/CaptureFileWriter.swift`.
- 27 Nov 2026, PR #2 claude-review (round 6, Minor): the debug channel `chmod`s its socket to 0600 after `bind` (wrap `bind` in `umask(0o177)`), and `stop()` closes the listener fd while the accept thread may still poll it (let the accept loop close it on exit). Where: `Sources/BugeyeApp/DebugChannel.swift`.
