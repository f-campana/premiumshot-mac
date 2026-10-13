#!/usr/bin/env python3
"""Generate bundle metadata from committed release numbers and icon compiler keys."""
from datetime import datetime
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
build = Path("BUILD_NUMBER").read_text().strip()
if not re.fullmatch(r"\d{10}", build) or build[-2:] == "00":
    raise SystemExit("BUILD_NUMBER must contain YYYYMMDDNN, with NN from 01 to 99")
try:
    datetime.strptime(build[:8], "%Y%m%d")
except ValueError:
    raise SystemExit("BUILD_NUMBER must contain a valid calendar date") from None
for tag in git("tag", "--list", "v*").splitlines():
    previous = subprocess.run(["git", "show", f"{tag}:BUILD_NUMBER"], text=True, capture_output=True)
    if previous.returncode != 0:
        continue  # Legacy releases predate the recorded build-number rule.
    number = previous.stdout.strip()
    if not number.isdigit():
        raise SystemExit(f"Invalid BUILD_NUMBER in release tag {tag}")
    same_commit = git("rev-parse", f"{tag}^{{commit}}") == git("rev-parse", "HEAD")
    if int(build) < int(number) or (build == number and not same_commit):
        raise SystemExit(f"BUILD_NUMBER must advance beyond release tag {tag} ({number})")
dirty = bool(git("status", "--porcelain", "--untracked-files=normal"))
metadata = {
    "CFBundleExecutable": "PremiumShotApp",
    "CFBundleIdentifier": "app.premiumshot.mac" + (".dev" if config == "debug" else ""),
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
# PSFeedbackURL stays absent until an incoming support message and reply are verified.
# Enable it in a reviewed release after that evidence is recorded.
# The support/tip page stays disabled until its real HTTPS destination is configured.
if support := os.environ.get("SUPPORT_URL"):
    if not support.startswith("https://"):
        raise SystemExit("SUPPORT_URL must be HTTPS")
    metadata["PSSupportURL"] = support
metadata.update(plistlib.loads(Path(icon).read_bytes()))
Path(app, "Contents", "Info.plist").write_bytes(plistlib.dumps(metadata, sort_keys=True))
