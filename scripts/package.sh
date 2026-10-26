#!/bin/zsh
# Builds Emulist.app and packages it for a release: a .dmg, a .zip and SHA256SUMS.txt in ./build/dist.
# The app is ad-hoc signed and not notarized (see the release notes for how to open it).
#
#   scripts/package.sh
set -euo pipefail
root="${0:A:h}/.."
cd "$root"

version="$(plutil -extract CFBundleShortVersionString raw packaging/macos/Info.plist)"
scripts/build-app.sh
codesign --verify --strict build/Emulist.app

dist="build/dist"
rm -rf "$dist"
mkdir -p "$dist"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R build/Emulist.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Emulist $version" -srcfolder "$staging" -fs HFS+ -format UDZO "$dist/Emulist-$version.dmg"
ditto -c -k --keepParent build/Emulist.app "$dist/Emulist-$version.zip"
(cd "$dist" && shasum -a 256 "Emulist-$version.dmg" "Emulist-$version.zip" > SHA256SUMS.txt)
ls -lh "$dist"
