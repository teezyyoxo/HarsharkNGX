from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "packaging" / "pyinstaller" / "harsharkngx.spec"
SOURCE_ICON = ROOT / "packaging" / "assets" / "AppIcon_Transparent.png"
ICONSET = ROOT / "packaging" / "pyinstaller" / "AppIcon.iconset"
ICNS = ROOT / "packaging" / "pyinstaller" / "AppIcon.icns"


ICON_SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def build_macos_icon() -> None:
    if sys.platform != "darwin" or not SOURCE_ICON.exists():
        return

    ICONSET.mkdir(parents=True, exist_ok=True)
    for size, filename in ICON_SIZES:
        subprocess.check_call(
            [
                "sips",
                "-z",
                str(size),
                str(size),
                str(SOURCE_ICON),
                "--out",
                str(ICONSET / filename),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=ROOT,
        )
    subprocess.check_call(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], cwd=ROOT)


def main() -> int:
    build_macos_icon()
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--clean",
        "--noconfirm",
        str(SPEC),
    ]
    return subprocess.call(command, cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
