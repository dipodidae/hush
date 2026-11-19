#!/usr/bin/env python3
"""env_art: the E5 environment tiles (floor variants, wall-top variants, wall faces with torches/banners) as pixel grids.

  tools/art/env_art.py apply      paint every tile below into gfx/src/bg_tileset/GFX_00/06/10.png (indexed writes, palette untouched)
  tools/art/env_art.py preview    write build/art_preview/env_tiles_<group>.png (every block in the six room palettes, 4x)

The digits are sheet indices 1-7 (index i = CGRAM colour 8+i of the BG row the tile word selects; docs/gfx/art_map.md section 3).
Row semantics (all six palette groups, gfx/src/palettes/bg_dungeon.yaml): 1 deepest dark, 2 base, 3 lit base (light from the top), 4 dark
(mortar / shade), 5 bright accent, 6 amber, 7 pale / row accent (row 3: moss, row 6: banner cloth). The tile positions (sheet, cell) and the
tile ids they produce are in BLOCKS below; tools/roomgen.py VARIANTS lists the tile words built from them.
Painted by hand (no vanilla pixels were looked at or derived); the only inputs are metadata (positions, 8x8 cells, 3bpp).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "gfx" / "src" / "bg_tileset"


def rows(text: str) -> list[list[int]]:
    out = []
    for line in text.strip("\n").split("\n"):
        line = line.strip()
        if line:
            out.append([int(c) for c in line])
    return out


def grid(text: str, w: int, h: int) -> list[list[int]]:
    g = rows(text)
    assert len(g) == h and all(len(r) == w for r in g), (len(g), [len(r) for r in g])
    return g


def put(g, pts, v):
    for x, y in pts:
        g[y][x] = v
    return g


def copy(g):
    return [r[:] for r in g]


# --------------------------------------------------------------------------------------------------------------------
# floor: the vanilla-independent base block (kept identical to the A0/E3 floor: brick pattern, light from the top-left)
# --------------------------------------------------------------------------------------------------------------------
FLOOR = grid("""
4444444444444444
4333333333333333
4322222222222222
4322222222222222
4322442222222222
4322222222242222
4322222222222222
4322222222222222
4444444444444444
3333333243333333
2222222243222222
2222222243222222
2222222243222422
2224422243222222
2222222243222222
2222222243222222
""", 16, 16)


def floor_crack():
    g = copy(FLOOR)
    # a hairline crack from the upper right to the lower left, crossing the mortar line: the mortar colour (idx 4) with a few deepest pixels (idx 1)
    path = [(12, 1), (12, 2), (11, 3), (11, 4), (10, 5), (10, 6), (9, 7), (8, 8), (7, 9), (6, 10), (6, 11), (5, 12), (5, 13), (4, 14), (3, 15)]
    for x, y in path:
        g[y][x] = 4
    put(g, [(11, 4), (10, 5), (6, 11), (5, 12)], 1)
    for x, y in [(13, 2), (12, 4), (11, 6), (10, 7), (8, 10), (7, 11), (6, 13), (5, 14)]:
        if g[y][x] == 2:
            g[y][x] = 3
    put(g, [(13, 3)], 4)                  # a flake next to the crack
    put(g, [(4, 12)], 4)
    return g


def floor_worn():
    g = copy(FLOOR)
    # worn smooth: the bevel is gone and two soot stains (a solid core with a dithered rim) sit on the bricks
    for y in range(16):
        for x in range(16):
            if g[y][x] == 3 and not (y in (1, 9) and x < 4):
                g[y][x] = 2

    def stain(core, ring):
        for x, y in core:
            g[y][x] = 4
        for x, y in ring:
            if (x + y) % 2 == 0 and g[y][x] == 2:
                g[y][x] = 4

    stain([(x, 4) for x in range(5, 10)] + [(x, 5) for x in range(4, 10)] + [(x, 6) for x in range(5, 9)],
          [(x, 3) for x in range(5, 9)] + [(4, 4), (10, 4), (3, 5), (10, 5), (4, 6), (9, 6)] + [(x, 7) for x in range(5, 9)])
    stain([(x, 12) for x in range(11, 14)] + [(x, 13) for x in range(10, 14)],
          [(x, 11) for x in range(11, 14)] + [(9, 12), (14, 12), (9, 13), (14, 13)] + [(x, 14) for x in range(10, 14)])
    return g


def floor_crack2():
    g = copy(FLOOR)
    # a forked crack in the upper brick (running down to the left) and a short hairline in the lower brick
    for x, y in [(4, 1), (4, 2), (5, 3), (5, 4), (6, 5), (6, 6), (7, 7), (3, 5), (2, 6), (3, 4)]:
        g[y][x] = 4
    put(g, [(5, 4), (6, 5), (3, 5)], 1)
    for x, y in [(5, 2), (6, 4), (7, 6), (4, 5), (3, 6)]:
        if g[y][x] == 2:
            g[y][x] = 3
    for x, y in [(12, 10), (12, 11), (13, 12), (13, 13), (14, 14)]:
        g[y][x] = 4
    put(g, [(13, 12)], 1)
    put(g, [(11, 11), (12, 13)], 3)
    return g


def floor_shadow():
    # contact shadow under a wall face: the top rows of the block fade to the mortar colour (light comes from the top, the wall blocks it)
    g = copy(FLOOR)
    for x in range(16):
        g[1][x] = 4
        g[2][x] = 4 if x % 2 == 0 else 2
        if x % 4 == 1:
            g[3][x] = 4
    return g


def floor_rune():
    # one big flagstone (no mortar cross) with a carved diamond glyph; the glyph glows in the row's accent (idx 5)
    g = grid("""
