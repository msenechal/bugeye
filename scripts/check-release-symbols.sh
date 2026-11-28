#!/usr/bin/env bash
# Spec §5.6: release builds contain none of the debug test channel. The debug build must contain it,
# or this check would prove nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

pattern='DebugChannel|DebugCommandHandler|DebugCommands|bugeye-debug\.sock'

symbols_of() {
    local config="$1"
    swift build -c "$config" --product BugeyeApp >&2
    local bin
    bin="$(swift build -c "$config" --show-bin-path)/BugeyeApp"
    { nm "$bin"; strings "$bin"; } 2>/dev/null
}

debug_symbols=$(symbols_of debug)
if ! grep -qE "$pattern" <<<"$debug_symbols"; then
    echo "check-release-symbols: the debug build has no debug channel, so this check proves nothing" >&2
    exit 1
fi

release_symbols=$(symbols_of release)
if grep -E "$pattern" <<<"$release_symbols"; then
    echo "check-release-symbols: the release build contains debug channel code" >&2
    exit 1
fi
echo "check-release-symbols: ok"
