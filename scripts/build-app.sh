#!/bin/zsh
# Builds Emulist.app (release) into ./build. Needs only the Swift toolchain (Command Line Tools);
# Metal shaders are compiled at runtime, so no Xcode is required.
#
#   scripts/build-app.sh [--open]
set -euo pipefail
root="${0:A:h}/.."
cd "$root"

swift build -c release --product Emulist
app="build/Emulist.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Emulist "$app/Contents/MacOS/Emulist"
# The version lives in packaging/macos/Info.plist (CFBundleShortVersionString).
cp packaging/macos/Info.plist "$app/Contents/Info.plist"
cp packaging/macos/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app" >/dev/null
echo "Built $root/$app"
[[ "${1:-}" == "--open" ]] && open "$app"
exit 0
