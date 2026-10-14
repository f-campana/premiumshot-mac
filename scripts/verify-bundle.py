#!/usr/bin/env python3
"""Fail packaging when release diagnostics leak, metadata is missing or signing changes."""
from pathlib import Path
import json
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
config, architecture = sys.argv[2:]
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == Path("VERSION").read_text().strip()
assert info["CFBundleVersion"].isdigit()
assert info["CFBundleVersion"] == Path("BUILD_NUMBER").read_text().strip()
assert int(info["CFBundleVersion"]) > 7, "Builds must follow the previously installed build 7"
assert info["CFBundleIdentifier"] == "app.premiumshot.mac" + (".dev" if config == "debug" else "")
assert info["NSDesktopFolderUsageDescription"]
assert info["PSFeedbackURL"] == "mailto:support@premiumshot.app"
assert info["LSApplicationCategoryType"] == "public.app-category.graphics-design"
assert "CFBundleURLTypes" not in info
assert info["LSMinimumSystemVersion"] == "26.0"
binary = app / "Contents/MacOS/PremiumShotApp"
assert list((app / "Contents/MacOS").iterdir()) == [binary], "Only the app executable may ship"
actual = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
assert actual == architecture, (actual, architecture)
resources = {p.name for p in (app / "Contents/Resources").iterdir()}
assert resources == {"AppIcon.icns", "Assets.car"}, resources
strings = subprocess.check_output(["strings", str(binary)], text=True)
diagnostics = ["--snapshot", "--spike-tools", "--bench-workflow", "--bench-visible",
               "--self-test", "--qa", "--image", "--welcome", "--folder-denied",
               "--summon", "--expanded", "--inspect", "--look", "--shape", "--dark", "--snapshot-action"]
for flag in diagnostics:
    assert (flag in strings) == (config == "debug"), (flag, config)
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
signature = subprocess.run(["codesign", "-dvv", str(app)], text=True, capture_output=True, check=True).stderr
assert "Signature=adhoc" in signature
assert "runtime" in signature
entitlements = subprocess.run(["codesign", "-d", "--entitlements", "-", str(app)], capture_output=True, check=True).stdout
assert not entitlements.strip(), "No entitlement is expected for this non-sandboxed app"
print(json.dumps({"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
    "bundle_identifier": info["CFBundleIdentifier"],
    "feedback_url": info["PSFeedbackURL"],
    "commit": info["PSBuildCommit"], "dirty": info["PSBuildDirty"], "architecture": actual,
    "signature": "ad-hoc hardened runtime", "notarized": False,
    "bundle_bytes": sum(p.stat().st_size for p in app.rglob("*") if p.is_file()),
    "release_diagnostics_absent": config == "release"}, indent=2))
