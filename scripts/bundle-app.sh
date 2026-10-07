#!/bin/bash
# Builds build/PremiumShot.app from the SwiftPM executable, ad-hoc signed with the hardened runtime.
set -euo pipefail
CONFIG="${1:-release}"
cd "$(dirname "$0")/.."

swift build -c "$CONFIG" --product PremiumShotApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/PremiumShotApp"
APP="build/PremiumShot.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PremiumShotApp"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PremiumShotApp</string>
  <key>CFBundleIdentifier</key><string>com.fabien.premiumshot</string>
  <key>CFBundleName</key><string>PremiumShot</string>
  <key>CFBundleDisplayName</key><string>PremiumShot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"
echo "built $APP"
