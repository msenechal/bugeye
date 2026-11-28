# Backlog

Minor findings from final reviews, and work noticed but out of scope. Newest first. Each entry: date, source (PR or review), the finding, where.

- 27 Nov 2026, PR #2 claude-review: `scripts/guards.sh` checks workflow conditions by substring (comment lines now excluded). Parse the YAML per job (e.g. `yq`) and require the same-repository and draft conditions on each job's `if:`, so a weakening `||` branch can't pass. Where: `scripts/guards.sh` rule 5.

- 27 Nov 2026, PR #2 claude-review (round 3, Minor): `CaptureFileWriter` doesn't fsync the temp file before `rename(2)` (the POSIX mode is now kept; creation date and ACLs are not). Where: `Sources/BugeyeCore/Files/CaptureFileWriter.swift`.
- 27 Nov 2026, PR #2 claude-review (round 6, Minor): the debug channel `chmod`s its socket to 0600 after `bind` (wrap `bind` in `umask(0o177)`), and `stop()` closes the listener fd while the accept thread may still poll it (let the accept loop close it on exit). Round 8 adds: or put the socket in a 0700 directory, and check the `chmod` result (`start()` also unlinks whatever is at the path). Where: `Sources/BugeyeApp/DebugChannel.swift`.
- 27 Nov 2026, PR #2 claude-review (round 8, Minor): a Keychain read error (locked keychain, access denied) is treated as "no key": `AIKeySettings.hasKey` and `AnthropicClient.send` use `try?`, so the pane shows "No key saved." and the user may overwrite a good key. Needs a spec status line such as "Couldn't read the Keychain." Where: `Sources/Core/AICore/AIKeySettings.swift`, `Sources/Core/AICore/AnthropicClient.swift`.

Final review of Wave 0 (PR #2, 28 Nov 2026), Minor findings:
- M1: `AIKeySettings` saves aren't serialized: two quick saves can reach the Keychain in either order while the status follows the later one, and a "Test key" press during a save can test the old key. Keep the in-flight save `Task` and await it in the next save and in `testKey`, or route Keychain calls through one actor; disable Test during a save. Where: `Sources/Core/AICore/AIKeySettings.swift`.
- M2: `CaptureFileWriter` turns a symlinked capture path into a regular file with the link's mode and leaves the target stale. Resolve symlinks at the top of `write`; test with a symlink. Where: `Sources/BugeyeCore/Files/CaptureFileWriter.swift`.
- M3: the writer's temp name `.<name>.<uuid>.tmp` adds 42 bytes, so names over 213 bytes fail with ENAMETOOLONG. Use `.bugeye-<uuid>.tmp`. Same file.
- M4: the AI key field keeps the typed key after Save, and a second Save resets "Key works." Clear `typedKey` after a successful save. Where: `Sources/BugeyeApp/SettingsWindowController.swift`.
- M5: `claude-review.yml` uses moving tags for `actions/checkout` and `anthropics/claude-code-action` in the secret-bearing job; pin full SHAs, and add `persist-credentials: false` to the checkout.
- M6: `FeatureRegistry` doesn't reserve the shell's own claims (the `ai` pane id, ⌘, and ⌘Q); seed `conflicts(in:)` with them. Where: `Sources/BugeyeFeatures/FeatureRegistry.swift`.
- M7: the guards' Apple-only import list misses Combine, OSLog, CryptoKit, UniformTypeIdentifiers, Network, FoundationModels, AppIntents, QuartzCore, CoreServices, UserNotifications; an import inside `#if canImport` passes. Extend the list and self-test. Where: `scripts/guards.sh`.
- M8: `AnthropicClient.send` reads the Keychain synchronously and stays off the main actor only because `NonisolatedNonsendingByDefault` is off; mark it `@concurrent` or read the key in a detached task, and extend the main-actor probe test to it.
- M9: `.gitignore` doesn't list `docs/rd/` and `t.md` (CLAUDE.md says to keep them untracked).
- M10: `#if DEBUG` blocks sit inline in `AppDelegate.swift`, against the `Debug*.swift` rule; move them to an `AppDelegate` extension in `DebugAppWiring.swift` or note the exception in CLAUDE.md.
- M11: a skipped required check (`linux`/`macos` on a fork PR) counts as passing in GitHub rulesets, so a fork PR could merge without CI. Harmless for a one-user repo; note it in the ruleset or require the review too.
- 28 Nov 2026, PR #2 claude-review (Minor): the debug channel serves clients one at a time on its accept thread, and `SO_RCVTIMEO` is per read, so a client trickling a byte every few seconds blocks all others. Add an overall per-connection deadline (~30 s) or a thread per client. Where: `Sources/BugeyeApp/DebugChannel.swift`.
