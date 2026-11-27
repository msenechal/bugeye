#!/usr/bin/env bash
# Copies the bundled, signed build/Bugeye.app into a folder (default ~/Applications) and relaunches it.
# It never replaces another app: the first build's Bugeye.app (bundle id dev.msenechal.cleanshotcopy) sits
# in /Applications and keeps running alongside until the rebuild replaces it (spec B2).
set -euo pipefail
cd "$(dirname "$0")/.."

dir="${1:-$HOME/Applications}"
target="$dir/Bugeye.app"
bundle_id="dev.msenechal.bugeye"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ ! -d build/Bugeye.app ]; then
    echo "install: build/Bugeye.app is missing. Run: make install (it bundles first)" >&2
    exit 1
fi
mkdir -p "$dir"

if [ -d "$target" ]; then
    existing=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || echo unknown)
    if [ "$existing" != "$bundle_id" ]; then
        echo "install: $target is another app ($existing). Not replacing it. Try: make install INSTALL_DIR=<folder>" >&2
        exit 1
    fi
    # Quit only this copy: the old app's process is also called Bugeye.
    pkill -f "$target/Contents/MacOS/Bugeye" || true
    for _ in $(seq 1 50); do
        pgrep -f "$target/Contents/MacOS/Bugeye" >/dev/null || break
        sleep 0.1
    done
    "$lsregister" -u "$target" || true
    rm -rf "$target"
fi

# The copy in build/ must never answer for the bundle id (notifications, open -b).
"$lsregister" -u "$PWD/build/Bugeye.app" >/dev/null 2>&1 || true
cp -R build/Bugeye.app "$target"
"$lsregister" -f "$target"
open "$target"
echo "Installed and launched $target"
