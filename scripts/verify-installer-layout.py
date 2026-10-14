"""Check the saved Finder viewport against the packaged artwork and hidden chrome."""
import json
from pathlib import Path
import re
import subprocess
import sys

from ds_store import DSStore

mount = Path(sys.argv[1]).resolve()
artwork = mount / ".background/Installer.tiff"
properties = subprocess.check_output([
    "sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "dpiWidth", "-g", "dpiHeight", str(artwork)
], text=True)
values = {key: float(value) for key, value in re.findall(
    r"(pixelWidth|pixelHeight|dpiWidth|dpiHeight):\s*([0-9.]+)", properties)}
artwork_size = (values["pixelWidth"] * 72 / values["dpiWidth"],
                values["pixelHeight"] * 72 / values["dpiHeight"])
with DSStore.open(str(mount / ".DS_Store"), "r") as layout:
    window = layout["."]["bwsp"]
    icons = layout["."]["icvp"]
bounds = re.fullmatch(r"\{\{(-?[0-9]+), (-?[0-9]+)\}, \{([0-9]+), ([0-9]+)\}\}", window["WindowBounds"])
if not bounds:
    raise SystemExit("Installer Finder bounds are invalid")
width, height = map(int, bounds.groups()[2:])
# Measured on the supported macOS 26 Finder with all optional bars hidden.
title_bar_height = 32
for flag in ["ShowStatusBar", "ShowToolbar", "ShowTabView", "ShowSidebar", "ShowPathbar"]:
    if window.get(flag) is not False:
        raise SystemExit(f"Installer must hide {flag} to keep the artwork viewport predictable")
if icons["scrollPositionX"] != 0 or icons["scrollPositionY"] != 0:
    raise SystemExit("Installer must open without a saved scroll offset")
if width < artwork_size[0] or height - title_bar_height < artwork_size[1]:
    raise SystemExit(f"Installer clips artwork: window {width} × {height} pt leaves "
                     f"{height - title_bar_height} pt below the title bar; "
                     f"artwork needs {artwork_size[1]:g} pt")
print(json.dumps({"window_points": [width, height], "artwork_points": artwork_size,
                  "title_bar_points": title_bar_height,
                  "available_content_height": height - title_bar_height,
                  "scroll_offset": [0, 0], "artwork_fits": True}, indent=2))