4444444444444444
4333333333333333
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4322222222222222
4222222222222222
""", 16, 16)
    lit = [(8, 3), (7, 4), (9, 4), (6, 5), (10, 5), (5, 6), (11, 6), (4, 7), (12, 7), (5, 8), (11, 8), (6, 9), (10, 9), (7, 10), (9, 10), (8, 11),
           (8, 5), (8, 6), (8, 7), (8, 8), (8, 9)]
    for x, y in lit:
        g[y][x] = 5
    for x, y in lit:
        if y + 1 < 16 and g[y + 1][x] == 2 and (x, y + 1) not in lit:
            g[y + 1][x] = 4
    put(g, [(7, 7), (9, 7)], 3)
    return g


def floor_moss():
    g = copy(FLOOR)
    moss = [
        # ragged clump on the upper brick's lower edge
        (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (7, 7), (8, 7), (2, 6), (3, 6), (5, 6), (6, 6), (7, 6), (3, 5), (6, 5), (6, 4),
        # clump against the vertical joint of the lower brick
        (9, 15), (10, 15), (11, 15), (12, 15), (9, 14), (10, 14), (12, 14), (9, 13), (7, 15), (6, 15), (7, 14),
    ]
    for x, y in moss:
        g[y][x] = 7
    for x, y in [(1, 6), (4, 6), (4, 5), (5, 5), (7, 5), (7, 4)]:
        if g[y][x] in (2, 3):
            g[y][x] = 4
    put(g, [(3, 4), (6, 3)], 3)
    # loose rubble chips (light on top, dark under)
    put(g, [(12, 3), (13, 3), (13, 2)], 3)
    put(g, [(12, 4), (13, 4)], 1)
    put(g, [(3, 11)], 3)
    put(g, [(3, 12), (4, 12)], 1)
    return g


def floor_glow(strong: bool):
    # lamp-lit bricks: in a lit palette idx 5 is a warm bronze and idx 6 amber. strong = brick faces one step brighter (dithered, so the pool fades
    # out) with a warm bevel; weak = only the top bevel line of each brick is warm
    g = copy(FLOOR)
    for y in range(16):
        for x in range(16):
            if g[y][x] == 3:
                if strong or y in (1, 9):
                    g[y][x] = 5
            elif g[y][x] == 2 and strong and (x + y) % 2 == 0:
                g[y][x] = 3
    if strong:
        put(g, [(6, 3), (12, 6), (4, 12), (13, 11)], 6)
    return g


# --------------------------------------------------------------------------------------------------------------------
# wall top (BG row 7, 8x8 tiles; the existing tile GFX_00 (5,1) is the plain speckle T0)
# --------------------------------------------------------------------------------------------------------------------
TOP0 = grid("""
44444444
44441444
44244444
44444444
41444444
44444244
42444444
44444414
""", 8, 8)

TOP1 = grid("""
44444444
44444444
44322444
44414444
44444444
44444414
44444444
42444444
""", 8, 8)       # chips: a lit stone chip (3 3) with its shade

TOP2 = grid("""
44444444
41444444
44444444
44442444
44444444
44444444
42444414
44444444
""", 8, 8)       # sparse

TOP3 = grid("""
44444444
44444414
44144444
44444444
44444444
44444441
41444444
44444444
""", 8, 8)       # darker (almost flat)

CRACK = grid("""
4444444444444444
4444444444444444
4444444444441444
4444444444414444
4444444441144444
4444444414444444
4444444144444444
4444441144444444
4444414444444444
4444411444444444
4444444144444444
4444444414444444
4444444441144444
4444444444144444
4444444444444444
4444444444444444
""", 16, 16)     # hairline crack over a 16x16 block of the dark mass (idx 1 crack, idx 2/3 chips)
put(CRACK, [(13, 2), (12, 3)], 4)
put(CRACK, [(9, 6)], 2)
put(CRACK, [(5, 8), (3, 4)], 2)

SEAM = grid("""
4444414444444444
4444414444444444
4444414444444444
4444414444444444
4444414444444444
4444414444444444
4444414444444444
1111111111111111
2222222222222222
4444444444441444
4444444444441444
4444444444441444
4444444444441444
4444444444441444
4444444444441444
4444444444441444
""", 16, 16)     # slab joints of the wall top: a horizontal course joint (dark line, light line under it) and one vertical joint per slab
for _y in range(7):
    SEAM[_y][6] = 2
for _y in range(9, 16):
    SEAM[_y][13] = 2
put(SEAM, [(2, 3), (10, 12)], 2)



# --------------------------------------------------------------------------------------------------------------------
# wall face strip (BG row 6): the A/B pair (8 rows each) like the base face, plus variants. Rim line on top, bevel, mortar at y=4, shade at the bottom.
# --------------------------------------------------------------------------------------------------------------------
FACE = grid("""
5555555555555555
1333333313333333
1222222212222222
1222222212222222
1111111111111111
3333133333331333
2222122222221222
4444444444444444
""", 16, 8)


def face_crack():
    g = copy(FACE)
    for x, y in [(6, 1), (6, 2), (5, 3), (5, 4), (4, 5), (4, 6), (3, 7)]:
        g[y][x] = 1
    for x, y in [(7, 2), (6, 3), (5, 5), (5, 6)]:
        if g[y][x] in (2, 3):
            g[y][x] = 3 if y <= 3 else 4
    put(g, [(10, 2), (11, 3)], 4)
    return g


def face_banner():
    # a banner hung from a rod: rod (idx 5) on the rim, cloth idx 7 with a trim (5) in the middle and a swallow-tail end
    g = copy(FACE)
    cloth_rows = {
        1: range(5, 11),
        2: range(5, 11),
        3: range(5, 11),
        4: range(5, 11),
        5: range(5, 11),
        6: [5, 6, 9, 10],
    }
    for y, xs in cloth_rows.items():
        for x in xs:
            g[y][x] = 7
    put(g, [(x, 0) for x in range(4, 12)], 5)           # rod
    put(g, [(4, 1), (11, 1)], 4)                          # rod ends
    put(g, [(7, 2), (8, 2), (7, 3), (8, 3)], 5)          # trim emblem
    put(g, [(5, y) for y in range(1, 6)] + [(5, 6)], 7)
    put(g, [(10, y) for y in range(1, 7)], 4)            # shade on the right edge
    put(g, [(9, 6), (10, 6)], 4)
    put(g, [(7, 6), (8, 6)], 1)                           # shadow between the tails
    put(g, [(7, 7), (8, 7)], 1)
    return g


def face_sigil():
    # a carved diamond sigil with two side dots in the face strip (accent idx 5 on the brick), centred in the 16 px
    g = copy(FACE)
    put(g, [(7, 1), (8, 1), (6, 2), (9, 2), (7, 3), (8, 3)], 5)
    put(g, [(4, 2), (11, 2)], 5)
    put(g, [(7, 2), (8, 2)], 1)
    put(g, [(7, 4), (8, 4)], 1)
    return g


def face_warm():
    # bricks lit by a nearby torch: bevel brighter (5), base one step up (3)
    g = copy(FACE)
    for y in range(1, 7):
        for x in range(16):
            if g[y][x] == 3:
                g[y][x] = 5
            elif g[y][x] == 2:
                g[y][x] = 3
    return g


# 16x16 wall cells in row 6: the whole cell is custom (top half = dark mass of the wall, bottom half = the face strip)
def torch_block(lit: bool = True):   # only the lit variant is used (unlit sconces are strips, see sconce_strip)
    """16x16 wall cell for BG row 6: top half = dark mass of the wall (+ the flame), bottom half = the face strip with the iron sconce."""
    g = grid("""
