# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path


ROOT = Path(SPECPATH).parents[1]
SRC = ROOT / "src"
ICON = ROOT / "packaging" / "pyinstaller" / "AppIcon.icns"


a = Analysis(
    [str(SRC / "harsharkngx" / "__main__.py")],
    pathex=[str(SRC)],
    binaries=[],
    datas=[],
    hiddenimports=[
        "darkdetect",
        "harsharkngx.mcp_server",
        "lxml.etree",
        "lxml._elementpath",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    # Compile collected Python modules with production optimizations to trim the bundle.
    optimize=2,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="HarsharkNGX",
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=True,
    upx=True,
    upx_exclude=[],
    name="HarsharkNGX",
)
app = BUNDLE(
    coll,
    name="HarsharkNGX.app",
    icon=str(ICON) if ICON.exists() else None,
    bundle_identifier="com.teezyyoxo.harsharkngx",
    info_plist={
        "CFBundleDisplayName": "HarsharkNGX",
        "CFBundleName": "HarsharkNGX",
        "CFBundleShortVersionString": "1.7.0",
        "CFBundleVersion": "1.7.0",
        "NSHighResolutionCapable": True,
    },
)
