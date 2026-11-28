#!/usr/bin/env bash
# CI (macOS job, `xcode-27` runner): lists the Xcodes on the runner, selects the newest Xcode 27, prints
# its version and checks that its Swift matches .swift-version (spec W2). Fails loudly when there is no
# Xcode 27: never fall back to another version.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Xcodes on this runner:"
ls -d /Applications/Xcode*.app 2>/dev/null || echo "(none)"

best=""
best_version=""
while IFS= read -r app; do
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)
    case "$version" in 27 | 27.*) ;; *) continue ;; esac
    newest=$(printf '%s\n%s\n' "${best_version:-0}" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
    if [ -z "$best" ] || [ "$newest" = "$version" ]; then
        best="$app"
        best_version="$version"
    fi
done < <(ls -d /Applications/Xcode*.app 2>/dev/null)

if [ -z "$best" ]; then
    echo "select-xcode: no Xcode 27 on this runner (spec W2 needs Xcode 27.x and Swift 6.4)." >&2
    exit 1
fi
echo "Selecting $best ($best_version)"
sudo xcode-select -s "$best/Contents/Developer"
xcodebuild -version
swift --version

want=$(cut -d. -f1,2 < .swift-version)
if ! swift --version 2>&1 | grep -q "Swift version $want"; then
    echo "select-xcode: this Xcode's Swift is not $want (.swift-version)" >&2
    exit 1
fi
