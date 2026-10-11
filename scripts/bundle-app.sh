#!/bin/bash
# Local/CI packaging uses the same SDK, metadata and ad-hoc signature checks.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
case "$CONFIG" in release|debug) ;; *) echo "Expected release or debug" >&2; exit 2;; esac
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 2;; esac
swift build -c "$CONFIG" --arch "$ARCH" --product PremiumShotApp
BIN="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)/PremiumShotApp"
if [[ "$CONFIG" == debug ]]; then APP="build/Debug/PremiumShot Dev.app"; else APP="build/PremiumShot.app"; fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PremiumShotApp"
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --target-device mac --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "build/icon-$CONFIG.plist"
python3 scripts/bundle-metadata.py "$APP" "$CONFIG" "build/icon-$CONFIG.plist"
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"
python3 scripts/verify-bundle.py "$APP" "$CONFIG" "$ARCH"
echo "Built $APP"
