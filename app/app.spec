# -*- mode: python ; coding: utf-8 -*-
import json
from pathlib import Path

ROOT = Path(SPECPATH).resolve()
_manifest = json.loads((ROOT / "app_manifest.json").read_text(encoding="utf-8"))


def _datas():
    rows = [(str(ROOT / "app_manifest.json"), ".")]
    icon_rel = _manifest.get("icon_path")
    if not icon_rel or not str(icon_rel).strip():
        return rows
    ip = ROOT / Path(icon_rel)
    if not ip.is_file():
        return rows
    rel = ip.relative_to(ROOT)
    parent = rel.parent
    dest = str(parent) if parent.parts else "."
    rows.append((str(ip), dest))
    return rows


a = Analysis(
    ["main.py"],
    pathex=[str(ROOT)],
    binaries=[],
    datas=_datas(),
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name=_manifest["executable_basename"],
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=[str(ROOT / _manifest["build_ico_path"])],
)
