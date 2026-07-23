from __future__ import annotations

import subprocess
import sys
import tempfile
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

    # Preserve the visible transparent PNG exactly, but clear RGB data hidden behind
    # transparent pixels. Without this normalization, macOS can surface an old matte
    # while rendering the generated .icns.
    from PySide6.QtGui import QImage

    source_image = QImage(str(SOURCE_ICON))
    if source_image.isNull():
        raise RuntimeError(f"Unable to read icon source: {SOURCE_ICON}")

    ICONSET.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp_dir:
        normalized_source = Path(temp_dir) / "AppIcon.png"
        normalized_image = source_image.convertToFormat(
            QImage.Format.Format_RGBA8888_Premultiplied
        ).convertToFormat(QImage.Format.Format_RGBA8888)
        if not normalized_image.save(str(normalized_source), "PNG"):
            raise RuntimeError(f"Unable to normalize icon source: {SOURCE_ICON}")

        for size, filename in ICON_SIZES:
            subprocess.check_call(
                [
                    "sips",
                    "-z",
                    str(size),
                    str(size),
                    str(normalized_source),
                    "--out",
                    str(ICONSET / filename),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                cwd=ROOT,
            )
    # iconutil exits successfully without replacing an existing .icns on some macOS versions.
    # Remove the generated artifact first so every build uses the tracked transparent source.
    ICNS.unlink(missing_ok=True)
    subprocess.check_call(
        ["iconutil", "--convert", "icns", "--output", str(ICNS), str(ICONSET)],
        cwd=ROOT,
    )


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
