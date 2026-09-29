#!/bin/zsh
# Build CleanUp with SwiftPM and package it as a proper macOS .app bundle.
set -e
cd "$(dirname "$0")"

CONFIG=${1:-release}
# Universal binary in one shot (requires full Xcode, installed 2026-09).
swift build -c "$CONFIG" --arch arm64 --arch x86_64

# Product path differs between SwiftPM releases — take whichever exists.
BIN=""
for candidate in ".build/out/Products/${(C)CONFIG}/CleanUp" \
                 ".build/apple/Products/${(C)CONFIG}/CleanUp"; do
    [ -f "$candidate" ] && BIN="$candidate" && break
done
[ -n "$BIN" ] || { echo "error: built product not found"; exit 1; }
APP="dist/CleanUp.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/CleanUp"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/SidebarLogo.png "$APP/Contents/Resources/SidebarLogo.png"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CleanUp</string>
    <key>CFBundleIdentifier</key><string>com.syahrul.cleanup</string>
    <key>CFBundleName</key><string>CleanUp</string>
    <key>CFBundleDisplayName</key><string>CleanUp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.11.2</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Syahrul Farhan</string>
</dict>
</plist>
EOF

# Sign with a real certificate when one exists (create a free "Apple
# Development" cert in Xcode > Settings > Accounts) so TCC permission
# grants like Full Disk Access survive updates; ad-hoc otherwise.
# PUBLIC=1 (public release zips) never uses an Apple Development cert: its
# signature embeds the developer's email, readable by anyone.
if [ "${PUBLIC:-0}" = "1" ]; then
    PATTERN='Developer ID Application'
else
    PATTERN='Developer ID Application|Apple Development'
fi
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v pat="$PATTERN" '$0 ~ pat {print $2; exit}')
codesign --force --deep -s "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc signature (permissions reset on each update)}"

echo "Built $APP"
