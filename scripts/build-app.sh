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
[[ -f scripts/AppIcon.icns ]] && cp scripts/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Emulist</string>
    <key>CFBundleDisplayName</key><string>Emulist</string>
    <key>CFBundleIdentifier</key><string>app.emulist.Emulist</string>
    <key>CFBundleExecutable</key><string>Emulist</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.2</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Emulist Project</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>app.emulist.project</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Movie</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.movie</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>app.emulist.project</string>
            <key>UTTypeDescription</key><string>Emulist Project</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>emulist</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null
echo "Built $root/$app"
[[ "${1:-}" == "--open" ]] && open "$app"
exit 0
