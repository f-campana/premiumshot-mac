"""Write Finder layout using the background's actual identity on this mounted image."""
from pathlib import Path
import sys
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1]).resolve()
background = Alias.for_file(str(mount / ".background/Installer.tiff"))
# Keep the real volume/file IDs, but never embed the source checkout's mount path.
background.volume.posix_path = b"/Volumes/PremiumShot"
background.target.user_home_prefix_len = None
destination = mount / ".DS_Store"
with DSStore.open(str(destination), "w+") as layout:
    layout["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowToolbar": False, "ShowTabView": False,
        "ContainerShowSidebar": False, "ShowSidebar": False,
        "PreviewPaneVisibility": False, "ShowPathbar": False, "SidebarWidth": 180,
        # Finder saves the full frame: 400 pt artwork plus its 32 pt title bar.
        "WindowBounds": "{{200, 200}, {600, 432}}",
    }
    layout["."]["icvp"] = {
        "backgroundType": 2, "backgroundImageAlias": background.to_bytes(),
        # Finder requires the complete icon-view dictionary, including RGB defaults.
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "gridSpacing": 54.0, "textSize": 12.0, "gridOffsetX": 0.0,
        "gridOffsetY": 0.0, "showItemInfo": False, "viewOptionsVersion": 1,
        "arrangeBy": "none", "labelOnBottom": True, "iconSize": 80.0,
        "showIconPreview": True,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    }
    layout["."]["vSrn"] = ("long", 1)
    layout["."]["icvl"] = ("type", b"icnv")
    layout["PremiumShot.app"]["Iloc"] = (180, 190)
    layout["Applications"]["Iloc"] = (420, 190)
    layout["Read me first.txt"]["Iloc"] = (555, 358)
