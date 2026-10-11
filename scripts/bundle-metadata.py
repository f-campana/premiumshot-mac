#!/usr/bin/env python3
"""Generate bundle metadata from VERSION, Git and the asset compiler's icon keys."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app, config, icon = sys.argv[1:]
version = Path("VERSION").read_text().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("VERSION must contain one x.y.z version")
if os.environ.get("VERSION", version) != version:
    raise SystemExit("Update the VERSION file before making this release")
def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()
build = git("rev-list", "--count", "HEAD")
dirty = bool(git("status", "--porcelain", "--untracked-files=normal"))
metadata = {
    "CFBundleExecutable": "PremiumShotApp",
    "CFBundleIdentifier": "com.fabien.premiumshot" + (".dev" if config == "debug" else ""),
    "CFBundleName": "PremiumShot" + (" Dev" if config == "debug" else ""),
    "CFBundleDisplayName": "PremiumShot" + (" Dev" if config == "debug" else ""),
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "CFBundleVersion": build,
    "LSMinimumSystemVersion": "26.0", "LSUIElement": True, "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication", "LSApplicationCategoryType": "public.app-category.graphics-design",
    "NSHumanReadableCopyright": "Copyright © 2026 Fabien Campana",
    "NSDesktopFolderUsageDescription": "PremiumShot reads your latest screenshot when you choose Open latest screenshot.",
    "PSWebsiteURL": "https://premiumshot.app", "PSSourceURL": "https://github.com/f-campana/premiumshot-mac",
    "PSBuildCommit": git("rev-parse", "HEAD"), "PSBuildDirty": dirty,
}
# Only expose support once its actual destination is configured by the owner.
if support := os.environ.get("SUPPORT_URL"):
    if not support.startswith("https://"):
        raise SystemExit("SUPPORT_URL must be HTTPS")
    metadata["PSSupportURL"] = support
metadata.update(plistlib.loads(Path(icon).read_bytes()))
Path(app, "Contents", "Info.plist").write_bytes(plistlib.dumps(metadata, sort_keys=True))
