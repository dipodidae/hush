#!/usr/bin/env python3
"""autotile_art: paint the T0 tileset into gfx/src/bg_tileset and render previews (design/tiles.md). The art itself lives in tools/autotile.py.

  tools/art/autotile_art.py apply      clear GFX_00 / GFX_10 / GFX_06 and paint every unique 8x8 cell of the tileset (indexed writes, palette untouched)
  tools/art/autotile_art.py preview    write build/art_preview/t0/*.png: mock rooms (gallery + r05/r09/r14/r18, with decoration) in the room palettes

Only original pixels; the sheets keep their PNG palette. ROM insertion is done by tools/gfx_insert.py as before (make build).
NOTE: `make gfx` regenerates placeholders over these sheets; run `apply` again afterwards.
"""
from __future__ import annotations

import sys
from pathlib import Path

import yaml
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import autotile as A  # noqa: E402

ROOT = A.ROOT
SHEETS = ROOT / "gfx" / "src" / "bg_tileset"
OUT = ROOT / "build" / "art_preview" / "t0"


def apply() -> None:
    for stem, cells in A.sheet_cells().items():
        path = SHEETS / f"{stem}.png"
        im = Image.open(path)
        assert im.mode == "P", path
        px = im.load()
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                px[x, y] = 0                       # clear: old placeholder / E5 art is unused now (smaller compressed sheet)
        for (cx, cy), t in cells.items():
            for y in range(8):
                for x in range(8):
                    assert 0 <= t[y][x] <= 7
                    px[cx * 8 + x, cy * 8 + y] = t[y][x]
        im.save(path, transparency=0)
        print(f"{stem}: {len(cells)} / 64 cells painted")
    print(f"{len(A.CHARS)} chars, {len(A.CELLS)} unique 8x8 cells (H-flip dedup)")


def rgb(h):
    return tuple(int(str(h)[i:i + 2], 16) for i in (0, 2, 4))


def palette_row(group, row):
    col = A.PAL[group]["colours"][2 * (row - 2) + 1]
    return [(0, 0, 0)] + [rgb(col[i]) for i in range(1, 8)]


def render(chars, group="pal_dungeon_00"):
    img = Image.new("RGB", (A.W * 16, A.H * 16), (0, 0, 0))
    px = img.load()
    pals = {}
    for ty, row in enumerate(chars):
        for tx, ci in enumerate(row):
            cell, fl, prow, _, _ = A.CHARS[ci]
            t = A.CELLS[cell]
            t = A.hflip(t) if fl else t
            pal = pals.setdefault(prow, palette_row(group, prow))
            for y in range(8):
                for x in range(8):
                    px[tx * 8 + x, ty * 8 + y] = pal[t[y][x]]
    return img


GALLERY = [
    "################",
    "################",
    "#.......##.....#",
    "#.OOO...##.WWW.#",
    "#OOOOO.p##WWWWW#",
    "#.OOO......WWW.#",
    "#.......#D#...##",
    "####.####......#",
    "#...S..#.......#",
    "#.O..#...W.....#",
    "#...###..XOO...#",
    "#..#####.......#",
    "#.a............#",
    "################",
]


def preview() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = {"gallery": ("gallery", GALLERY, "pal_dungeon_00", False)}
    for rid, grp in (("r01", "pal_dungeon_00"), ("r05", "pal_dungeon_00"), ("r09", "pal_dungeon_04"), ("r14", "pal_dungeon_04"), ("r18", "pal_dungeon_05"), ("final", "pal_dungeon_05")):
        p = ROOT / "design" / "rooms" / f"{rid}.yaml"
        if p.exists():
            d = yaml.safe_load(p.read_text())
            jobs[rid] = (d["id"], d["grid"], grp, d["lighting"] == "lit")
    for name, (rid, grid, grp, lit) in jobs.items():
        chars, plan = A.place(rid, grid, lit)
        render(chars, grp).save(OUT / f"room_{name}.png")
    sheet = Image.new("RGB", (16 * 36, ((len(A.CELLS) + 15) // 16) * 36), (24, 24, 30))
    pal = palette_row("pal_dungeon_00", 7)
    for i, t in enumerate(A.CELLS):
        for y in range(8):
            for x in range(8):
                for dy in range(4):
                    for dx in range(4):
                        sheet.putpixel(((i % 16) * 36 + x * 4 + dx, (i // 16) * 36 + y * 4 + dy), pal[t[y][x]])
    sheet.save(OUT / "contact_sheet.png")
    print("previews ->", OUT)


if __name__ == "__main__":
    {"apply": apply, "preview": preview}[sys.argv[1] if len(sys.argv) > 1 else "preview"]()
