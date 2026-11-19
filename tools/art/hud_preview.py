#!/usr/bin/env python3
"""hud_preview.py: compose the in-room HUD (BG3 tilemap rows 2-7) from gfx/src/hud sheets + gfx/src/palettes/hud.yaml,
the way the vanilla tilemap/HUD code lays it out (docs/gfx/hud_map.md), without running the emulator.

  .venv/bin/python tools/art/hud_preview.py                 # build/art_preview/hud_preview.png (3 tool stages, 3x)
  .venv/bin/python tools/art/hud_preview.py --zoom 6 --out /tmp/x.png
"""
from __future__ import annotations

import argparse
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HUD = ROOT / "gfx" / "src" / "hud"
BG = (0x10, 0x10, 0x38)  # what the room shows behind the HUD (CGRAM $101038-ish indigo)


def groups():
    d = yaml.safe_load((ROOT / "gfx/src/palettes/hud.yaml").read_text())["groups"]
    out = []
    for i in range(8):
        c = d["pal_hud_%02X" % i]["colours"][0]
        out.append([tuple(int(str(h).zfill(6)[k:k + 2], 16) & 0xF8 for k in (0, 2, 4)) for h in c])
    return out


def sheets():
    return {n: Image.open(HUD / f"GFX_{n}.png").convert("P") for n in ("DD", "DE")}


def tile(sh, t):
    n, i = ("DD", t) if t < 128 else ("DE", t - 128)
    x, y = (i % 16) * 8, (i // 16) * 8
    return sh[n].crop((x, y, x + 8, y + 8))


def e(tid, pal, h=0, v=0):
    return (tid, pal, h, v)


def hud_cells(tool: str, hearts=(3, 6), digits=None):
    """{(col,row): (tile, pal, hflip, vflip)} for tilemap rows 2-7 (buffer rows 0-5); tool = none|darts|ink;
    hearts = (containers, half hearts of health)"""
    c = {}
    c[(2, 2)] = e(0x50, 2); c[(3, 2)] = e(0x56, 2, 0, 1); c[(4, 2)] = e(0x52, 2)
    c[(5, 2)] = e(0x5B, 2); c[(6, 2)] = e(0x5B, 2); c[(7, 2)] = e(0x5C, 2)
    for r in (3, 4):
        c[(2, r)] = e(0x54, 2); c[(4, r)] = e(0x58, 2); c[(7, r)] = e(0x5D, 2)
    c[(2, 5)] = e(0x54, 2); c[(4, 5)] = e(0x59, 2); c[(5, 5)] = e(0x5B, 2, 0, 1); c[(6, 5)] = e(0x5B, 2, 0, 1)
    c[(7, 5)] = e(0x5C, 2, 0, 1)
    c[(2, 6)] = e(0x54, 2); c[(4, 6)] = e(0x54, 2, 1)
    c[(2, 7)] = e(0x50, 2, 0, 1); c[(3, 7)] = e(0x56, 2); c[(4, 7)] = e(0x50, 2, 1, 1)
    for r in (3, 4, 5, 6):
        c[(3, r)] = e(0xF5, 7)
    if tool == "darts":
        c[(5, 3)] = e(0xBA, 2); c[(6, 3)] = e(0x4A, 2); c[(5, 4)] = e(0x49, 2); c[(6, 4)] = e(0xCB, 2)
    elif tool == "ink":
        c[(5, 3)] = e(0xB2, 3); c[(6, 3)] = e(0xB3, 3); c[(5, 4)] = e(0xC2, 3); c[(6, 4)] = e(0xC2, 3, 1)
    c[(9, 2)] = e(0xA8, 7)
    c[(12, 2)] = e(0x88, 3); c[(13, 2)] = e(0x89, 3)
    c[(15, 2)] = e(0xA7, 0); c[(16, 2)] = e(0xA9, 0)
    digits = digits or {"rup": "000", "ink": "00", "dart": "00"}
    for i, ch in enumerate(digits["rup"]):
        c[(8 + i, 3)] = e(0x90 + int(ch), 1)
    for i, ch in enumerate(digits["ink"]):
        c[(12 + i, 3)] = e(0x90 + int(ch), 1)
    for i, ch in enumerate(digits["dart"]):
        c[(15 + i, 3)] = e(0x90 + int(ch), 1)
    c[(22, 2)] = e(0x8B, 2); c[(23, 2)] = e(0x8F, 2); c[(24, 2)] = e(0xAB, 1); c[(25, 2)] = e(0xAC, 1)
    c[(26, 2)] = e(0x8F, 2, 1); c[(27, 2)] = e(0x8B, 2, 1)
    mx, hp = hearts
    for i in range(mx):
        full = 2 * (i + 1) <= hp
        half = (not full) and 2 * i + 1 <= hp
        c[(20 + i, 3)] = e(0xA0 if full else 0xA1 if half else 0xA2, 1)
    return c


def render(cells, zoom, sh, pal):
    im = Image.new("RGB", (32 * 8, 6 * 8), BG)
    px = im.load()
    for (col, row), (t, p, h, v) in cells.items():
        tl = tile(sh, t)
        if h:
            tl = tl.transpose(Image.FLIP_LEFT_RIGHT)
        if v:
            tl = tl.transpose(Image.FLIP_TOP_BOTTOM)
        for y in range(8):
            for x in range(8):
                i = tl.getpixel((x, y))
                if i:
                    px[col * 8 + x, (row - 2) * 8 + y] = pal[p][i]
    return im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zoom", type=int, default=3)
    ap.add_argument("--out", default=str(ROOT / "build/art_preview/hud_preview.png"))
    a = ap.parse_args()
    sh, pal = sheets(), groups()
    stages = [
        render(hud_cells("none"), a.zoom, sh, pal),
        render(hud_cells("darts", digits={"rup": "000", "ink": "00", "dart": "12"}), a.zoom, sh, pal),
        render(hud_cells("ink", hearts=(3, 5), digits={"rup": "000", "ink": "07", "dart": "12"}), a.zoom, sh, pal),
    ]
    out = Image.new("RGB", (stages[0].width, sum(s.height for s in stages) + 4 * (len(stages) - 1)), (60, 60, 60))
    y = 0
    for s in stages:
        out.paste(s, (0, y)); y += s.height + 4
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    out.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
