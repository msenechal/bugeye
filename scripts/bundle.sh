#!/usr/bin/env bash
# Assembles build/Bugeye.app from the SwiftPM product, Resources/Info.plist and the icon BugeyeIconTool
# draws. Signs with $SIGN_IDENTITY ("Bugeye Dev", from `make cert`) when it is set, ad hoc otherwise (CI).
# CONFIG=debug builds a bundle with the debug test channel; the default is release.
set -euo pipefail
cd "$(dirname "$0")/.."

config="${CONFIG:-release}"
app="build/Bugeye.app"
bundle_id="dev.msenechal.bugeye"

swift build -c "$config" --product BugeyeApp
bin="$(swift build -c "$config" --show-bin-path)/BugeyeApp"

rm -rf build/icon
swift run -c release BugeyeIconTool build/icon
iconutil -c icns build/icon/Bugeye.iconset -o build/icon/Bugeye.icns

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Bugeye"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp build/icon/Bugeye.icns build/icon/MenuBarIcon.png build/icon/MenuBarIcon@2x.png "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist"

# The fixture app and the icon tool never ship: Bugeye's executable is the only one in the bundle.
if [ "$(ls "$app/Contents/MacOS")" != "Bugeye" ]; then
    echo "bundle: unexpected executables in $app/Contents/MacOS" >&2
    exit 1
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
    keychain="$HOME/Library/Keychains/bugeye-signing.keychain-db"
    if [ ! -f "$keychain" ]; then
        echo "No signing keychain. Run: make cert" >&2
        exit 1
    fi
    security unlock-keychain -p bugeye "$keychain"
    codesign --force --sign "$SIGN_IDENTITY" --keychain "$keychain" --identifier "$bundle_id" "$app"
else
    codesign --force --sign - --identifier "$bundle_id" "$app"
fi
codesign --verify --strict "$app"
codesign -d -r- "$app"
echo "Built $app ($config)"
