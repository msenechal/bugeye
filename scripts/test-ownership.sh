#!/usr/bin/env bash
# Self-test for scripts/ownership.sh (contracts spec §3, K16, K24, K25): builds a throwaway git repository
# and checks which branches and paths pass or fail, and with which owner.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/ownership.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

git_quiet() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# A repository whose main has one file per interesting folder.
base_repo() {
    local r="$1"
    mkdir -p "$r"
    (
        cd "$r"
        git_quiet init -b main
        mkdir -p Sources/Core/CaptureCore Sources/Core/EditorCore Sources/BugeyeCore docs/ledgers
        echo a > Sources/Core/CaptureCore/A.swift
        echo e > Sources/Core/EditorCore/E.swift
        echo c > Sources/BugeyeCore/C.swift
        echo b > docs/backlog.md
        echo m > CLAUDE.md
        git_quiet add -A
        git_quiet commit -m base
    )
}

# expect <name> <branch> <pass|fail> <expected output fragment or ""> <change commands…>
expect() {
    local name="$1" branch="$2" want="$3" fragment="$4"
    shift 4
    local r="$work/$name"
    base_repo "$r"
    local out status=0
    out=$(
        cd "$r"
        git_quiet checkout -b "$branch"
        eval "$*"
        git_quiet add -A
        git_quiet commit -m change --allow-empty
        OWNERSHIP_BRANCH="$branch" GITHUB_HEAD_REF="" "$check" main 2>&1
    ) || status=$?
    if [ "$want" = pass ] && [ $status -ne 0 ]; then
        echo "FAIL $name: expected pass, got: $out"
        failures=$((failures + 1))
    elif [ "$want" = fail ] && [ $status -eq 0 ]; then
        echo "FAIL $name: expected failure, got: $out"
        failures=$((failures + 1))
    elif [ -n "$fragment" ] && ! grep -qF -- "$fragment" <<<"$out"; then
        echo "FAIL $name: expected '$fragment' in: $out"
        failures=$((failures + 1))
    fi
    return 0
}

cap=feat/wave1-capture-x
expect owned "$cap" pass "" "echo b > Sources/Core/CaptureCore/B.swift"
expect owned-brace feat/wave1-recording-x pass "" \
    "mkdir -p Tests/BugeyeCoreTests/Timeline && echo t > Tests/BugeyeCoreTests/Timeline/T.swift"
expect other-epic "$cap" fail "ownership capture: Sources/Core/EditorCore/E.swift belongs to editor" \
    "echo x >> Sources/Core/EditorCore/E.swift"
expect contract-file "$cap" fail \
    "ownership capture: Sources/BugeyeCore/C.swift belongs to contract (needs a contract amendment, K2)" \
    "echo x >> Sources/BugeyeCore/C.swift"
expect rename-out "$cap" fail "ownership capture: Sources/BugeyeCore/A.swift belongs to contract" \
    "git mv Sources/Core/CaptureCore/A.swift Sources/BugeyeCore/A.swift"
expect ledger "$cap" pass "" "echo l > docs/ledgers/wave-1-capture.md"
expect plan "$cap" pass "" "mkdir -p docs/plans && echo p > docs/plans/2026-11-28-wave-1-capture.md"
expect checklist "$cap" pass "" "mkdir -p docs/checklists && echo c > docs/checklists/wave-1-capture.md"
expect other-ledger "$cap" fail "ownership capture: docs/ledgers/wave-1-editor.md belongs to editor" \
    "echo l > docs/ledgers/wave-1-editor.md"
expect backlog "$cap" fail "ownership capture: docs/backlog.md belongs to contract" "echo x >> docs/backlog.md"
expect claude-md "$cap" fail "ownership capture: CLAUDE.md belongs to contract" "echo x >> CLAUDE.md"
expect not-epic feat/something pass "ownership: feat/something is not an epic branch, skipped" \
    "echo x >> Sources/BugeyeCore/C.swift"
expect contracts-branch feat/wave1-contracts-claude-md pass "is not an epic branch, skipped" \
    "echo x >> CLAUDE.md"
expect dashed-wave feat/wave-1-capture-x fail \
    "ownership: feat/wave-1-capture-x looks like a Wave 1 branch but has no known prefix" "true"
expect misspelt feat/wave1-captur-x fail \
    "ownership: feat/wave1-captur-x looks like a Wave 1 branch but has no known prefix" "true"
expect quick-access feat/wave1-quick-access-x pass "" \
    "mkdir -p Sources/BugeyeApp/QuickAccess && echo q > Sources/BugeyeApp/QuickAccess/Q.swift"
expect wiring-other "$cap" fail "belongs to editor" \
    "mkdir -p Sources/BugeyeApp/Wiring && echo w > Sources/BugeyeApp/Wiring/EditorWiring.swift"

if [ "$failures" -gt 0 ]; then
    echo "test-ownership: $failures failure(s)"
    exit 1
fi
echo "test-ownership: ok"
