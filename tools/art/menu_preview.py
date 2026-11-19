#!/usr/bin/env python3
"""menu_preview.py: recompose the START item menu (or any BG3 screen) of a gfx snapshot with the CURRENT art + palettes, no rebuild needed.

  .venv/bin/python tools/art/menu_preview.py build/art_research/menu/menu_snap/menu_open out.png [--zoom 3] [--scroll 280]

Takes the BG3 tilemap (64x64, VRAM $C000, screens $800 apart) from <snapshot>.vram, the chr from gfx/src/hud/GFX_DC/DD/DE.png (tile ids
0-127 DD, 128-255 DE, 256-383 DC) and gfx/src/font/FONT.png is NOT used: dynamic text tiles (>= $180, composed by the text box code) are
copied from the snapshot. Palettes = groups pal_hud_00..07 of gfx/src/palettes/hud.yaml. Background = dark indigo (what the room shows).
The menu is shown with BG3 vscroll 280 (map row 35 at the top); --scroll 0 shows the HUD rows of the top-left screen.
"""
from __future__ import annotations

import sys
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HUD = ROOT / "gfx" / "src" / "hud"
BACK = (0x10, 0x10, 0x38)


def palettes():
    d = yaml.safe_load((ROOT / "gfx/src/palettes/hud.yaml").read_text())["groups"]
    out = []
    for i in range(8):
        c = d["pal_hud_%02X" % i]["colours"][0]
        out.append([tuple(int(str(h).zfill(6)[k:k + 2], 16) & 0xF8 for k in (0, 2, 4)) for h in c])
    return out


def sheet_tiles():
    tiles = []
    for n in ("DD", "DE", "DC"):
        im = Image.open(HUD / f"GFX_{n}.png").convert("P")
        px = im.tobytes()
        w = im.size[0]
        for ty in range(im.size[1] // 8):
            for tx in range(w // 8):
                tiles.append([[px[(ty * 8 + y) * w + tx * 8 + x] for x in range(8)] for y in range(8)])
    return tiles


def main():
    base, out = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    scroll = int(sys.argv[sys.argv.index("--scroll") + 1]) if "--scroll" in sys.argv else 280
    v = open(base + ".vram", "rb").read()
    pals = palettes()
    tiles = sheet_tiles()

    def vram_tile(t):
        o = 0xE000 + t * 16
        rows = []
        for y in range(8):
            a, b = v[(o + 2 * y) & 0xFFFF], v[(o + 2 * y + 1) & 0xFFFF]
            rows.append([((a >> (7 - x)) & 1) | (((b >> (7 - x)) & 1) << 1) for x in range(8)])
        return rows

    def entry(mx, my):
        scr = (my // 32) * 2 + (mx // 32)
        a = 0xC000 + scr * 0x800 + ((my % 32) * 32 + (mx % 32)) * 2
        return v[a] | (v[a + 1] << 8)

    img = Image.new("RGB", (256, 224), BACK)
    px = img.load()
    for sy in range(224):
        my = ((scroll + sy) // 8) % 64
        for sx in range(256):
            mx = sx // 8
            w = entry(mx, my)
            t, pal, hf, vf = w & 0x3FF, (w >> 10) & 7, (w >> 14) & 1, (w >> 15) & 1
            tx, ty = sx % 8, (scroll + sy) % 8
            if hf:
                tx = 7 - tx
            if vf:
                ty = 7 - ty
            tl = vram_tile(t) if t >= 0x180 or t >= len(tiles) else tiles[t]
            k = tl[ty][tx]
            if k:
                px[sx, sy] = pals[pal][k]
    if zoom != 1:
        img = img.resize((256 * zoom, 224 * zoom), Image.NEAREST)
    img.save(out)


main()
