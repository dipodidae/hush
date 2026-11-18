#!/usr/bin/env python3
"""Insert HUSH's graphics (gfx/src/**) and palettes (gfx/src/palettes/*.yaml) into a built ROM.

  gfx_insert.py apply [rom]      patch build/hush.sfc in place (called by tools/build.py)
  gfx_insert.py ledger           print the merged ROM regions this step writes (FREESPACE.md rows)
  gfx_insert.py report           sizes per asset: placeholder bytes vs slot capacity

For every inventory asset with `insert: true` in its brief:
  PNG --(tools/gfx_convert.py: SNES limits + colour roles)--> planar tiles at the slot's bit depth
      --(tools/gfx_compress.py, if the slot is compressed)--> bytes, padded with $FF to the slot size.
If the compressed data is larger than the slot, the build FAILS with the byte counts: there is no
slack between sheets (docs/gfx/formats.md), so a relocation plan needs a human decision.
Pointer tables are never changed. Palettes are written in place over the vanilla colour words.
Slot addresses come from docs/gfx/inventory.yaml and are cross-checked against the ROM's own
GFXSheetPointers table ($00CF80) before anything is written.
Set HUSH_GFX=off to skip insertion (control builds for the leak detector).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from common import BUILT_ROM, die, snes_to_pc, pc_to_snes  # noqa: E402
from gfx_compress import compress  # noqa: E402
from gfx_convert import process  # noqa: E402
from gfxlib import sheet_pointer  # noqa: E402
import gfx_title  # noqa: E402

INV = ROOT / "docs" / "gfx" / "inventory.yaml"
SRC = ROOT / "gfx" / "src"


def hexrgb(s: str):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def bgr555(rgb) -> int:
    r, g, b = (c >> 3 for c in rgb)
    return (b << 10) | (g << 5) | r


CACHE = ROOT / "build" / "gfx_cache"


def cached_compress(data: bytes) -> bytes:
    """Compression is deterministic but slow; cache by content hash (build/ is gitignored)."""
    import hashlib
    key = hashlib.sha1(data).hexdigest()
    f = CACHE / key
    if f.exists():
        return f.read_bytes()
    blob = compress(data)
    CACHE.mkdir(parents=True, exist_ok=True)
    f.write_bytes(blob)
    return blob


def collect(rom: bytes | None = None):
    """Return (patches, notes). patches = list of (pc_offset, bytes, label)."""
    inv = yaml.safe_load(INV.read_text())
    patches, notes, errors, warnings = [], [], [], []
    for e in inv["assets"]:
        kind_dir = SRC / e["kind"]
        png = kind_dir / f"{e['id']}.png"
        brief_p = kind_dir / f"{e['id']}.yaml"
        if not png.exists() or not brief_p.exists():
            errors.append(f"{e['id']}: missing {png.relative_to(ROOT)} (run tools/gfx_placeholder.py)")
            continue
        brief = yaml.safe_load(brief_p.read_text())
        if not brief.get("insert", True):
            notes.append((e["id"], "skipped (insert: false)", 0, e.get("capacity_bytes") or 0))
            continue
        addr = int(e["rom"][1:], 16)
        if e["id"].startswith("GFX_") and rom is not None:
            sid = int(e["id"][4:], 16)
            if sheet_pointer(rom, sid) != addr:
                errors.append(f"{e['id']}: inventory address {e['rom']} != ROM pointer table ${sheet_pointer(rom, sid):06X}")
                continue
        data = process(png, write=False, errors=errors, warnings=warnings)
        if data is None:
            continue
        cap = e["capacity_bytes"]
        if e["compressed"]:
            blob = cached_compress(data)
            if len(blob) > cap:
                errors.append(f"{e['id']}: compressed {len(blob)} B > slot {cap} B; needs a relocation plan "
                              f"(human decision, see docs/gfx/formats.md 'Slot capacity')")
                continue
            blob_raw = blob
            blob = blob + b"\xFF" * (cap - len(blob))
            used = len(blob_raw)
        else:
            if e["bpp"] == 3 and data[0] != 0xFF:
                errors.append(f"{e['id']}: uncompressed 3bpp sheet must start with $FF (tile 0 row 0 = colour 1): the game also "
                              f"runs the decompressor over it (InitializeTilesets); anything else can overwrite WRAM")
                continue
            if len(data) != cap:
                errors.append(f"{e['id']}: {len(data)} B != uncompressed slot {cap} B (wrong size/bpp)")
                continue
            blob, used = data, len(data)
        patches.append((snes_to_pc(addr), blob, e["id"]))
        notes.append((e["id"], "ok", used, cap))
    # title screen tilemap (cell layout for the logo sheets; tools/gfx_title.py)
    patches.append((snes_to_pc(gfx_title.STREAM_PC_START_SNES), gfx_title.stream(), "TITLE_TILEMAP"))
    # palettes
    for f in sorted((SRC / "palettes").glob("*.yaml")):
        doc = yaml.safe_load(f.read_text())
        for gid, g in doc["groups"].items():
            for addr_s, cols in zip(g["rom_rows"], g["colours"]):
                blob = b"".join(bgr555(hexrgb(c)).to_bytes(2, "little") for c in cols)
                patches.append((snes_to_pc(int(addr_s[1:], 16)), blob, gid))
    return patches, notes, errors, warnings


def regions(patches):
    spans = sorted((p, p + len(b)) for p, b, _ in patches)
    merged = []
    for a, b in spans:
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return merged


def apply(rom_path: Path) -> None:
    if os.environ.get("HUSH_GFX") == "off":
        print("gfx: HUSH_GFX=off, vanilla graphics left in place (control build)")
        return
    rom = bytearray(rom_path.read_bytes())
    patches, notes, errors, warnings = collect(bytes(rom))
    if errors:
        for e in errors[:40]:
            print(f"  - {e}", file=sys.stderr)
        die(f"graphics insertion failed ({len(errors)} problem(s)); build/hush.sfc not modified.")
    seen = {}
    for p, blob, label in patches:
        for q, (q_end, ql) in seen.items():
            if p < q_end and q < p + len(blob):
                die(f"gfx patches overlap: {label} and {ql}")
        seen[p] = (p + len(blob), label)
        rom[p:p + len(blob)] = blob
    rom_path.write_bytes(rom)
    sheets = [n for n in notes if n[1] == "ok"]
    print(f"gfx: inserted {len(sheets)} sheets, {len(patches) - len(sheets)} palette rows; "
          f"{sum(len(b) for _, b, _ in patches)} bytes written in {len(regions(patches))} regions")


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "report"
    if cmd == "apply":
        apply(Path(sys.argv[2]) if len(sys.argv) > 2 else BUILT_ROM)
        return 0
    patches, notes, errors, warnings = collect(None)
    if cmd == "ledger":
        for a, b in regions(patches):
            print(f"| ${pc_to_snes(a):06X} | ${pc_to_snes(b - 1):06X} | hook | tools/gfx_insert.py | "
                  f"A0 graphics/palette data replaced in place ({b - a} bytes) |")
        return 0
    if cmd == "report":
        tot = 0
        for i, st, used, cap in notes:
            print(f"{i:22s} {st:22s} {used:6d} / {cap:6d}")
            tot += used
        for e in errors:
            print("ERROR", e)
        print(f"total placeholder bytes: {tot}")
        return 1 if errors else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
