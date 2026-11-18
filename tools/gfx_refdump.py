#!/usr/bin/env python3
"""Extract vanilla graphics REFERENCE data into build/ref/ (gitignored).

  gfx_refdump.py            decompress every vanilla sheet, build metadata + hash sets

Outputs (all under build/ref/, never committed, never copied into gfx/):
  build/ref/sheets/GFX_xx.bin|link.4bpp|font.2bpp   raw decompressed vanilla sheets (pixels!)
  build/ref/tilehash.json                           hash sets of every non-trivial vanilla tile
  build/ref/palettes_full.json                      every vanilla palette row (for the leak check)
  build/ref/meta/assets.json                        METADATA ONLY: addresses, sizes, bpp, tile
                                                    counts, which tile indices are non-blank.
  build/ref/meta/palette_layout.json                METADATA ONLY: palette table structure.

The art agent may read build/ref/meta/ only. Pixels never leave build/ref/.
Facts and citations: docs/gfx/formats.md.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, die, verify_vanilla  # noqa: E402
from gfxlib import (  # noqa: E402
    BLANK, FONT_ADDR, FONT_SIZE, LAST_SHEET, LINK_ADDR, LINK_SIZE, UNCOMPRESSED, WORLDMAP_ADDR,
    BG_COUNT, SPR_OFFSET, decode_tile, decompress, pc, sheet_bpp, sheet_pointer, tile_bytes, tiles_of,
)

REF = ROOT / "build" / "ref"
VENDOR = ROOT / "vendor" / "usdasm"


def tile_key(rows) -> str:
    return hashlib.sha1(bytes(v for r in rows for v in r)).hexdigest()[:16]


def variants(rows):
    """Tile + its flips (H, V, HV): VRAM tiles may be stored flipped relative to vanilla."""
    h = [r[::-1] for r in rows]
    v = rows[::-1]
    hv = [r[::-1] for r in rows[::-1]]
    return [rows, h, v, hv]


def trivial(rows) -> bool:
    return len({x for r in rows for x in r}) <= 1


def sheet_slots(rom: bytes):
    """Unique sheet data slots: id -> dict(addr, comp_len, capacity). Aliases (bg 71/72) noted."""
    ids = list(range(0, LAST_SHEET + 1))
    by_addr: dict[int, list[int]] = {}
    for i in ids:
        by_addr.setdefault(sheet_pointer(rom, i), []).append(i)
    slots = {}
    for addr, owners in by_addr.items():
        first = max(owners)   # aliases: bg 0x71/0x72 are GFX_DD/GFX_DE
        if first in UNCOMPRESSED:
            data, clen = None, 0x600
        else:
            data, clen = decompress(rom, addr)
        slots[addr] = dict(ids=owners, primary=first, addr=addr, data=data, comp_len=clen)
    order = sorted(slots)
    for n, a in enumerate(order):
        s = slots[a]
        end = pc(a) + s["comp_len"]
        nxt = pc(order[n + 1]) if n + 1 < len(order) else None
        s["capacity"] = (nxt - pc(a)) if nxt is not None and nxt - end == 0 else s["comp_len"]
    return slots


def parse_palette_layout() -> list[dict]:
    """Structure of PaletteData (bank_1B.asm:4646..): label -> rows of N colours at ROM addr."""
    path = VENDOR / "bank_1B.asm"
    if not path.exists():
        die("vendor/usdasm missing; run `make vendor`.")
    lines = path.read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("PaletteData:"))
    end = next(i for i, l in enumerate(lines) if l.startswith("SwordPaletteOffsets:"))
    label, rows = "PaletteData", []
    cur = None
    for l in lines[start + 1:end]:
        m = re.match(r"^[.#]([A-Za-z0-9_]+):?\s*$", l)
        if m:
            label = m.group(1)
            continue
        m = re.match(r"^\|([0-9A-F]{6})\|\s*dw\s+(.*)$", l)
        if m:
            n = len(re.findall(r"\$[0-9A-Fa-f]{4}", m.group(2)))
            rows.append(dict(label=label, addr=int(m.group(1), 16), n=n))
    return rows


EXTRA_PALETTES = [  # (name, snes addr, bytes) verified in vendor/usdasm (see docs/gfx/formats.md)
    ("Palettes_LWMAP", 0x0ADB27, None), ("Palettes_DWMAP", 0x0ADC27, None),
    ("Palettes_Triforce", 0x0CC425, 16),
    ("Palettes_BlueThunder1", 0x0EF4EB, 14), ("Palettes_BlueThunder2", 0x0EF4F9, 14),
    ("Palettes_BlueThunder3", 0x0EF507, 14), ("Palettes_BlueThunder4", 0x0EF515, 14),
    ("Palettes_BlueThunder5", 0x0EF523, 14), ("Palettes_GanonTowerFlash", 0x0EF531, 80),
]


def main() -> int:
    rom = verify_vanilla()
    (REF / "sheets").mkdir(parents=True, exist_ok=True)
    (REF / "meta").mkdir(parents=True, exist_ok=True)
    slots = sheet_slots(rom)

    assets, hashes = [], {"3": set(), "4": set(), "2": set()}
    attrib: dict[str, str] = {}      # tile hash -> "GFX_xx:tile" (first owner), for leak attribution

    def add(kind_id, addr, data, bpp, comp_len, capacity, extra=None):
        tl = tiles_of(data, bpp)
        nonblank = []
        for n, t in enumerate(tl):
            rows = decode_tile(t, bpp)
            if any(v for r in rows for v in r):
                nonblank.append(n)
            if not trivial(rows):
                for var in variants(rows):
                    k = tile_key(var)
                    hashes[str(bpp)].add(k)
                    attrib.setdefault(f"{bpp}:{k}", f"{kind_id}:{n:02X}")
        a = dict(id=kind_id, addr=addr, bpp=bpp, compressed=comp_len is not None and extra is None or False,
                 data_bytes=len(data), comp_bytes=comp_len, capacity=capacity,
                 tiles=len(tl), nonblank_tiles=nonblank)
        a.update(extra or {})
        assets.append(a)

    for a, s in sorted(slots.items()):
        i = s["primary"]
        bpp = sheet_bpp(i)
        if i in UNCOMPRESSED:
            data = rom[pc(a):pc(a) + 0x600]
            cl, comp = 0x600, False
        else:
            data, cl, comp = s["data"], s["comp_len"], True
        (REF / "sheets" / f"GFX_{i:02X}.bin").write_bytes(data)
        add(f"GFX_{i:02X}", a, data, bpp, cl, s["capacity"],
            dict(compressed=comp, aliases=[f"GFX_{j:02X}" for j in s["ids"] if j != i],
                 table_ids=s["ids"]))

    link = rom[pc(LINK_ADDR):pc(LINK_ADDR) + LINK_SIZE]
    (REF / "sheets" / "link.4bpp").write_bytes(link)
    add("LINK", LINK_ADDR, link, 4, LINK_SIZE, LINK_SIZE, dict(compressed=False))
    font = rom[pc(FONT_ADDR):pc(FONT_ADDR) + FONT_SIZE]
    (REF / "sheets" / "font.2bpp").write_bytes(font)
    add("FONT", FONT_ADDR, font, 2, FONT_SIZE, FONT_SIZE, dict(compressed=False))
    wm = rom[pc(WORLDMAP_ADDR):pc(WORLDMAP_ADDR) + 0x4000]
    (REF / "sheets" / "worldmap.8bpp").write_bytes(wm)
    assets.append(dict(id="WORLDMAP", addr=WORLDMAP_ADDR, bpp=8, compressed=False, data_bytes=0x4000,
                       comp_bytes=0x4000, capacity=0x4000, tiles=0x4000 // 64, nonblank_tiles=[]))

    # palettes
    layout = parse_palette_layout()
    full = []
    for r in layout:
        p = pc(r["addr"])
        cols = [int.from_bytes(rom[p + 2 * k:p + 2 * k + 2], "little") for k in range(r["n"])]
        full.append(dict(label=r["label"], addr=r["addr"], colors=cols))
    extra_layout = []
    for name, addr, nbytes in EXTRA_PALETTES:
        if nbytes is None:   # map palettes: run until the next label
            nbytes = 0x100 if name == "Palettes_LWMAP" else 0x100
        p = pc(addr)
        for off in range(0, nbytes, 14 if nbytes % 14 == 0 and nbytes != 16 else 16):
            w = 14 if nbytes % 14 == 0 and nbytes != 16 else 16
            n = w // 2
            cols = [int.from_bytes(rom[p + off + 2 * k:p + off + 2 * k + 2], "little") for k in range(n)]
            full.append(dict(label=name, addr=addr + off, colors=cols))
        extra_layout.append(dict(label=name, addr=addr, bytes=nbytes))
    (REF / "palettes_full.json").write_text(json.dumps(full))
    (REF / "meta" / "palette_layout.json").write_text(json.dumps(dict(layout=layout, extra=extra_layout), indent=1))
    (REF / "tilehash.json").write_text(json.dumps({"sets": {k: sorted(v) for k, v in hashes.items()}, "attrib": attrib}))
    (REF / "meta" / "assets.json").write_text(json.dumps(assets, indent=1))
    print(f"refdump: {len(assets)} assets, tiles hashed: " +
          ", ".join(f"{k}bpp={len(v)}" for k, v in hashes.items()) + f", palette rows: {len(full)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
