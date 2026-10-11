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
cp Resources/DMGLayout.ds-store "$STAGE/.DS_Store"
hdiutil create -volname PremiumShot -srcfolder "$STAGE" -format UDZO -ov "$PACKAGE.dmg"
hdiutil verify "$PACKAGE.dmg"
(cd out && shasum -a 256 "${PACKAGE#out/}.dmg" > "${PACKAGE#out/}.dmg.sha256")
python3 scripts/verify-bundle.py build/PremiumShot.app release "$ARCH" > "$PACKAGE.json"
echo "Private-beta package: $PACKAGE.dmg"
