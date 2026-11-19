#!/usr/bin/env python3
"""Paint the tool / effect / icon sheets: GFX_C5 (awareness icons), GFX_7D (shadow + Ink Pot), GFX_79 + GFX_7A (ink cloud, poof,
sparkles), GFX_73 (Hush Dart), GFX_D1 (Shade Knife blade).  Layout = docs/gfx/art_map.md sections 5-9.  Original pixel art, drawn here.

Palette indices (see tools/art/cast_pal.py):
  FX family (73 79 7A 7D; OBJ rows 1/2): 1 outline  2 shade  3 deepest  4 mid violet  5 light violet  6 cyan-white glint  7 teal
  C5 (OBJ row 4 right):  1 outline  4 pale gold  5 amber  6 pale teal  7 teal shade
  D1 (OBJ row 5 right, indices 1-3 only): 1 violet blade  2 cyan-white glint  3 deep violet edge / grip
Run:  .venv/bin/python tools/art/cast_fx.py [--preview-dir DIR]
"""
from __future__ import annotations

import math
import sys

from cast_common import Sheet, check, hflip, outline, pad, render_preview
import cast_pal


def blank(w, h):
    return [["."] * w for _ in range(h)]


def rows_of(g):
    return ["".join(r) for r in g]


def transpose(rows):
    return ["".join(rows[y][x] for y in range(len(rows))) for x in range(len(rows[0]))]


# ------------------------------------------------------------------------------------------------ awareness icons (C5)
def glyph_icon(glyph: list[str], fill: str, hi: str | None = None, ox: int = 1, oy: int = 1) -> list[str]:
    g = blank(8, 8)
    for y, r in enumerate(glyph):
        for x, ch in enumerate(r):
            if ch != ".":
                g[oy + y][ox + x] = hi if (ch == "h" and hi) else fill
    return outline(rows_of(g), {fill} | ({hi} if hi else set()), "1")


Q_ICON = glyph_icon([".XX.", "X..X", "..X.", ".X..", "....", ".X.."], "4", ox=2)
BANG_ICON = glyph_icon(["hX", "hX", "hX", "hX", "..", "hX"], "5", hi="4", ox=3)
Z_ICON = glyph_icon(["XXXXX", "...X.", "..X..", ".X...", "XXXXX"], "6", ox=1, oy=2)


def paint_icons(s: Sheet):
    s.set_palette(cast_pal.ICON)
    s.clear(0, 0, s.w, s.h)
    s.put(96, 24, Q_ICON)
    s.put(104, 24, BANG_ICON)
    s.put(112, 24, Z_ICON)


# ------------------------------------------------------------------------------------------------ shading helpers (smoke, pot)
def disc(g, cx, cy, r, shade, rim_lit="5", rim_dark="2", fill_only=False):
    """Draw a shaded disc into g (list of lists). shade: dict with thresholds [(limit, idx)...] along the light axis (light from top-left)."""
    h, w = len(g), len(g[0])
    for y in range(h):
        for x in range(w):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > r:
                continue
            s = (dx * 0.6 + dy * 0.8)
            idx = None
            for lim, i in shade:
                if s < lim:
                    idx = i
                    break
            if idx is None:
                idx = shade[-1][1]
            if d > r - 1.0 and not fill_only:
                idx = rim_lit if s < 0.8 else rim_dark
            g[y][x] = idx


SMOKE = [(-0.2 * 99, "6")]  # placeholder, replaced below
SMOKE = [(-2.5, "4"), (1.5, "4"), (3.5, "2"), (99, "3")]   # interior: mid, mid, shade, deepest (bottom-right)


def puff_block(w, h, circles, sparks=()):
    g = blank(w, h)
    for cx, cy, r in circles:
        disc(g, cx, cy, r, SMOKE)
    for x, y in sparks:
        if 0 <= y < h and 0 <= x < w:
            g[y][x] = "6"
    return rows_of(g)


