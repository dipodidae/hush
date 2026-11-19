#!/usr/bin/env python3
"""menu_art.py: HUSH's own START item menu / text box pixels (BG3, 2bpp) written into gfx/src/hud/GFX_DC.png, GFX_DD.png, GFX_DE.png.

  .venv/bin/python tools/art/menu_art.py            # (re)draw every menu cell, validate with gfx_convert
  .venv/bin/python tools/art/hud_art.py             # the in-room HUD cells (different cells of the same sheets; run in either order)

Every pixel is drawn here from ASCII art / simple geometry; nothing is read from vanilla graphics. Only the cells listed in
docs/gfx/hud_map.md section 7 are touched. Tile numbers and tilemap positions are vanilla (ROM tilemap code) and do NOT change.
BG3 tile id -> sheet cell: id 0x00-0x7F = GFX_DD idx id, 0x80-0xFF = GFX_DE idx id-0x80, 0x100-0x17F = GFX_DC idx id-0x100.

ASCII keys: '.' = index 0 (transparent), '1' '2' '3' = palette index 1 2 3 of the palette group the tilemap word selects
(gfx/src/palettes/hud.yaml; the group used by each cell is written next to it below).
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "art"))
import gfx_convert  # noqa: E402
import hud_art  # noqa: E402
from gfx_pixfont import GLYPHS  # noqa: E402

HUD = ROOT / "gfx" / "src" / "hud"


def cell(tile_id: int) -> tuple[str, int]:
    if tile_id < 0x80:
        return "DD", tile_id
    if tile_id < 0x100:
        return "DE", tile_id - 0x80
    return "DC", tile_id - 0x100


# ---------------------------------------------------------------------------------------------
# fonts: 3x5 caps for labels (hand drawn), proportional 5x7 caps for item names (gfx_pixfont GLYPHS, trimmed; I redrawn narrow)
F3 = {
    "A": ".#. #.# ### #.# #.#", "B": "##. #.# ##. #.# ##.", "C": ".## #.. #.. #.. .##", "D": "##. #.# #.# #.# ##.",
    "E": "### #.. ##. #.. ###", "F": "### #.. ##. #.. #..", "G": ".## #.. #.# #.# .##", "H": "#.# #.# ### #.# #.#",
    "I": "### .#. .#. .#. ###", "J": "..# ..# ..# #.# .#.", "K": "#.# #.# ##. #.# #.#", "L": "#.. #.. #.. #.. ###",
    "M": "#.# ### ### #.# #.#", "N": "### #.# #.# #.# #.#", "O": "### #.# #.# #.# ###", "P": "### #.# ### #.. #..",
    "Q": "### #.# #.# ### ..#", "R": "### #.# ##. #.# #.#", "S": ".## #.. .#. ..# ##.", "T": "### .#. .#. .#. .#.",
    "U": "#.# #.# #.# #.# ###", "V": "#.# #.# #.# #.# .#.", "W": "#.# #.# ### ### #.#", "X": "#.# #.# .#. #.# #.#",
    "Y": "#.# #.# .#. .#. .#.", "Z": "### ..# .#. #.. ###", " ": "... ... ... ... ...",
}


def text3(s: str, ink: str) -> list[str]:
    """3x5 text, 1 px gap: 5 rows"""
    rows = [""] * 5
    for ch in s:
        g = F3[ch].split()
        for y in range(5):
            rows[y] += "".join(ink if c == "#" else "." for c in g[y]) + "."
    return [r[:-1] for r in rows]


NARROW_I = ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"]


def glyph5(ch: str) -> list[str]:
    """proportional 5x7: columns trimmed to the ink (I redrawn 3 wide)"""
    if ch == "I":
        return NARROW_I
    g = GLYPHS[ch]
    cols = [x for x in range(5) if any(r[x] == "#" for r in g)]
    if not cols:
        return ["..."] * 7
    return [r[cols[0]:cols[-1] + 1] for r in g]


def text5(s: str, ink: str = "1", shadow: str | None = None, width: int | None = None, x0: int = 0) -> list[str]:
    """proportional 5x7 text (optionally with a 1 px down-right shadow): 8 rows; placed at x0 inside a canvas of `width` px"""
    gl = [glyph5(c) if c != " " else ["..."] * 7 for c in s]
    w = x0 + sum(len(g[0]) + 1 for g in gl)
    W = width or w
    canvas = [["."] * W for _ in range(8)]
    x = x0
    for g in gl:
        for y, r in enumerate(g):
            for dx, c in enumerate(r):
                if shadow and c == "#" and x + dx + 1 < W and y + 1 < 8:
                    canvas[y + 1][x + dx + 1] = shadow
        x += len(g[0]) + 1
    x = x0
    for g in gl:
        for y, r in enumerate(g):
            for dx, c in enumerate(r):
                if c == "#":
                    canvas[y][x + dx] = ink
        x += len(g[0]) + 1
    return ["".join(r) for r in canvas]


def split_row(rows: list[str], n: int) -> list[list[str]]:
    """slice an 8-row picture n tiles wide into n tiles"""
    assert len(rows) == 8 and len(rows[0]) == 8 * n, (len(rows), len(rows[0]), n)
    return [[r[i * 8:i * 8 + 8] for r in rows] for i in range(n)]


def hflip(t: list[str]) -> list[str]:
    return [r[::-1] for r in t]


def vflip(t: list[str]) -> list[str]:
    return t[::-1]


# ---------------------------------------------------------------------------------------------
# window frames: 2 px line (idx 1 outside, idx 2 inside) + a dark bezel (idx 3); the tile is opaque because the room is behind BG3
FRAME_EDGE = ["11111111", "22222222"] + ["33333333"] * 6          # top edge as stored (V flip = bottom edge)
FRAME_SIDE = ["12333333"] * 8                                      # left edge as stored (H flip = right edge)
FRAME_CORNER = [                                                   # top-left corner, rounded (H/V flips = the others)
    "..111111",
    ".1222222",
    "12233333",
    "12333333",
    "12333333",
    "12333333",
    "12333333",
    "12333333",
]


def tab(label: str, ink: str, lines: str = "12") -> list[list[str]]:
    """two tiles of the top edge with a 3x5 label in the bezel (rows 3-7); `lines` = the colour index of the outer / inner line"""
    txt = text3(label, ink)
    w = len(txt[0])
    off = (16 - w) // 2
    pic = [(lines[0] * 16), (lines[1] * 16)] + ["3" * 16] * 6
    for y in range(5):
        r = list(pic[3 + y])
        for x, c in enumerate(txt[y]):
            if c != ".":
                r[off + x] = c
        pic[3 + y] = "".join(r)
    return split_row_16(pic)


def split_row_16(pic: list[str]) -> list[list[str]]:
    return [[r[0:8] for r in pic], [r[8:16] for r in pic]]


ACCENT_A = ["32233333"] * 8                                        # inner bar near the top-left of a window (idx 2 = accent)
ACCENT_B = ["32233333"] * 6 + ["32333333", "33333333"]


# window cursor (BG3 ring around the selected 16x16 slot; the ring tiles REPLACE the panel cells, so they are opaque: a dark mat next to
# the slot and a violet frame (idx 1) with a thin teal inner line (idx 2) on the outer edge of the 8 px gap; palette 7: idx 1 violet, 2 teal)
CURSOR_EDGE_H = ["11111111", "11111111", "22222222"] + ["33333333"] * 5     # 0x61 top edge (V flip = bottom edge)
CURSOR_EDGE_V = ["11233333"] * 8                                            # 0x70 left edge (H flip = right edge)
CURSOR_CORNER = ["..111111", ".1111111", "11222222", "11233333", "11233333", "11233333", "11233333", "11233333"]  # 0x60 top-left (rounded)


# ---------------------------------------------------------------------------------------------
# icons (16x16 as ASCII; palette group per tile written in cell_map)
SWORD = [  # Shade Knife: blade tip up. TL/TR/BL = group 3 (1 light violet, 2 violet), BR = group 7 (1 violet light, 2 teal)
    ".......12.......",
    ".......12.......",
    "......1122......",
    "......1122......",
    "......1122......",
    "......1122......",
    "......1122......",
    "......1122......",
    "......1122......",
    "....11111111....",
    "....11111111....",
    ".......22.......",
    ".......22.......",
    ".......22.......",
    "......2222......",
    "......2222......",
]
MAIL_HALF = [  # hooded cloak, left half (the right half is the H flip); group 7: 1 violet, 2 teal scarf, 3 dark hollow
    "......11",
    ".....111",
    "....1111",
    "...11133",
    "..111133",
    "..111133",
    "..111113",
    "...11122",
    "..111222",
    "..111122",
    ".1111111",
    ".1111111",
    ".1111111",
    "11111111",
    "11111111",
    ".1111111",
]
GEM_HALF = [  # loot gem, left half (group 1: 1 white facet, 2 violet, 3 dark facet)
    "........",
    "....1111",
    "...11222",
    "..112222",
    ".1122222",
    "11111111",
    ".2222222",
    "..222223",
    "...22233",
    "....2233",
    ".....223",
    "......23",
    ".......3",
    "........",
    "........",
    "........",
]


def mirror16(half: list[str]) -> list[str]:
    return [r + r[::-1] for r in half]


def socket() -> list[str]:
    """empty socket 16x16 (group 4: 1 bright ring, 2 dim ring, 3 hollow): the three progress slots, nothing collected"""
    g = []
    for y in range(16):
        row = ""
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d > 6.3:
                row += "."
            elif d > 5.0:
                row += "1"
            elif d > 3.6:
                row += "2"
            else:
                row += "3"
        g.append(row)
    return g


def socket_lit() -> list[str]:
    """the same socket with a glowing core (progress window with a pendant bit set in $7EF374: red = group 1, blue = group 3, green = group 7)"""
    g = []
    for y in range(16):
        row = ""
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d > 6.3:
                row += "."
            elif d > 5.0:
                row += "1"
            elif d > 3.6:
                row += "2"
            elif d > 1.8:
                row += "1"
            else:
                row += "2"
        g.append(row)
    return g


def slice16(pic: list[str]) -> list[list[str]]:
    """4 tiles TL TR BL BR"""
    assert len(pic) == 16 and all(len(r) == 16 for r in pic)
    return [[r[x:x + 8] for r in pic[y:y + 8]] for y in (0, 8) for x in (0, 8)]


# ---------------------------------------------------------------------------------------------
def cell_map() -> dict[tuple[str, int], list[str]]:
    m: dict[tuple[str, int], list[str]] = {}

    def put(tid: int, rows: list[str], opaque: bool = True):
        """every menu tile is OPAQUE (idx 3 = the group's dark colour instead of idx 0): the menu is drawn over the room, a transparent
        pixel would show the floor behind the window"""
        assert len(rows) == 8 and all(len(r) == 8 for r in rows), (hex(tid), rows)
        m[cell(tid)] = [r.replace(".", "3") for r in rows] if opaque else rows

    # window frames: F9 edge, FC side, FB corner (palette 7 active windows, 2 pendants/equipment/text box, 1 ability window)
    put(0xF9, FRAME_EDGE)
    put(0xFC, FRAME_SIDE)
    put(0xFB, FRAME_CORNER, opaque=False)   # the three corner pixels stay transparent: rounded window corners
    # text box: border tiles of RenderText_BorderTiles (palette 2): corner, top/bottom edge, left/right side
    put(0xF3, FRAME_CORNER, opaque=False)
    put(0xF4, FRAME_EDGE)
    put(0xC8, FRAME_SIDE)
    # label tabs on the top edge (palette 1: 1 white, 2 violet) and the accent bars inside the corner
    for tid, t in zip((0x6E, 0x6F), tab("ITEM", "2", "22")):   # inside the (palette 7) items window: lines match its violet outer line
        put(tid, t)
    for tid, t in zip((0x82, 0x83), tab("HUSH", "2")):
        put(tid, t)
    put(0xF0, ACCENT_A)
    put(0xF1, ACCENT_B)
    put(0xF2, ACCENT_B)
    # cursor ring (palette 7)
    put(0x60, CURSOR_CORNER, opaque=False)
    put(0x61, CURSOR_EDGE_H)
    put(0x70, CURSOR_EDGE_V)
    # equipment window: label (palette 1), rule (palette 2), Shade Knife icon, cloak icon, gem icon
    lab = text3("EQUIPMENT", "2")                          # 35 px in 5 tiles
    pic = ["." * 3 + r + "." * (40 - 3 - len(r)) for r in lab]
    pic = ["........" * 5] * 1 + pic + ["." * 40] * 2
    for tid, t in zip((0x79, 0x7A, 0x7B, 0x7C, 0x8C), split_row(pic, 5)):
        put(tid, t)
    put(0xD7, ["........"] * 3 + ["22222222", "11111111"] + ["........"] * 3)
    sw = slice16(SWORD)
    for tid, t in zip((0x64, 0xCE, 0x75, 0x125), sw):
        put(tid, t)
    mail = mirror16(MAIL_HALF)
    mt = slice16(mail)
    put(0x68, mt[0])
    put(0x78, mt[2])
    # heart pieces ($84 $85, "0 pieces" in the equipment window): HUSH has none, so the icon is an empty (panel coloured) cell
    put(0x84, ["........"] * 8)
    put(0x85, ["........"] * 8)
    # pendant window -> FLOORS: label (palette 1) + three empty sockets (palette 4)
    lab = text3("FLOORS", "2")
    pic = ["." * 40] * 1 + ["." * 3 + r + "." * (37 - len(r)) for r in lab] + ["." * 40] * 2
    for tid, t in zip((0x121, 0x122, 0x123, 0x124, 0x13F), split_row(pic, 5)):
        put(tid, t)
    for tid, t in zip((0x13B, 0x13C, 0x13D, 0x13E), slice16(socket())):
        put(tid, t)
    # lit sockets (ItemIcons.pendant_red $252B.., pendant_blue $2D2B.., pendant_green $3D2B..: tiles $12B-$12E in groups 1 / 3 / 7)
    for tid, t in zip((0x12B, 0x12C, 0x12D, 0x12E), slice16(socket_lit())):
        put(tid, t)
    # equipped item name row (palette 1: 1 white). Bow-and-arrows row = 8 tiles 6B 6C 6E 6F 7C 7D 7E 7F: the dart
    # emblem in the first two (alone when the quiver is empty), DARTS after it. Bombs row = 4 tiles 51 5E 5C 51: drop, INK, drop.
    dart_row = [["."] * 64 for _ in range(8)]
    emblem = [r for r in hud_art.DART_MINI]
    for y in range(8):
        for x in range(16):
            c = emblem[y][x]
            dart_row[y][x] = c
    txt = text5("DARTS", "1", None, 64 - 20, 0)
    for y in range(8):
        for x, c in enumerate(txt[y]):
            if c != ".":
                dart_row[y][20 + x] = c
    tiles = split_row(["".join(r) for r in dart_row], 8)
    for tid, t in zip((0x16B, 0x16C, 0x16E, 0x16F, 0x17C, 0x17D, 0x17E, 0x17F), tiles):
        put(tid, t)
    drop = [
        "........",
        "...22...",
        "..2222..",
        ".222222.",
        ".212222.",
        ".222222.",
        "..2222..",
        "........",
    ]
    ink_txt = text5("INK", "1", None, 16, 0)
    ink_tiles = split_row(ink_txt, 2)
    put(0x151, drop)
    put(0x15E, ink_tiles[0])
    put(0x15C, ink_tiles[1])
    return m


PREVIEW_PALETTE = None


def write_sheets(cells: dict) -> list[str]:
    msgs = []
    for sheet in ("DC", "DD", "DE"):
        path = HUD / f"GFX_{sheet}.png"
        im = Image.open(path)
        assert im.mode == "P" and im.size == (128, 64), (sheet, im.mode, im.size)
        flat = []
        for c in hud_art.PNG_PALETTE:
            flat += list(c)
        flat += [0] * (768 - len(flat))
        im.putpalette(flat)
        px = im.load()
        n = 0
        for (s, idx), rows in cells.items():
            if s != sheet:
                continue
            ox, oy = (idx % 16) * 8, (idx // 16) * 8
            for y, r in enumerate(rows):
                for x, ch in enumerate(r):
                    px[ox + x, oy + y] = 0 if ch == "." else int(ch)
            n += 1
        im.save(path, transparency=0)
        msgs.append(f"GFX_{sheet}: {n} menu cells drawn")
    return msgs


def main() -> int:
    argparse.ArgumentParser().parse_args()
    cells = cell_map()
    for m in write_sheets(cells):
        print(m)
    errors: list[str] = []
    warnings: list[str] = []
    for sheet in ("DC", "DD", "DE"):
        gfx_convert.process(HUD / f"GFX_{sheet}.png", False, errors, warnings)
    for e in errors:
        print("ERROR", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
