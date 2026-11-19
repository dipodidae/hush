#!/usr/bin/env python3
"""Paint gfx/src/sprite/GFX_BC.png: the lantern guard (14 blocks, contract = docs/gfx/art_map.md section 5).

Index meaning (calm, OBJ row 4; alert OBJ row 6 recolours the same indices amber, Hush_PalAlert):
  1 outline   2 helmet / pauldrons / boots (dark slate)   3 deep shade   4 uniform (steel blue)   5 amber (lantern, helmet badge, buckle)
  6 highlights / eyes (pale)   7 never used (violet in the alert row)
Run:  .venv/bin/python tools/art/cast_guard.py [--preview out.png]
"""
from __future__ import annotations

import sys

from cast_common import Sheet, check, hflip, mirror, pad, render_preview
import cast_pal

HEAD_DOWN = mirror([
    "......11",
    "....1122",
    "...12244",
    "..122244",
    "..122225",
    "..122222",
    "..144444",
    "..133333",
    "..133663",
    "..133333",
    "...13444",
    "....1144",
])
HEAD_UP = mirror([
    "......11",
    "....1122",
    "...12224",
    "..122224",
    "..122224",
    "..122224",
    "..144444",
    "..133333",
    "..133333",
    "...13333",
    "....1144",
    "......11",
])
# head in profile, LEFT: visor slit and eye on the left, helmet back on the right
HEAD_SIDE = [
    "......1111......",
    "....1122222211..",
    "...122442222221.",
    "..1224422222221.",
    "..1222222222221.",
    "..1444444422221.",
    "..1333332222221.",
    "..1663332222221.",
    "..1333332222221.",
    "...13344444441..",
    "....1144444411..",
    "......111111....",
]
HEAD_SLEEP = mirror([
    "......11",
    "....1122",
    "...12244",
    "..122244",
    "..122225",
    "..122222",
    "..144444",
    "..133333",
    "..134433",
    "..133333",
    "...13444",
    "....1144",
])
BODY_DOWN_A = mirror([
    "........",
    "..111111",
    ".1224444",
    ".1224443",
    ".1224443",
    ".1244443",
    ".1344443",
    ".1344443",
    ".1334443",
    ".1222225",
    ".1222225",
    ".1111111",
    "...1331.",
    "...1331.",
    "...1221.",
    "...1111.",
])
BODY_DOWN_B = mirror([
    "........",
    "..111111",
    ".1224444",
    ".1224443",
    ".1224443",
    ".1244443",
    ".1344443",
    ".1344443",
    ".1334443",
    ".1222225",
    ".1222225",
    ".1111111",
    "...1331.",
    "...1331.",
    "...1221.",
    "...1111.",
])
# step: the right leg (screen right half) is lifted one row
BODY_DOWN_B = [r for r in BODY_DOWN_B]
BODY_DOWN_B[14] = "...1221..1111..."
BODY_DOWN_B[15] = "...1111........."
BODY_UP_A = mirror([
    "........",
    "..111111",
    ".1224444",
    ".1224443",
    ".1224443",
    ".1244443",
    ".1344443",
    ".1344443",
    ".1334443",
    ".1222222",
    ".1222222",
    ".1111111",
    "...1331.",
    "...1331.",
    "...1221.",
    "...1111.",
])
BODY_UP_B = list(BODY_UP_A)
BODY_UP_B[14] = "...1221..1111..."
BODY_UP_B[15] = "...1111........."
# profile LEFT: front arm (idx 2) toward the lantern, cape at the back (idx 3), belt with buckle at the front
BODY_SIDE_A = [
    "................",
    "....11111111....",
    "...1222444441...",
    "...1244444431...",
    "...1244444431...",
    "...1224444431...",
    "...1224444431...",
    "...1224444431...",
    "...1344444431...",
    "...1522222221...",
    "...1522222221...",
    "...1111111111...",
    ".....133331.....",
    ".....133331.....",
    ".....122221.....",
    ".....111111.....",
]
BODY_SIDE_B = list(BODY_SIDE_A[:12]) + [
    "..13331..13331..",
    "..13331..13331..",
    "..12221..11111..",
    "..11111.........",
]
BODY_SIDE_C = list(BODY_SIDE_A[:12]) + [
    "...13331.13331..",
    "...13331.13331..",
    "...11111.12221..",
    "..........11111.",
]
BODY_SLEEP = [
    "................",
    "................",
    "................",
    "................",
    ".....111111.....",
    "...1144444411...",
    "..114446644411..",
    "..144444444441..",
    ".14444444444441.",
    ".14444444444441.",
    ".12255555555221.",
    ".12222555522221.",
    "..122222222221..",
    "..113222222311..",
    "...1133333311...",
    ".....111111.....",
]
LANTERN_0 = [
    "...11...",
    "..1221..",
    "..1551..",
    "..1651..",
    "..1551..",
    "..1221..",
    "...11...",
    "........",
]
LANTERN_1 = [
    "...11...",
    "..1221..",
    "..1651..",
    "..1661..",
    "..1561..",
    "..1221..",
    "...11...",
    "........",
]
BLOCKS = {
    (0, 0): (HEAD_DOWN, 16, 16), (16, 0): (HEAD_UP, 16, 16), (32, 0): (HEAD_SIDE, 16, 16), (48, 0): (HEAD_SLEEP, 16, 16),
    (64, 0): (BODY_DOWN_A, 16, 16), (80, 0): (BODY_DOWN_B, 16, 16), (96, 0): (BODY_UP_A, 16, 16), (112, 0): (BODY_UP_B, 16, 16),
    (0, 16): (BODY_SIDE_A, 16, 16), (16, 16): (BODY_SIDE_B, 16, 16), (32, 16): (BODY_SIDE_C, 16, 16), (48, 16): (BODY_SLEEP, 16, 16),
    (64, 16): (LANTERN_0, 8, 8), (72, 16): (LANTERN_1, 8, 8),
}


def paint(sheet: Sheet):
    sheet.set_palette(cast_pal.GUARD)
    sheet.clear(0, 0, sheet.w, sheet.h)
    for (x, y), (rows, w, h) in BLOCKS.items():
        sheet.put(x, y, pad(check(rows if len(rows) == h else pad(rows, w, h), w, h, f"{x},{y}"), w, h))


if __name__ == "__main__":
    s = Sheet("sprite/GFX_BC.png")
    paint(s)
    s.save()
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        from PIL import Image
        a = render_preview(s, (0, 0, 128, 32), cast_pal.GUARD, 6)
        b = render_preview(s, (0, 0, 128, 32), cast_pal.ALERT[:6] + ["A878F0"], 6)
        m = Image.new("RGB", (a.width, a.height * 2 + 6), (0, 0, 0))
        m.paste(a, (0, 0)); m.paste(b, (0, a.height + 6)); m.save(out)
        print("preview", out)