# ------------------------------------------------------------------------------------------------ sparkles
STAR_A = ["...66...", "...66...", "..6776..", "66777766", "66777766", "..6776..", "...66...", "...66..."]
STAR_B = ["........", "...6....", "...7....", ".67776..", "...7....", "...6....", "........", "........"]
STAR_C = ["........", "..6..6..", "...77...", "..7667..", "..7667..", "...77...", "..6..6..", "........"]


# ------------------------------------------------------------------------------------------------ cloud pieces (79)
def cloud_cell_corner():
    # 8x8 quadrant of the first burst frame: centre of the 4-fold burst = bottom-right corner of the cell
    g = blank(8, 8)
    disc(g, 8, 8, 6.5, [(-2, "5"), (1.5, "4"), (99, "2")])
    for x, y in ((3, 3), (4, 4), (2, 5), (5, 2)):
        g[y][x] = "6"
    g[6][6] = "7"; g[7][7] = "7"; g[7][6] = "6"; g[6][7] = "6"
    return rows_of(g)


def cloud_block_burst():
    # 16x16 quadrant (centre at bottom-right corner): ring of puffs around a bright core
    return puff_block(16, 16, [(11, 4, 4.2), (4, 11, 4.2), (9, 9, 5), (14, 14, 3)], sparks=[(9, 3), (3, 9), (14, 7), (7, 14), (6, 6)])


def cloud_block_big():
    return puff_block(16, 16, [(9, 3, 4.5), (3, 9, 4.5), (8, 8, 7), (13, 12, 4)], sparks=[(5, 5), (11, 4), (4, 12), (13, 13)])


def cloud_block_puff():
    # the held cloud: one fat dark puff (drawn six times with flips)
    return puff_block(16, 16, [(8, 8, 7.5), (4.5, 5, 4.5), (11.5, 11, 4.5)], sparks=[(4, 4), (11, 9)])


def cloud_block_thin():
    # dissipating: ring with holes
    g = blank(16, 16)
    disc(g, 8, 8, 7.2, SMOKE)
    for x, y in ((6, 6), (7, 6), (6, 7), (7, 7), (9, 10), (10, 10), (9, 11), (4, 11), (5, 11), (10, 4), (11, 4), (11, 5)):
        g[y][x] = "."
    for y in range(16):
        for x in range(16):
            if (x * 3 + y * 5) % 7 == 0 and g[y][x] != ".":
                g[y][x] = "."
    g[3][8] = "6"; g[12][4] = "7"; g[7][12] = "6"
    return rows_of(g)


def cloud_cell_dust():
    g = blank(8, 8)
    disc(g, 4, 4, 3.2, [(-1, "5"), (99, "4")], fill_only=False)
    g[2][2] = "6"
    return rows_of(g)


def anchor(s: Sheet):
    """Uncompressed 3bpp sheets must start with $FF (tile 0 row 0 = colour 1, tools/gfx_insert.py: the game runs the decompressor over them)."""
    for x in range(8):
        s.px[x, 0] = 1


def paint_79(s: Sheet):
    s.set_palette(cast_pal.FX)
    s.clear(0, 0, s.w, s.h)
    s.put(0, 1, STAR_A[:7])      # cell (0,0): row 0 is the $FF anchor, the star sits one row lower
    s.put(24, 0, STAR_B)
    s.put(56, 24, STAR_A)
    s.put(16, 8, STAR_C)
    s.put(24, 8, STAR_B)
    anchor(s)
    s.put(96, 0, cloud_cell_corner())
    s.put(32, 0, cloud_block_burst())
    s.put(64, 0, cloud_block_big())
    s.put(48, 0, cloud_block_puff())
    s.put(80, 0, cloud_block_thin())
    s.put(88, 8, cloud_cell_dust())


def paint_7a(s: Sheet):
    s.set_palette(cast_pal.FX)
    s.clear(0, 0, s.w, s.h)
    anchor(s)
    s.put(48, 8, [r.replace("6", "5") for r in STAR_C])     # light-violet arms, teal core
    s.put(56, 8, [r.replace("6", "5") for r in STAR_A])


