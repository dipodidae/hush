#!/usr/bin/env python3
"""menu_map.py: decode the BG3 tilemap of a gfx snapshot (<name>.vram/.cgram/.ppu.txt from tools/art/menu_snap.lua) and say which
sheet cell each tile came from (pixel match of the 2bpp chr at VRAM $E000 against gfx/src hud/GFX_DC DD DE and font/FONT).

  .venv/bin/python tools/art/menu_map.py build/art_research/menu/menu_snap/menu_open [--tiles]
Output: per screen (32x32 words at VRAM $C000/$C400/$C800/$CC00) a grid of 'tile/pal' words, then the tile usage table.
"""
from __future__ import annotations
import sys
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def sheet_tiles(path: Path):
    im = Image.open(path)
    w, h = im.size
    px = list(im.convert("P").tobytes()) if im.mode != "P" else list(im.tobytes())
    out = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            out.append(tuple(px[(ty * 8 + y) * w + tx * 8 + x] for y in range(8) for x in range(8)))
    return out


def vram_tile(v: bytes, base: int, n: int):
    o = base + n * 16
    rows = []
    for y in range(8):
        a, b = v[o + 2 * y], v[o + 2 * y + 1]
        rows += [((a >> (7 - x)) & 1) | (((b >> (7 - x)) & 1) << 1) for x in range(8)]
    return tuple(rows)


def main():
    bases = [a for a in sys.argv[1:] if not a.startswith("--")]
    grid = "--grid" in sys.argv
    allused = defaultdict(set)
    for base in bases:
        one(base, grid, allused)
    if len(bases) > 1:
        print("=== union over", len(bases), "snapshots:", " ".join(f"{t:03X}p{p}" for (t, p) in sorted(allused)))


def one(base, grid, allused):
    v = open(base + ".vram", "rb").read()
    srcs = {}
    for k, p in {"DC": "gfx/src/hud/GFX_DC.png", "DD": "gfx/src/hud/GFX_DD.png", "DE": "gfx/src/hud/GFX_DE.png", "FONT": "gfx/src/font/FONT.png"}.items():
        srcs[k] = sheet_tiles(ROOT / p)
    lookup = defaultdict(list)
    for k, tl in srcs.items():
        for i, t in enumerate(tl):
            lookup[t].append(f"{k}{i}")
    # vram chr $E000: tile ids
    used = defaultdict(list)
    for scr, addr in enumerate((0xC000, 0xC800, 0xD000, 0xD800)):
        if grid:
            print(f"--- BG3 screen {scr} (VRAM ${addr:04X})")
        for r in range(32):
            if grid and all((v[addr + (r * 32 + c) * 2] | (v[addr + (r * 32 + c) * 2 + 1] << 8)) in (0, 0x207F, 0x007F) for c in range(32)):
                continue
            line = []
            for c in range(32):
                w = v[addr + (r * 32 + c) * 2] | (v[addr + (r * 32 + c) * 2 + 1] << 8)
                t, pal, fl = w & 0x3FF, (w >> 10) & 7, (w >> 14) & 3
                line.append(f"{t:03X}{'HVB'[fl-1] if fl in (1,2) else ('B' if fl==3 else ' ')}{pal}" if w != 0x207F and w != 0 else "  .  ")
                if w not in (0, 0x207F):
                    used[(t, pal)].append((scr, c, r))
                    allused[(t, pal)].add(base)
            if grid:
                print(f"{r:2d} " + " ".join(line))
    print("--- " + base + " tile usage: tile pal -> sheet cell candidates, count, first positions")
    for (t, pal), pos in sorted(used.items()):
        tt = vram_tile(v, 0xE000, t)
        print(f"{t:03X} p{pal} n={len(pos):3d} {lookup.get(tt, ['?'])[:4]} {pos[:3]}")


if __name__ == "__main__":
    main()
