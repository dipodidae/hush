#!/usr/bin/env python3
"""Paint the poses of gfx/src/player/LINK.png that the game really draws (block lists = docs/gfx/art_map.md section 8).

Link = the shadow thief: violet hooded cloak, glowing pale-cyan eyes, teal scarf (OBJ row 7, 4bpp indices 1-15; hex digits a-f = 10-15).
  1 outline  2 cloak dark  3 cloak  4 cloak light / hood highlight  5 violet bright  6 eye glint  7 boots / deep shade
  8 scarf  9 scarf shade  a hood inner  b violet mid  c violet bright  d deepest (face hollow)  e pale violet  f near white
Side view is drawn facing RIGHT (left = H flip by the game).  Same pixels for every pose of a facing; only the legs change.
Run:  .venv/bin/python tools/art/cast_link.py [--preview out.png]
"""
from __future__ import annotations

import sys

from cast_common import Sheet, hflip, mirror, snap, render_preview

LINK_PAL = [snap(h) for h in ("080818", "382080", "583CB0", "885CE0", "B890F8", "D8F8F8", "181050",
                              "38D8C8", "188888", "201860", "7050D0", "C0A8F8", "281858", "E0D0F8", "F0F8F8")]

HEAD_DOWN = mirror([
    "......11",
    "....1133",
    "...13444",
    "..134333",
    "..133ddd",
    "..13dddd",
    "..13d66d",
    "..13dddd",
    "..13ddd8",
    "...18888",
    "...19898",
    "....1999",
    "......11",
])
HEAD_UP = mirror([
    "......11",
    "....1133",
    "...13444",
    "..134333",
    "..133333",
    "..133333",
    "..133332",
    "..133322",
    "..122222",
    "...18888",
    "...19898",
    "....1999",
    "......11",
])
HEAD_SIDE = [   # facing right
    "......1111......",
    "....1133333311..",
    "...134433333331.",
    "..13433333ddddd1",
    "..133333dd66ddd1",
    "..1333333ddddd1.",
    "..1333333ddddd1.",
    "..133333333ddd1.",
    "..1333388d11111.",
    "...18888889991..",
    "...199999911....",
    "....111111......",
    "................",
]


def pad16(rows):
    rows = [r.ljust(16, ".") for r in rows]
    return rows + ["." * 16] * (16 - len(rows))


def cloak_front(walk: str, tail: bool):
    """Body facing down / up. walk = stand | stepL | stepR | mid."""
    t = "8" if tail else "3"
    t2 = "9" if tail else "3"
    left = [
        "...13333",
        "..133333",
        ".1333333",
        f".133433{t}",
        f".133433{t}",
        f".133433{t}",
        f".133333{t}",
        f".123333{t}",
        f".123333{t2}",
        ".1255555",
        ".1233333",
        ".1223333",
        ".1222222",
    ]
    rows = mirror(left)
    boots = {
        "stand": ["...1771..1771...", "...1771..1771...", "...1111..1111..."],
        "stepL": ["...1771..1771...", "...1771..1111...", "...1111........."],
        "stepR": ["...1771..1771...", "...1111..1771...", "........1111...."],
        "mid":   ["...1771..1771...", "...1111..1111...", "................"],
    }[walk]
    return pad16(rows + boots)


def cloak_side(walk: str):
    """Body facing right: scarf tail flutters back (left), belt at the waist."""
    top = [
        "....13333331....",
        "...1333333331...",
        "..88333333331...",
        ".8993334433331..",
        "..9933343333331.",
        "...133334333331.",
        "...133333333331.",
        "...123333333331.",
        "...125555555221.",
        "...122333333221.",
        "...122222222221.",
    ]
    top = [r[:16].ljust(16, ".") for r in top]
    legs = {
        "stand": ["....1771.1771...", "....1771.1771...", "....1111.1111..."],
        "stepL": ["...1771...1771..", "..1771.....111..", "..1111.........."],
        "stepR": ["....1771..1771..", "...111....1771..", ".........1111..."],
        "mid":   ["....1771.1771...", "....1111.1111...", "................"],
    }[walk]
    return pad16(top + legs)