# ------------------------------------------------------------------------------------------------ shadow + Ink Pot (7D)
SHADOW = [
    "................",
    "................",
    "................",
    "................",
    "....22222222....",
    "..221111111122..",
    ".22111111111122.",
    "..221111111122..",
    "....22222222....",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]


def ink_pot():
    g = blank(16, 16)
    disc(g, 8, 10.5, 5.8, [(-2.8, "5"), (0.2, "4"), (2.6, "2"), (99, "3")], rim_lit="5", rim_dark="3")
    # neck + cork
    for y, row in zip(range(1, 6), ("..2222..", ".255552.", "..2442..", "..2442..", "..2442..")):
        for x, ch in enumerate(row):
            if ch != ".":
                g[y][4 + x] = ch
    rows = rows_of(g)
    rows = outline(rows, set("2345"), "1")
    g = [list(r) for r in rows]
    for x, y in ((5, 8), (6, 8), (5, 9), (6, 7)):
        g[y][x] = "6"                       # glint
    for x, y in ((9, 10), (8, 11), (9, 11), (10, 11), (9, 12)):
        g[y][x] = "7"                       # teal ink drop on the belly
    return rows_of(g)


def paint_7d(s: Sheet):
    s.set_palette(cast_pal.FX)
    s.clear(0, 0, s.w, s.h)
    anchor(s)
    s.put(96, 16, SHADOW)
    s.put(112, 16, ink_pot())


# ------------------------------------------------------------------------------------------------ Hush Dart (73)
DART_TAIL_A = [".4....4.", ".44..44.", "..4554..", "...55...", "...55...", "...45...", "...45...", "...45..."]
DART_TAIL_B = ["........", ".4....4.", ".44..44.", "..4554..", "...55...", "...45...", "...45...", "...45..."]
DART_HEAD = ["...45...", "..4554..", ".455554.", ".455654.", "..4564..", "..4664..", "...66...", "...77..."]


BOW_9_0 = ["........", ".......7", "......75", ".....75.", "....75..", "...75...", "..75....", ".75....."]
BOW_10_0 = ["77......", "55......", "........", "........", "........", "........", "........", "........"]


def paint_bow(s: Sheet):
    """Bow limbs (aiming): drawn with the Ink row (OBJ 1): idx 7 violet, idx 5 shade, idx 1 outline. Cell (9,0) = '/' curve, (9,1) its V mirror, (10,0) tip stub."""
    for (cx, cy), rows in (((9, 0), BOW_9_0), ((9, 1), BOW_9_0[::-1]), ((10, 0), BOW_10_0), ((10, 1), BOW_10_0[::-1])):
        out = [list(r) for r in outline(rows, {"5", "7"}, "1")]
        s.put(cx * 8, cy * 8, ["".join(r) for r in out])


def paint_73(s: Sheet):
    s.set_palette(cast_pal.FX)
    s.clear(0, 0, s.w, s.h)
    anchor(s)
    horiz_tail_a, horiz_tail_b = transpose(DART_TAIL_A), transpose(DART_TAIL_B)
    horiz_head = transpose(DART_HEAD)
    # cells (10,2) $2A, (11,2) $2B, (12,2) $2C, (13,2) $2D, (10,3) $3A, (11,3) $3B, (12,3) $3C, (13,3) $3D
    s.put(80, 16, DART_TAIL_A)
    s.put(88, 16, DART_TAIL_A)
    s.put(96, 16, DART_TAIL_B)
    s.put(104, 16, DART_TAIL_B)
    s.put(80, 24, horiz_tail_a)
    s.put(88, 24, horiz_tail_b)
    s.put(96, 24, DART_HEAD)
    s.put(104, 24, horiz_head)
    paint_bow(s)


# ------------------------------------------------------------------------------------------------ Shade Knife blade (D1)
def column():
    g = blank(8, 16)
    for y in range(0, 11):
        w = 1 if y == 0 else (2 if y == 1 else 4)
        row = {1: "...2....", 2: "..21....", 4: "..2113.."}[w]
        g[y] = list(row)
    g[0] = list("...2....")
    g[11] = list(".311113.")
    g[12] = list("..3333..")
    g[13] = list("...33...")
    g[14] = list("...33...")
    g[15] = list("..3333..")
    return rows_of(g)


