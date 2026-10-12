#!/bin/bash
# Private-beta packaging only. Publishing and notarization are separate owner gates.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Commit the reviewed source before make release. Use make app for a working-tree preview." >&2
  exit 2
fi
VERSION="$(cat VERSION)"
ARCH="${ARCH:-$(uname -m)}"
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" != "v$VERSION" ]]; then
  echo "The tag must match VERSION (v$VERSION)." >&2; exit 2
fi
make clean
make check ARCH="$ARCH"
PACKAGE="out/PremiumShot-$VERSION-$ARCH"
STAGE="build/dmg-root"
mkdir -p "$STAGE" out
ditto build/PremiumShot.app "$STAGE/PremiumShot.app"
ln -s /Applications "$STAGE/Applications"
cp docs/beta-installation.md "$STAGE/Read me first.txt"
xcrun SetFile -a V "$STAGE/Read me first.txt"
mkdir -p "$STAGE/.background"
cp Resources/Installer.tiff "$STAGE/.background/Installer.tiff"
cp build/PremiumShot.app/Contents/Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
MOUNT="$PWD/build/dmg-volume"
mkdir -p "$MOUNT"
cleanup() { hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
hdiutil create -volname PremiumShot -fs HFS+ -srcfolder "$STAGE" -format UDRW -ov build/installer.dmg
hdiutil attach build/installer.dmg -mountpoint "$MOUNT" -nobrowse
python3 -m pip install --disable-pip-version-check --no-cache-dir --only-binary=:all: \
  --require-hashes --target build/installer-tools -r scripts/installer-requirements.txt
PYTHONPATH="$PWD/build/installer-tools" python3 scripts/make-installer-layout.py "$MOUNT"
xcrun SetFile -a C "$MOUNT"
xcrun SetFile -a V "$MOUNT/.VolumeIcon.icns"
hdiutil detach "$MOUNT"
trap - EXIT
hdiutil convert build/installer.dmg -format UDZO -o "$PACKAGE.dmg" -ov
hdiutil verify "$PACKAGE.dmg"
(cd out && shasum -a 256 "${PACKAGE#out/}.dmg" > "${PACKAGE#out/}.dmg.sha256")
python3 scripts/verify-bundle.py build/PremiumShot.app release "$ARCH" > "$PACKAGE.json"
echo "Private-beta package: $PACKAGE.dmg"
