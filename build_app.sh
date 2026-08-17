#!/bin/zsh
# Build CleanUp with SwiftPM and package it as a proper macOS .app bundle.
set -e
cd "$(dirname "$0")"

CONFIG=${1:-release}
# Universal binary: build each arch separately (works with Command Line
# Tools alone; --arch x2 would need full Xcode), then merge with lipo.
swift build -c "$CONFIG" --triple arm64-apple-macosx
swift build -c "$CONFIG" --triple x86_64-apple-macosx
mkdir -p ".build/universal-$CONFIG"
lipo -create \
    ".build/arm64-apple-macosx/$CONFIG/CleanUp" \
    ".build/x86_64-apple-macosx/$CONFIG/CleanUp" \
    -output ".build/universal-$CONFIG/CleanUp"

BIN=".build/universal-$CONFIG/CleanUp"
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
    <key>CFBundleShortVersionString</key><string>1.6</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Syahrul Farhan</string>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS treats the bundle as a stable identity for
# permission grants like Full Disk Access.
codesign --force --deep -s - "$APP"

echo "Built $APP"