def block_sets():
    """(col,row) -> rows.  Heads: down/up/side; bodies by facing and walk phase."""
    B = {}
    for c in ((2, 0), (0, 10), (6, 0), (8, 0), (0, 40)):
        B[c] = pad16(HEAD_DOWN)
    for c in ((4, 0), (2, 10), (4, 40)):
        B[c] = pad16(HEAD_UP)
    for c in ((0, 0), (6, 20), (8, 20), (2, 40)):
        B[c] = pad16(HEAD_SIDE)
    # down bodies
    B[(6, 2)] = cloak_front("stand", True)
    for c, ph in (((8, 2), "stepL"), ((10, 2), "mid"), ((10, 36), "stepL"), ((12, 36), "mid"),
                  ((10, 46), "stepL"), ((12, 46), "mid"), ((14, 46), "stepR"), ((0, 11), "stand"),
                  ((12, 4), "stand"), ((0, 6), "stand"), ((0, 54), "stand"), ((6, 22), "stand"), ((0, 24), "stand"),
                  ((8, 30), "stand")):
        B[c] = cloak_front(ph, True)
    # up bodies
    B[(2, 4)] = cloak_front("stand", False)
    ups = ["stepL", "mid", "stepR", "mid", "stepL", "mid", "stepR", "mid"]
    for c, ph in zip(((12, 2), (0, 4), (14, 36), (6, 38), (14, 38), (8, 38), (10, 38), (12, 38)), ups):
        B[c] = cloak_front(ph, False)
    for c, ph in (((6, 24), "stand"), ((8, 24), "mid"), ((10, 24), "stepL"), ((2, 11), "stand"), ((2, 6), "stand"),
                  ((4, 6), "stand"), ((2, 54), "stand"), ((8, 22), "stand"), ((10, 30), "stand")):
        B[c] = cloak_front(ph, False)
    # side bodies
    B[(0, 2)] = cloak_side("stand")
    for c, ph in (((2, 2), "stepL"), ((4, 2), "stepR"), ((14, 32), "mid"), ((8, 36), "stepL"), ((12, 34), "stepR"),
                  ((14, 34), "mid"), ((6, 36), "stepL"), ((4, 46), "stepL"), ((6, 46), "mid"), ((8, 46), "stepR"),
                  ((4, 4), "stand"), ((6, 4), "stand"), ((8, 4), "stand"), ((14, 52), "stand"), ((10, 4), "stand"),
                  ((12, 24), "stand"), ((12, 30), "stand")):
        B[c] = cloak_side(ph)
    return B


FIST = ["........", "..1111..", ".1eeee1.", ".1ebbe1.", ".1ebbe1.", ".1eeee1.", "..1111..", "........"]


def paint(s: Sheet):
    s.set_palette(LINK_PAL)
    s.put(12 * 8, 51 * 8, FIST)            # the 8x8 hand of the side sword slash (art_map section 8.2)
    for (c, r), rows in block_sets().items():
        assert all(len(x) == 16 for x in rows) and len(rows) == 16, (c, r, [len(x) for x in rows], len(rows))
        s.put(c * 8, r * 8, rows)


if __name__ == "__main__":
    s = Sheet("player/LINK.png")
    paint(s)
    s.save()
    print("link painted:", len(block_sets()), "blocks")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        B = block_sets()
        from PIL import Image
        names = [(2, 0), (4, 0), (0, 0), (6, 2), (8, 2), (10, 2), (2, 4), (12, 2), (0, 2), (2, 2), (4, 2)]
        z = 6
        M = Image.new("RGB", (16 * z * len(names), 16 * z * 1), (52, 52, 62))
        for i, k in enumerate(names):
            tmp = Image.new("P", (16, 16)); tmp.putpalette(s.im.getpalette())
            for y in range(16):
                for x in range(16):
                    tmp.putpixel((x, y), s.px[k[0] * 8 + x, k[1] * 8 + y])
            tmp.save("/tmp/opencode/art/_t.png", transparency=0)
            rgba = Image.open("/tmp/opencode/art/_t.png").convert("RGBA").resize((16 * z, 16 * z), Image.NEAREST)
            M.paste(rgba, (i * 16 * z, 0), rgba)
        M.save(out); print(out)