def diag(p0, p1, tip_len=0.74, w=16, h=16):
    """'\\'-type blade from tip p0 to hilt end p1 (x, y) in a w x h block."""
    g = blank(w, h)
    (x0, y0), (x1, y1) = p0, p1
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    nx, ny = uy, -ux                       # normal pointing up-right
    steps = int(L * 3)
    for k in range(steps + 1):
        t = k / steps
        d = t * L
        cx, cy = x0 + ux * d, y0 + uy * d
        if t < tip_len:
            half = 0.6 + 1.2 * min(1.0, d / 4.0) if t > 0.02 else 0.4
            for o in (-1.4, -0.7, 0.0, 0.7, 1.4):
                if abs(o) > half:
                    continue
                px, py = int(round(cx + nx * o)), int(round(cy + ny * o))
                if 0 <= px < w and 0 <= py < h:
                    g[py][px] = "2" if o > 0.5 else ("3" if o < -0.5 else "1")
            px, py = int(round(cx)), int(round(cy))
            if t < 0.04:
                g[py][px] = "2"
        elif t < tip_len + 0.05:
            for o in (-4, -3, -2, -1, 0, 1, 2, 3, 4):
                px, py = int(round(cx + nx * o * 0.9)), int(round(cy + ny * o * 0.9))
                if 0 <= px < w and 0 <= py < h:
                    g[py][px] = "3" if abs(o) >= 3 else "1"
        else:
            for o in (-0.8, 0.0, 0.8):
                px, py = int(round(cx + nx * o)), int(round(cy + ny * o))
                if 0 <= px < w and 0 <= py < h:
                    g[py][px] = "3"
    return rows_of(g)


def paint_d1(s: Sheet):
    s.set_palette(cast_pal.BLADE + cast_pal.FX[3:])      # idx 4-7 = the (violet/teal) shield colours, unused by the blade
    # only the 12x2 blade cells are drawn by the game; clear everything so no labelled placeholder is left in the sheet
    s.clear(0, 0, s.w, s.h)
    col = column()
    s.put(40, 0, col)            # (5,0)+(5,1) vertical blade, tip up
    s.put(0, 0, col)             # (0,0)+(0,1) the same (second column in the swing)
    hor = transpose(col)         # 16x8, tip left
    for cx in (3,):
        s.put(cx * 8, 0, hor)    # (3,0)(4,0)
        s.put(cx * 8, 8, hor)    # (3,1)(4,1)
    s.put(8, 0, diag((1, 1), (14, 14)))         # block (1,0): 45 degrees
    s.put(80, 0, diag((0, 3), (14, 12)))        # block (10,0): shallow
    s.put(48, 0, diag((3, 0), (12, 15)))        # block (6,0): steep
    s.put(64, 0, diag((1, 2), (13, 13)))        # block (8,0)


def main():
    pv = sys.argv[sys.argv.index("--preview-dir") + 1] if "--preview-dir" in sys.argv else None
    jobs = [("sprite/GFX_C5.png", paint_icons, cast_pal.ICON), ("sprite/GFX_79.png", paint_79, cast_pal.FX),
            ("sprite/GFX_7A.png", paint_7a, cast_pal.FX), ("sprite/GFX_7D.png", paint_7d, cast_pal.FX),
            ("sprite/GFX_73.png", paint_73, cast_pal.FX), ("item/GFX_D1.png", paint_d1, cast_pal.BLADE + cast_pal.FX[3:])]
    for path, fn, pal in jobs:
        s = Sheet(path)
        fn(s)
        s.save()
        if pv:
            render_preview(s, (0, 0, 128, 32), pal, 6).save(f"{pv}/{path.split('/')[-1][:-4]}.png")
    print("fx sheets painted")


if __name__ == "__main__":
    main()
