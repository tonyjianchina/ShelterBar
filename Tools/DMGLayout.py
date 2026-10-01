"""Write and verify Finder metadata without opening Finder or launching the app."""

import argparse
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias


WINDOW = {
    "WindowBounds": "{{180, 120}, {720, 510}}",
    "ShowStatusBar": False,
    "ShowToolbar": False,
    "ShowPathbar": False,
    "ShowSidebar": False,
    "ShowTabView": False,
    "ContainerShowSidebar": False,
    "PreviewPaneVisibility": False,
    "SidebarWidth": 180,
}
ICONS = {
    "viewOptionsVersion": 1,
    "backgroundType": 2,
    "arrangeBy": "none",
    "iconSize": 112.0,
    "textSize": 16.0,
    "labelOnBottom": True,
    "showIconPreview": False,
    "showItemInfo": False,
    "gridOffsetX": 0.0,
    "gridOffsetY": 0.0,
    "gridSpacing": 100.0,
    "scrollPositionX": 0.0,
    "scrollPositionY": 0.0,
}
POSITIONS = {"ShelterBar.app": (170, 286), "Applications": (550, 286)}


def verify(mount: Path) -> None:
    with DSStore.open(str(mount / ".DS_Store"), "r") as metadata:
        assert metadata["."]["bwsp"] == WINDOW, "Unexpected installer window layout"
        assert metadata["."]["icvl"] == (b"type", b"icnv"), "Expected icon view"
        options = metadata["."]["icvp"]
        for key, value in ICONS.items():
            assert options[key] == value, f"Unexpected icon option: {key}"
        alias = Alias.from_bytes(options["backgroundImageAlias"])
        assert alias.target.filename == "ShelterBar.png", "Unexpected background alias"
        assert alias.target.cnid == (mount / ".background/ShelterBar.png").stat().st_ino, \
            "Background alias does not reference the packaged image"
        for name, position in POSITIONS.items():
            assert metadata[name]["Iloc"] == position, f"Unexpected position: {name}"
    print("Verified drag-to-Applications layout and background alias")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mount", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if not args.verify:
        alias = Alias.for_file(str(args.mount / ".background/ShelterBar.png"))
        with DSStore.open(str(args.mount / ".DS_Store"), "w+") as metadata:
            metadata["."]["vSrn"] = ("long", 1)
            metadata["."]["bwsp"] = WINDOW
            metadata["."]["icvp"] = dict(ICONS, backgroundImageAlias=alias.to_bytes())
            metadata["."]["icvl"] = ("type", "icnv")
            for name, position in POSITIONS.items():
                metadata[name]["Iloc"] = position
    verify(args.mount)


if __name__ == "__main__":
    main()
