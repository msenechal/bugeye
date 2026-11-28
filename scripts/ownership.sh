#!/usr/bin/env bash
# Folder ownership after the Wave 1 contracts PR (contracts spec §3, K16, K24, K25).
# Usage: scripts/ownership.sh [base] (default origin/main). The branch comes from OWNERSHIP_BRANCH, else
# GITHUB_HEAD_REF, else the current branch. An epic branch (feat/wave1-<epic>-<slice>) may change only the
# paths its epic owns; every path not owned by an epic is contract and changes through a contract amendment.
set -euo pipefail

base="${1:-origin/main}"
branch="${OWNERSHIP_BRANCH:-${GITHUB_HEAD_REF:-}}"
[ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD)

epics=(capture quick-access editor recording ocr)

# The paths each epic writes. A trailing / means the folder and everything in it; otherwise the exact file.
owned_paths() {
    case "$1" in
    capture) printf '%s\n' Sources/Core/CaptureCore/ Tests/CaptureCoreTests/ Sources/BugeyeCore/Ports/Capture/ \
        Tests/BugeyeCoreTests/Capture/ Sources/BugeyeTestSupport/Capture/ Tests/BugeyeTestSupportTests/Capture/ \
        Sources/BugeyeFeatures/Shortcuts/ Tests/BugeyeFeaturesTests/Shortcuts/ Sources/Mac/MacAdapters/Capture/ \
        Tests/MacAdaptersTests/Capture/ Sources/BugeyeApp/Capture/ Sources/BugeyeApp/Shortcuts/ \
        Sources/BugeyeApp/Wiring/CaptureWiring.swift Tests/BugeyeAppTests/Capture/ ;;
    quick-access) printf '%s\n' Sources/Core/QuickAccessCore/ Tests/QuickAccessCoreTests/ \
        Sources/BugeyeApp/QuickAccess/ Sources/BugeyeApp/Wiring/QuickAccessWiring.swift \
        Tests/BugeyeAppTests/QuickAccess/ ;;
    editor) printf '%s\n' Sources/Core/EditorCore/ Tests/EditorCoreTests/ Sources/Mac/MacAdapters/DisplayList/ \
        Tests/MacAdaptersTests/DisplayList/ Sources/BugeyeApp/Editor/ Sources/BugeyeApp/Wiring/EditorWiring.swift \
        Tests/BugeyeAppTests/Editor/ ;;
    recording) printf '%s\n' Sources/Core/RecordingCore/ Tests/RecordingCoreTests/ \
        Sources/BugeyeCore/Ports/Recording/ Sources/BugeyeCore/Ports/Accessibility/ Sources/BugeyeCore/Timeline/ \
        Tests/BugeyeCoreTests/Recording/ Tests/BugeyeCoreTests/Accessibility/ Tests/BugeyeCoreTests/Timeline/ \
        Sources/BugeyeTestSupport/Recording/ Sources/BugeyeTestSupport/Accessibility/ \
        Tests/BugeyeTestSupportTests/Recording/ Tests/BugeyeTestSupportTests/Accessibility/ \
        Sources/Mac/MacAdapters/Accessibility/ Sources/Mac/MacAdapters/Permissions/ \
        Tests/MacAdaptersTests/Accessibility/ Tests/MacAdaptersTests/Permissions/ Sources/BugeyeApp/Recording/ \
        Sources/BugeyeApp/Wiring/RecordingWiring.swift Tests/BugeyeAppTests/Recording/ ;;
    ocr) printf '%s\n' Sources/Core/TextCore/ Tests/TextCoreTests/ Sources/BugeyeCore/Ports/Text/ \
        Tests/BugeyeCoreTests/Text/ Sources/BugeyeTestSupport/Text/ Tests/BugeyeTestSupportTests/Text/ \
        Sources/Mac/MacAdapters/Text/ Sources/Mac/MacAdapters/Images/ Tests/MacAdaptersTests/Text/ \
        Tests/MacAdaptersTests/Images/ Sources/BugeyeApp/Wiring/TextWiring.swift Tests/BugeyeAppTests/Text/ ;;
    esac
}

# True when `path` belongs to `epic`, including its docs (any docs/ path whose file name contains
# wave-1-<epic>, K25).
owns() {
    local epic="$1" path="$2" pattern
    case "$path" in docs/*) case "${path##*/}" in *"wave-1-$epic"*) return 0 ;; esac ;; esac
    while IFS= read -r pattern; do
        case "$pattern" in
        */) [[ "$path" == "$pattern"* ]] && return 0 ;;
        *) [ "$path" = "$pattern" ] && return 0 ;;
        esac
    done < <(owned_paths "$epic")
    return 1
}

owner_of() {
    local epic
    for epic in "${epics[@]}"; do
        if owns "$epic" "$1"; then
            echo "$epic"
            return
        fi
    done
    echo "contract (needs a contract amendment, K2)"
}

epic=""
for candidate in "${epics[@]}"; do
    if [[ "$branch" == "feat/wave1-$candidate-"?* ]]; then epic="$candidate"; fi
done
if [ -z "$epic" ]; then
    if [[ "$branch" =~ ^feat/wave-?1- ]] && [[ ! "$branch" =~ ^feat/wave1-contracts ]]; then
        echo "ownership: $branch looks like a Wave 1 branch but has no known prefix"
        exit 1
    fi
    echo "ownership: $branch is not an epic branch, skipped"
    exit 0
fi

failures=0
while IFS= read -r path; do
    [ -z "$path" ] && continue
    owns "$epic" "$path" && continue
    echo "ownership $epic: $path belongs to $(owner_of "$path")"
    failures=$((failures + 1))
done < <(git diff --name-only --no-renames "$(git merge-base "$base" HEAD)" HEAD)

if [ "$failures" -gt 0 ]; then
    echo "ownership: $failures path(s) outside $epic's folders"
    exit 1
fi
echo "ownership $epic: ok"
