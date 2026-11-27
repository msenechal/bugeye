#!/usr/bin/env bash
# Bug-class guards (spec W7, design/14 §6): deterministic checks for rules that kept breaking in the
# first build. Usage: scripts/guards.sh [repo-root]. Prints one line per violation; exits 1 if any.
# Each guard skips comment lines (// and ///), so docs may name what they forbid.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"
failures=0

fail() {
    echo "guard $1: $2"
    failures=$((failures + 1))
}

# Prints file:line:text for code (non-comment) lines under the given paths matching an ERE.
code_matches() {
    local pattern="$1"
    shift
    local existing=()
    for path in "$@"; do [ -e "$path" ] && existing+=("$path"); done
    [ ${#existing[@]} -eq 0 ] && return 0
    grep -rnE --include='*.swift' "$pattern" "${existing[@]}" 2>/dev/null |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

# 1. Atomic writes drop extended attributes: only CaptureFileWriter may replace a file.
writer="Sources/BugeyeCore/Files/CaptureFileWriter.swift"
while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    [ "${hit%%:*}" = "$writer" ] && continue
    fail atomic-write "$hit (write capture files through CaptureFileWriter)"
done < <(code_matches '\.atomic([^A-Za-z0-9_]|$)|atomically:[[:space:]]*true|replaceItemAt|replaceItem\(' Sources)

# 2. Portable targets build on Linux: no Apple-only frameworks.
apple='AppKit|Cocoa|SwiftUI|UIKit|CoreGraphics|CoreText|CoreImage|ImageIO|Vision|VisionKit|ScreenCaptureKit|AVFoundation|AVKit|Carbon|Security|CoreSpotlight|ApplicationServices|Speech|Darwin|os'
while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    fail portable-import "$hit (portable targets import Foundation and Swift modules only)"
done < <(code_matches "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|func|var|let|typealias)[[:space:]]+)?($apple)([^A-Za-z0-9_]|$)" \
    Sources/BugeyeCore Sources/BugeyeFeatures Sources/BugeyeTestSupport Sources/Core)

# 3. Settings go through SettingsStore and secrets through SecretStore: UserDefaults only in the adapter.
while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    case "${hit%%:*}" in Sources/Mac/*) continue ;; esac
    fail user-defaults "$hit (use SettingsStore; the UserDefaults adapter lives in Sources/Mac)"
done < <(code_matches '(^|[^A-Za-z0-9_])UserDefaults([^A-Za-z0-9_]|$)' Sources)

# 4. Debug-only code: every Sources file named Debug* starts with #if DEBUG.
while IFS= read -r file; do
    first=$(grep -vE '^[[:space:]]*(//.*)?$' "$file" | head -n 1 || true)
    [ "$first" = "#if DEBUG" ] || fail debug-only "$file (must start with #if DEBUG)"
done < <(find Sources -name 'Debug*.swift' 2>/dev/null | sort)

# 5. Workflows: never pull_request_target, always explicit permissions, and anything with secrets or an
#    agent runs only for branches of this repository (spec W6).
same_repo='github.event.pull_request.head.repo.full_name == github.repository'
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -e "$wf" ] || continue
    grep -q 'pull_request_target' "$wf" && fail workflow "$wf uses pull_request_target"
    grep -qE '^[[:space:]]*permissions:' "$wf" || fail workflow "$wf has no permissions: block"
    if grep -qE 'secrets\.|anthropics/claude-code-action' "$wf" && ! grep -qF "$same_repo" "$wf"; then
        fail workflow "$wf uses secrets or an agent without the same-repository condition"
    fi
done

# 6. One compiler everywhere (spec W2): the Linux image matches .swift-version.
if [ -f .swift-version ]; then
    version=$(tr -d '[:space:]' < .swift-version)
    if [ -f .github/workflows/linux.yml ] && ! grep -qF "swift:$version-" .github/workflows/linux.yml; then
        fail swift-version ".github/workflows/linux.yml does not use the swift:$version image"
    fi
else
    fail swift-version ".swift-version is missing"
fi

if [ "$failures" -gt 0 ]; then
    echo "guards: $failures violation(s)"
    exit 1
fi
echo "guards: ok"