4444444444444444
4444444414444444
4444444444444444
4414444444444144
4444444444444444
4444444444444444
4444144444444444
4444444444444444
""", 16, 8) + copy(FACE)
    # sconce plate: a plain panel (no mortar) so the iron reads; light bevel on the top-left
    for y in range(9, 15):
        for x in range(4, 12):
            g[y][x] = 2
    for x in range(4, 12):
        g[9][x] = 3
    for y in range(9, 15):
        g[y][4] = 3
    for x in range(4, 12):
        g[14][x] = 4
    # iron: cup (rows 8-9), stem (10-13)
    put(g, [(x, 8) for x in range(5, 11)], 1)
    put(g, [(x, 9) for x in range(6, 10)], 1)
    put(g, [(7, y) for y in range(10, 14)] + [(8, y) for y in range(10, 14)], 1)
    put(g, [(6, 12), (9, 12)], 1)          # crossbar of the bracket
    put(g, [(6, 8)], 5 if lit else 3)       # lit edge of the cup
    if lit:
        flame = {
            1: [(7, 5), (8, 5)],
            2: [(7, 5), (8, 5)],
            3: [(6, 5), (7, 6), (8, 6), (9, 5)],
            4: [(6, 5), (7, 6), (8, 6), (9, 5)],
            5: [(5, 5), (6, 6), (7, 6), (8, 6), (9, 6), (10, 5)],
            6: [(5, 5), (6, 6), (7, 6), (8, 6), (9, 6), (10, 5)],
            7: [(5, 5), (6, 6), (7, 6), (8, 6), (9, 6), (10, 5)],
        }
        fl = {}
        for y, cells in flame.items():
            for x, v in cells:
                fl[(x, y)] = v
        # glow: ring 1 (idx 3) around the flame, ring 2 (idx 2, checker dither) around that
        ring1 = set()
        for (x, y) in fl:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q not in fl and 0 <= q[0] < 16 and 0 <= q[1] < 8:
                        ring1.add(q)
        ring2 = set()
        for (x, y) in ring1:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q not in fl and q not in ring1 and 0 <= q[0] < 16 and 0 <= q[1] < 8 and (q[0] + q[1]) % 2 == 0:
                        ring2.add(q)
        for (x, y) in ring2:
            g[y][x] = 2
        for (x, y) in ring1:
            g[y][x] = 3
        for (x, y), v in fl.items():
            g[y][x] = v
        put(g, [(x, 8) for x in range(5, 11)], 1)
        put(g, [(6, 8)], 5)
        # the plate is lit too
        for y in range(10, 14):
            for x in range(4, 12):
                if g[y][x] == 2:
                    g[y][x] = 3
    return g


def sconce_strip():
    """16x8 face strip (BG row 6, tiles A/B) of an UNLIT iron sconce: dead torch stub in a bracket on a plain panel (the cell's top half is the plain wall top)."""
    g = copy(FACE)
    for y in range(1, 7):
        for x in range(4, 12):
            g[y][x] = 2
    for x in range(4, 12):
        g[1][x] = 3
        g[6][x] = 4
    for y in range(1, 7):
        g[y][4] = 3
    put(g, [(7, 1), (8, 1)], 4)                         # charred stub
    put(g, [(6, 2), (7, 2), (8, 2), (9, 2)], 1)         # cup
    put(g, [(6, 3), (9, 3), (7, 3), (8, 3)], 1)
    put(g, [(7, 4), (8, 4), (7, 5), (8, 5)], 1)         # stem
    put(g, [(6, 4), (9, 4)], 1)
    put(g, [(6, 2)], 3)                                  # lit edge of the cup
    return g


# --------------------------------------------------------------------------------------------------------------------
# placement: (sheet file stem) -> {(cell x, cell y): 8x8 tile}; blocks are 16x16 = 2x2 cells
# --------------------------------------------------------------------------------------------------------------------
def tile_of(g, tx, ty):
    return [row[tx * 8:(tx + 1) * 8] for row in g[ty * 8:(ty + 1) * 8]]


def block_to(sheet: dict, cx: int, cy: int, g):
    for ty in range(2):
        for tx in range(2):
            sheet[(cx + tx, cy + ty)] = tile_of(g, tx, ty)


def build() -> dict[str, dict[tuple[int, int], list[list[int]]]]:
    s00, s06, s10 = {}, {}, {}
    # GFX_06 (tiles $C0 + idx): floor blocks, ids $C4 $C5 / $D4 $D5 ... (all vanilla tile type $00 = floor)
    block_to(s06, 4, 0, floor_crack())
    block_to(s06, 6, 0, floor_worn())
    block_to(s06, 8, 0, floor_rune())
    block_to(s06, 10, 0, floor_moss())
    block_to(s06, 12, 0, floor_glow(True))
    block_to(s06, 9, 2, floor_crack2())
    block_to(s06, 14, 2, floor_shadow())
    # GFX_00: wall top chips (ids $00 $01 $02, solid) and the weak glow floor block (ids $2E $2F / $3E $3F, floor)
    s00[(0, 0)] = TOP1
    s00[(1, 0)] = TOP2
    s00[(2, 0)] = TOP3
    block_to(s00, 14, 2, floor_glow(False))
    # GFX_10 (tiles $80 + idx, all solid type $01): crack block, torch, sconce, face strips
    block_to(s10, 0, 0, CRACK)
    block_to(s10, 2, 0, torch_block(True))
    s10[(4, 0)] = tile_of(sconce_strip(), 0, 0)   # unlit sconce strip A/B
    s10[(5, 0)] = tile_of(sconce_strip(), 1, 0)
    block_to(s10, 0, 2, SEAM)
    for _c in (4, 5):
        s10[(_c, 1)] = [[4] * 8 for _ in range(8)]       # spare (plain dark)
    for (cx, cy), g in {(6, 0): face_banner(), (8, 0): face_sigil(), (10, 0): face_crack(), (12, 0): face_warm()}.items():
        s10[(cx, cy)] = tile_of(g, 0, 0)       # A (left 8 px of the 16x8 strip)
        s10[(cx + 1, cy)] = tile_of(g, 1, 0)   # B (right 8 px)
    return {"GFX_00": s00, "GFX_06": s06, "GFX_10": s10}


# face strips are 16x8 grids; tile_of() above slices rows 0-8 only, so give them an 8-row view
def _face_tiles():
    pass


BLOCKS_DOC = """
GFX_06 floor blocks (BG row 3, ids $C0+idx):  crack (4,0)  worn (6,0)  rune (8,0)  moss (10,0)  glow (12,0)
GFX_00: wall-top chips T1 (0,0) T2 (1,0) T3 (2,0);  weak glow floor block (14,2)
GFX_10 (ids $80+idx): top crack block (0,0); torch (2,0); sconce (4,0); banner A/B (6,0)(7,0); sigil (8,0)(9,0); face crack (10,0)(11,0); warm face (12,0)(13,0)
"""


def apply() -> None:
    sheets = build()
    for stem, cells in sheets.items():
        path = SHEETS / f"{stem}.png"
        im = Image.open(path)
        assert im.mode == "P"
        px = im.load()
        for (cx, cy), t in cells.items():
            for y in range(8):
                for x in range(8):
                    v = t[y][x]
                    assert 1 <= v <= 7, (stem, cx, cy, x, y, v)
                    px[cx * 8 + x, cy * 8 + y] = v
        im.save(path, transparency=0)
        print(f"wrote {len(cells)} tiles into {path.relative_to(ROOT)}")


def preview() -> None:
    pal = yaml.safe_load((ROOT / "gfx/src/palettes/bg_dungeon.yaml").read_text())["groups"]
    out = ROOT / "build" / "art_preview"
    out.mkdir(parents=True, exist_ok=True)
    sheets = build()

    def colours(group: str, row: int):
        c = pal[group]["colours"][2 * (row - 2) + 1]
        return [(0, 0, 0)] + [tuple(int(str(h)[i:i + 2], 16) for i in (0, 2, 4)) for h in c[1:]]

    def draw(img, ox, oy, g, row, group, z=4):
        cols = colours(group, row)
        for y, r in enumerate(g):
            for x, v in enumerate(r):
                for dy in range(z):
                    for dx in range(z):
                        img.putpixel((ox + x * z + dx, oy + y * z + dy), cols[v])

    items = []   # (name, grid, row)
    for name, g in (("floor", FLOOR), ("crack", floor_crack()), ("crack2", floor_crack2()), ("shadow", floor_shadow()), ("worn", floor_worn()), ("rune", floor_rune()), ("moss", floor_moss()),
                    ("glow", floor_glow(True)), ("glow2", floor_glow(False))):
        items.append((name, g, 3))
    for name, g in (("T0", TOP0), ("T1", TOP1), ("T2", TOP2), ("T3", TOP3)):
        items.append((name, g, 7))
    items.append(("topcrack", CRACK, 7))
    return_items = items
    for group in ("pal_dungeon_00", "pal_dungeon_01", "pal_dungeon_02", "pal_dungeon_03", "pal_dungeon_04", "pal_dungeon_05"):
        z = 5
        img = Image.new("RGB", (1100, 16 * z * 3 + 60), (40, 40, 48))
        x = 4
        for name, g, row in return_items:
            draw(img, x, 4, g, row, group, z)
            x += len(g[0]) * z + 6
        # face strips + torches
        x = 4
        y = 16 * z + 12
        for name, g in (("face", FACE), ("banner", face_banner()), ("sigil", face_sigil()), ("fcrack", face_crack()), ("warm", face_warm())):
            draw(img, x, y, g, 6, group, z)
            x += 16 * z + 6
        x = 4
        y = 16 * z + 12 + 8 * z + 8
        for name, g in (("torch", torch_block(True)), ("sconce", sconce_strip())):
            draw(img, x, y, g, 6, group, z)
            x += 16 * z + 6
        img.save(out / f"env_tiles_{group}.png")
    print("preview ->", out)


# E5 palette tweaks (idx 5/6/7 of BG rows 3 and 6 in the six room groups; only colours the E3 tiles never use are touched):
#   row 3 (floor)  idx 7 = moss green (floor 1 jade, 2 olive-teal, 3 olive); lit groups also idx 5 = warm bronze (lamp-lit bricks), idx 6 = amber
#   row 6 (face)   idx 7 = banner cloth (crimson / teal / teal); lit groups idx 6 = flame amber
PAL_EDITS = {
    # group: {(row, idx): hex}
    "pal_dungeon_00": {(3, 7): "35603A", (6, 7): "B03050"},
    "pal_dungeon_01": {(3, 7): "4A7438", (6, 7): "2A9A94"},
    "pal_dungeon_02": {(3, 7): "5E6E32", (6, 7): "2A9A94"},
    "pal_dungeon_03": {(3, 5): "A87850", (3, 6): "F0B040", (3, 7): "4A7040", (6, 6): "FFC040", (6, 7): "C03858"},
    "pal_dungeon_04": {(3, 5): "A88458", (3, 6): "F0B040", (3, 7): "56783E", (6, 6): "FFC040", (6, 7): "30AAA4"},
    "pal_dungeon_05": {(3, 5): "B48254", (3, 6): "F0B040", (3, 7): "6E7C38", (6, 6): "FFD060", (6, 7): "30AAA4"},
}


def palette() -> None:
    path = ROOT / "gfx" / "src" / "palettes" / "bg_dungeon.yaml"
    lines = path.read_text().split("\n")
    for group, edits in PAL_EDITS.items():
        gi = lines.index(f"  {group}:")
        ci = next(i for i in range(gi, len(lines)) if lines[i].strip() == "colours:")
        for (row, idx), hexv in edits.items():
            li = ci + 1 + 2 * (row - 2) + 1          # right half of the row = colours[2(row-2)+1]
            items = re.findall(r"'([0-9A-Fa-f]{6})'", lines[li])
            assert len(items) == 8, (group, row, lines[li])
            items[idx] = hexv
            lines[li] = "    - [" + ", ".join(f"'{c}'" for c in items) + "]"
    path.write_text("\n".join(lines))
    print("palette edits written to", path.relative_to(ROOT))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "preview"
    {"apply": apply, "preview": preview, "palette": palette}[cmd]()
