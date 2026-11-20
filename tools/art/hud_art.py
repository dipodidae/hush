#!/usr/bin/env python3
"""hud_art.py: HUSH's own in-game HUD pixels (BG3, 2bpp) written into gfx/src/hud/GFX_DD.png and GFX_DE.png.

  .venv/bin/python tools/art/hud_art.py            # (re)draw every used HUD cell, validate with gfx_convert
  .venv/bin/python tools/art/hud_art.py --preview  # also write build/art_preview/hud_sheet.png (zoomed, in-game colours)

Every pixel is drawn here from ASCII art / simple geometry; nothing is read from vanilla graphics.
Only the cells listed in docs/gfx/hud_map.md are touched, the rest of both sheets stays as it is.
Tile numbers and positions do NOT change (the ROM tilemap is vanilla): only pixels and palette groups.

ASCII keys: '.' = index 0 (transparent), '1' '2' '3' = palette index 1 2 3 of the tile's palette group.
Palette groups (gfx/src/palettes/hud.yaml, one per tilemap palette bits p -> group pal_hud_0p):
  p0 dart counter icon   p1 meter cells, digits, HUSH label   p2 frame + dart item icon
  p3 ink pot icons       p7 loot gem + meter interior
Frame lines are 2 px: index 1 on the outside of a box, index 2 on the inside (shared wall: 2 2).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gfx_convert  # noqa: E402
import gfx_placeholder  # noqa: E402  single source: stealth meter cells + HUSH label

HUD = ROOT / "gfx" / "src" / "hud"

# palette stored in the two PNGs (preview palette only; in game each tile uses the group of its tilemap entry)
PNG_PALETTE = [(0, 0, 0), (0xE8, 0xE8, 0xF8), (0xA8, 0x78, 0xF0), (0x1A, 0x24, 0x56)]

# ---------------------------------------------------------------------------------------------
# digits 0-9: 5x7 glyphs, drawn at x 1..5, y 0..6, with a one pixel shadow (index 3) down-right
DIGITS = {
    0: ".###. #...# #...# #...# #...# #...# .###.",
    1: "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
    2: ".###. #...# ....# ...#. ..#.. .#... #####",
    3: ".###. #...# ....# ..##. ....# #...# .###.",
    4: "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
    5: "##### #.... ####. ....# ....# #...# .###.",
    6: ".###. #.... #.... ####. #...# #...# .###.",
    7: "##### ....# ...#. ..#.. ..#.. ..#.. ..#..",
    8: ".###. #...# #...# .###. #...# #...# .###.",
    9: ".###. #...# #...# .#### ....# ....# .###.",
}


def glyph_tile(rows: str, ink: str = "1", shadow: str = "3") -> list[str]:
    g = rows.split()
    grid = [["."] * 8 for _ in range(8)]
    for y, r in enumerate(g):
        for x, c in enumerate(r):
            if c == "#" and y + 1 < 8 and x + 2 < 8:
                grid[y + 1][x + 2] = shadow
    for y, r in enumerate(g):
        for x, c in enumerate(r):
            if c == "#":
                grid[y][x + 1] = ink
    return ["".join(r) for r in grid]


# ---------------------------------------------------------------------------------------------
# hearts (7x7 + one empty column): O = outline (3), F = fill (2), H = glint (1)
HEART_FULL = [
    ".OO.OO..",
    "OHFOFFO.",
    "OHFFFFO.",
    "OFFFFFO.",
    ".OFFFO..",
    "..OFO...",
    "...O....",
    "........",
]


def heart(kind: str) -> list[str]:
    out = []
    for y, row in enumerate(HEART_FULL):
        s = ""
        for x, c in enumerate(row):
            if c == "O":
                # outline: dark (3) around a filled part; the EMPTY part is drawn as a violet (2) outline so it still shows on dark floors
                filled = kind == "full" or (kind == "half" and x <= 3)
                s += "3" if filled else "2"
            elif c in "FH":
                keep = kind == "full" or (kind == "half" and x <= 3)
                s += ("1" if c == "H" else "2") if keep else "."
            else:
                s += "."
        out.append(s)
    return out


HEART_TURN = [  # A3: the heart turning (refill animation frame)
    "........",
    "..3.3...",
    ".32323..",
    ".32223..",
    ".32223..",
    "..323...",
    "...3....",
    "........",
]
HEART_EDGE = [  # A4: edge-on
    "........",
    "...33...",
    "...32...",
    "...32...",
    "...32...",
    "...33...",
    "....3...",
    "........",
]

# ---------------------------------------------------------------------------------------------
# frame: 2 px line (1 outside, 2 inside), meter box = cols 2-4, item box = cols 4-7 (see docs/gfx/hud_map.md)
FILL = "3"  # meter interior only (item box interior is transparent: an empty slot is tile $7F, blank)
FRAME = {
    # 0x50 meter corner, drawn top-left (V/H flips make the other three corners)
    0x50: [".......1", "......12", "......12", "......12", "......12", "......12", "......12", "......12"],
    # 0x52 junction top: top line across, wall px 0-1 going down (meter right wall = item box left wall)
    0x52: ["11111111", "22222222", "22......", "22......", "22......", "22......", "22......", "22......"],
    # 0x54 vertical wall of the meter (left: px 6-7; H flipped at col 4: px 0-1)
    0x54: ["......12"] * 8,
    # 0x56 meter edge (bottom edge as stored; V flip = top edge); interior fill above the line
    0x56: [FILL * 8] * 6 + ["22222222", "11111111"],
    # 0x58 shared wall (meter | item box)
    0x58: ["22......"] * 8,
    # 0x59 junction bottom: wall continues down to the meter, bottom line of the item box goes right
    0x59: ["22......"] * 6 + ["22222222", "21111111"],
    # 0x5B item box edge (top as stored; V flip = bottom)
    0x5B: ["11111111", "22222222"] + ["........"] * 6,
    # 0x5C item box corner top-right (V flip = bottom-right)
    0x5C: ["1111111.", "22222221"] + ["......21"] * 6,
    # 0x5D item box right wall
    0x5D: ["......21"] * 8,
    # 0xF5 (DE 117): meter interior / empty item slot
    0xF5: [FILL * 8] * 8,
}

# gauge fills (never shown while magic stays 0; reserved so a magic pickup cannot show a hex label)
GAUGE = {
    0x5E: 8, 0x5F: 2, 0x4C: 4, 0x4D: 6, 0x4E: 7,
}


def gauge_tile(h: int) -> list[str]:
    """meter tile filled h rows from the bottom: surface row index 1, body index 2, empty part = interior fill"""
    return [FILL * 8 if y < 8 - h else ("11111111" if y == 8 - h else "22222222") for y in range(8)]


# ---------------------------------------------------------------------------------------------
# icons
# ornaments either side of the label: outer cell ($8B) = small diamond + start of the line, inner cell ($8F) = line
ORN_OUTER = [
    "........",
    "........",
    "...2....",
    "..2112.2",
    "..2112.2",
    "...2....",
    "........",
    "........",
]
ORN_INNER = [
    "........",
    "........",
    "........",
    "2222222.",
    "2222222.",
    "........",
    "........",
    "........",
]

# 16x8 counter icons -----------------------------------------------------------------------
DART_MINI = [  # tiles A7 (left) A9 (right), palette group 0: 1 light teal, 2 teal; the dart points right
    "................",
    ".1..............",
    ".11....11.......",
    ".1111111111111.1",
    ".2222222222222.2",
    ".22....22.......",
    ".2..............",
    "................",
]
INK_MINI = [  # tiles 88 (left) 89 (right), palette group 3: 1 light violet, 2 violet
    ".......11.......",
    "......1111......",
    ".....222222.....",
    "....22222222....",
    "...2122222222...",
    "...2222222222...",
    "....22222222....",
    ".....222222.....",
]
INK_BIG = [  # B2 B3 / C2 C2(H): palette group 3; the bottom half is mirror-symmetric (the game H-flips C2 for the bottom right)
    "................",
    "................",
    ".....111111.....",
    ".....122221.....",
    "......2222......",
    "......2222......",
    "....22222222....",
    "...2122222222...",
    "..222222222222..",
    "..222211112222..",
    "..222213312222..",
    "..222211112222..",
    "..222222222222..",
    "...2222222222...",
    "....22222222....",
    "................",
]
GEM = [  # A8: loot gem, palette group 7: 1 white, 2 teal
    "........",
    "..1111..",
    ".122221.",
    "12122221",
    "12222221",
    ".122221.",
    "..1221..",
    "...22...",
]


def dart_big() -> list[str]:
    """16x16 Hush Dart pointing right, palette group 2: shaft + upper half index 1 (light), lower vane/barb index 2"""
    g = [["."] * 16 for _ in range(16)]
    for x in range(1, 16):
        g[7][x] = g[8][x] = "1"
    g[8][15] = "."  # pointed tip (upper pixel only)
    # head: spear leaf, upper half drawn, lower half mirrored in index 2
    for x, ys in {9: (4, 5, 6), 10: (4, 5, 6), 11: (5, 6), 12: (5, 6), 13: (6,), 14: (6,)}.items():
        for y in ys:
            g[y][x] = "1"
            g[15 - y][x] = "2"
    # fletching: two swept vanes (2 px strokes)
    for x, y in [(1, 3), (2, 3), (2, 4), (3, 4), (3, 5), (4, 5), (4, 6), (5, 6), (6, 6)]:
        g[y][x], g[15 - y][x] = "1", "2"
    return ["".join(r) for r in g]


# ---------------------------------------------------------------------------------------------
def to_cells(rows: list[str], w: int, h: int):
    """slice an ASCII picture of (w*8)x(h*8) into h*w tiles, row-major"""
    assert len(rows) == h * 8 and all(len(r) == w * 8 for r in rows), (len(rows), [len(r) for r in rows][:3])
    out = []
    for cy in range(h):
        for cx in range(w):
            out.append([r[cx * 8:cx * 8 + 8] for r in rows[cy * 8:cy * 8 + 8]])
    return out


def cell_map() -> dict[tuple[str, int], list[str]]:
    """(sheet, cell idx) -> 8 ASCII rows"""
    m: dict[tuple[str, int], list[str]] = {}
    # digits 0-9: DE idx 16..25 (tile $90-$99)
    for d, rows in DIGITS.items():
        m[("DE", 16 + d)] = glyph_tile(rows)
    # hearts: $A1 half, $A3 / $A4 refill animation frames (unused by the meter HUD; kept so no hex junk shows)
    # $A0 / $A2 (DE 32 / 34) are the stealth meter cells and $AB / $AC (DE 43 / 44) the HUSH label:
    # single source is gfx_placeholder.hud_cells() (docs/gfx/hud_map.md section 10)
    m[("DE", 33)] = heart("half")
    m[("DE", 35)] = HEART_TURN
    m[("DE", 36)] = HEART_EDGE
    # frame (DD idx = tile id) and the meter interior / empty slot cell (DE 117)
    for t, rows in FRAME.items():
        m[("DE", t - 128) if t >= 128 else ("DD", t)] = rows
    for t, h in GAUGE.items():
        m[("DD", t)] = gauge_tile(h)
    # meter cells DE 32 / 34 and HUSH label DE 43 / 44
    for idx, rows in gfx_placeholder.hud_cells().items():
        m[("DE", idx)] = rows
    # ornaments either side of the label: $8B $8F (idx 11 15)
    m[("DE", 11)] = ORN_OUTER
    m[("DE", 15)] = ORN_INNER
    # counters icons: ink mini $88 $89 (DE 8 9), dart mini $A7 $A9 (DE 39 41), gem $A8 (DE 40)
    m[("DE", 8)], m[("DE", 9)] = to_cells(INK_MINI, 2, 1)
    dm = to_cells(DART_MINI, 2, 1)
    m[("DE", 39)], m[("DE", 41)] = dm
    m[("DE", 40)] = GEM
    # item icons: bow+arrows slot = Hush Dart: $BA $4A / $49 $CB ; bombs slot = Ink Pot: $B2 $B3 / $C2 ($C2 H-flipped)
    db = to_cells(dart_big(), 2, 2)
    m[("DE", 58)], m[("DD", 74)], m[("DD", 73)], m[("DE", 75)] = db
    ib = to_cells(INK_BIG, 2, 2)
    m[("DE", 50)], m[("DE", 51)], m[("DE", 66)] = ib[0], ib[1], ib[2]
    # the item icons are opaque (idx 3 = dark slot): the START menu draws them over the room, not over a slot tile
    for key in (("DE", 58), ("DD", 74), ("DD", 73), ("DE", 75), ("DE", 50), ("DE", 51), ("DE", 66)):
        m[key] = [r.replace(".", "3") for r in m[key]]
    # (ib[3] is never drawn: the game uses C2 H-flipped for the bottom right quarter, INK_BIG's bottom half is symmetric)
    return m


def write_sheets(cells: dict) -> list[str]:
    msgs = []
    for sheet in ("DD", "DE"):
        path = HUD / f"GFX_{sheet}.png"
        im = Image.open(path)
        assert im.mode == "P" and im.size == (128, 64), (sheet, im.mode, im.size)
        flat = []
        for c in PNG_PALETTE:
            flat += list(c)
        flat += [0] * (768 - len(flat))
        im.putpalette(flat)
        px = im.load()
        n = 0
        for (s, idx), rows in cells.items():
            if s != sheet:
                continue
            assert len(rows) == 8 and all(len(r) == 8 for r in rows), (s, idx, rows)
            ox, oy = (idx % 16) * 8, (idx // 16) * 8
            for y, r in enumerate(rows):
                for x, ch in enumerate(r):
                    px[ox + x, oy + y] = 0 if ch == "." else int(ch)
            n += 1
        im.save(path, transparency=0)
        msgs.append(f"GFX_{sheet}: {n} cells drawn")
    return msgs


# ---------------------------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    cells = cell_map()
    for m in write_sheets(cells):
        print(m)
    errors: list[str] = []
    warnings: list[str] = []
    for sheet in ("DD", "DE"):
        p = HUD / f"GFX_{sheet}.png"
        rows, pal = None, None
        gfx_convert.process(p, False, errors, warnings)
    for e in errors:
        print("ERROR", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
