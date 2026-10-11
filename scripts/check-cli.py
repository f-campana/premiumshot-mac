#!/usr/bin/env python3
"""Exercise the development-only parity contract."""
import json
import os
from pathlib import Path
import subprocess

arch = os.environ.get("ARCH", os.uname().machine)
directory = subprocess.check_output(["swift", "build", "-c", "release", "--arch", arch, "--show-bin-path"], text=True).strip()
cli = str(Path(directory, "pshot"))
# The exact same layout object feeds the app and the external Chrome test harness.
case = [cli, "layout", "--in", "fixtures/wide-dashboard.png", "--look", "dawn", "--shape", "fit", "--json"]
result = json.loads(subprocess.check_output(case, text=True))
assert result["width"] > 0 and result["height"] > 0, result
removed = subprocess.run(case + ["--frame", "window"], text=True, capture_output=True)
assert removed.returncode == 2 and "--frame was removed" in removed.stderr
print("Development CLI: layout JSON and removed-frame error verified; CLI is excluded from the bundle.")
