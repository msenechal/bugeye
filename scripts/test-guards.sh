#!/usr/bin/env bash
# Self-test for scripts/guards.sh: a clean tree passes, and each planted violation fails with its guard.
set -euo pipefail

guards="$(cd "$(dirname "$0")" && pwd)/guards.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# A minimal tree that follows every rule, including the allowed exceptions.
clean_tree() {
    local t="$1"
    mkdir -p "$t/Sources/BugeyeCore/Files" "$t/Sources/Mac/MacAdapters" "$t/Sources/BugeyeApp" "$t/.github/workflows"
    echo "6.4.3" > "$t/.swift-version"
    printf 'import Foundation\n// Not .atomic: we rename.\nlet o: Data.WritingOptions = .atomic\n' \
        > "$t/Sources/BugeyeCore/Files/CaptureFileWriter.swift"
    printf 'import Foundation\nlet d = UserDefaults.standard\n' > "$t/Sources/Mac/MacAdapters/Settings.swift"
    printf '// Debug channel\n#if DEBUG\nlet x = 1\n#endif\n' > "$t/Sources/BugeyeApp/DebugChannel.swift"
    printf 'import AppKit\n' > "$t/Sources/BugeyeApp/App.swift"
    printf 'permissions:\n  contents: read\njobs:\n  linux:\n    container: swift:6.4.3-noble\n' \
        > "$t/.github/workflows/linux.yml"
}

# expect <name> <pass|guard-name> <setup commands…>
expect() {
    local name="$1" want="$2"
    shift 2
    local t="$work/$name"
    clean_tree "$t"
    (cd "$t" && eval "$*")
    local out status=0
    out=$("$guards" "$t" 2>&1) || status=$?
    if [ "$want" = pass ]; then
        if [ $status -ne 0 ]; then echo "FAIL $name: expected pass, got: $out"; failures=$((failures + 1)); fi
    elif [ $status -eq 0 ] || ! grep -q "^guard $want:" <<<"$out"; then
        echo "FAIL $name: expected guard $want, got: $out"
        failures=$((failures + 1))
    fi
    return 0
}

expect clean pass true
expect atomic-elsewhere atomic-write "printf 'let o = Data.WritingOptions.atomic\n' > Sources/BugeyeApp/Save.swift"
expect atomically atomic-write "printf 'try s.write(to: u, atomically: true, encoding: .utf8)\n' > Sources/BugeyeApp/Save.swift"
expect replace-item atomic-write "printf 'try fm.replaceItemAt(a, withItemAt: b)\n' > Sources/BugeyeApp/Save.swift"
expect atomic-in-comment pass "printf '/// never use .atomic here\n' > Sources/BugeyeApp/Save.swift"
expect appkit-in-core portable-import "mkdir -p Sources/Core/EditorCore && printf 'import AppKit\n' > Sources/Core/EditorCore/A.swift"
expect preconcurrency-cg portable-import "printf '@preconcurrency import CoreGraphics\n' > Sources/BugeyeCore/G.swift"
expect scoped-import portable-import "printf 'import struct CoreGraphics.CGRect\n' > Sources/BugeyeCore/G.swift"
expect foundation-ok pass "printf 'import Foundation\nimport Synchronization\nimport Observation\n' > Sources/BugeyeCore/G.swift"
expect os-in-core portable-import "printf 'import os\n' > Sources/BugeyeCore/G.swift"
expect oslog-name-ok pass "printf 'import OSLogLike\n' > Sources/BugeyeCore/G.swift"
expect defaults-in-app user-defaults "printf 'let d = UserDefaults.standard\n' > Sources/BugeyeApp/Prefs.swift"
expect adapter-name-ok pass "printf 'let s = UserDefaultsSettingsStore()\n' > Sources/BugeyeApp/Prefs.swift"
expect debug-unguarded debug-only "printf 'let x = 1\n' > Sources/BugeyeApp/DebugServer.swift"
expect pr-target workflow "printf 'on: pull_request_target\npermissions: {}\n' > .github/workflows/bad.yml"
expect no-permissions workflow "printf 'on: push\njobs: {}\n' > .github/workflows/bad.yml"
expect secret-without-guard workflow "printf 'permissions: {}\nx: \${{ secrets.TOKEN }}\n' > .github/workflows/bad.yml"
expect guard-only-in-comment workflow "printf 'permissions: {}\n# if: github.event.pull_request.head.repo.full_name == github.repository\nuses: anthropics/claude-code-action@v1\n' > .github/workflows/review.yml"
expect draft-only-in-comment workflow "printf 'on:\n  pull_request:\npermissions: {}\nconcurrency:\n  group: x\n# github.event.pull_request.draft == false\n' > .github/workflows/ci.yml"
expect dispatch-agent-without-fork-check workflow "printf 'on:\n  workflow_dispatch:\npermissions: {}\nif: github.event_name == '\\''workflow_dispatch'\\'' || github.event.pull_request.head.repo.full_name == github.repository\nuses: anthropics/claude-code-action@v1\n' > .github/workflows/review.yml"
expect dispatch-agent-with-fork-check pass "printf 'on:\n  workflow_dispatch:\npermissions: {}\nif: github.event_name == '\\''workflow_dispatch'\\'' || github.event.pull_request.head.repo.full_name == github.repository\nrun: gh api \"repos/\$REPO/pulls/\$PR\" --jq .head.repo.full_name\nuses: anthropics/claude-code-action@v1\n' > .github/workflows/review.yml"
expect agent-with-guard pass "printf 'permissions: {}\nif: github.event.pull_request.head.repo.full_name == github.repository\nuses: anthropics/claude-code-action@v1\n' > .github/workflows/review.yml"
expect pr-runs-on-drafts workflow "printf 'on:\n  pull_request:\npermissions: {}\nconcurrency:\n  group: x\n' > .github/workflows/ci.yml"
expect pr-without-concurrency workflow "printf 'on:\n  pull_request:\npermissions: {}\nif: github.event.pull_request.draft == false\n' > .github/workflows/ci.yml"
expect pr-ready-only pass "printf 'on:\n  pull_request:\npermissions: {}\nconcurrency:\n  group: x\nif: github.event.pull_request.draft == false\n' > .github/workflows/ci.yml"
expect version-drift swift-version "echo 6.4.4 > .swift-version"
expect version-missing swift-version "rm .swift-version"

if [ $failures -gt 0 ]; then
    echo "test-guards: $failures failure(s)"
    exit 1
fi
echo "test-guards: ok"
