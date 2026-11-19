#!/usr/bin/env python3
"""Paint the title sheets (GFX_40 GFX_41 GFX_39) from tools/gfx_title.py and write gfx/src/palettes/title.yaml.

  .venv/bin/python tools/art/cast_title.py [--preview out.png]     (preview = the 256x224 screen composed from the tilemap, as the game shows it)
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "art"))
import gfx_title as T  # noqa: E402
from cast_common import Sheet, hex2rgb, snap  # noqa: E402

SETS = {"A": [snap(h) for h in T.SET_A], "B": [snap(h) for h in T.SET_B], "C": [snap(h) for h in T.SET_C]}
AMBER = [snap(h) for h in T.AMBER]
BANDS = [snap(h) for h in T.BANDS]


def paint_sheets():
    for sid, pal, name in ((0x40, SETS["A"], "GFX_40"), (0x41, SETS["A"], "GFX_41"), (0x39, AMBER, "GFX_39")):
        s = Sheet(f"title/{name}.png")
        s.set_palette(pal)
        s.clear(0, 0, s.w, s.h)
        for idx, pix in T.sheet_tiles(sid).items():
            x0, y0 = (idx % 16) * 8, (idx // 16) * 8
            for y, row in enumerate(pix):
                for x, v in enumerate(row):
                    s.px[x0 + x, y0 + y] = v
        s.save()


def write_yaml():
    def row(cols):
        return "[" + ", ".join(f"'{c}'" for c in cols) + "]"
    left = [[b] + AMBER[1:] for b in BANDS] + [AMBER]            # BG rows 2-5: idx 1 = band colour; row 6: the amber set
    p = ROOT / "gfx" / "src" / "palettes" / "title.yaml"
    t = p.read_text()
    import re

    def setg(t, group, rows):
        m = re.search(rf"(  {group}:\n(?:    .*\n)*?    colours:\n)((?:    - \[.*\]\n)+)", t)
        assert m and m.group(2).count("\n") == len(rows), (group, len(rows))
        return t[:m.start(2)] + "".join(f"    - {row(r)}\n" for r in rows) + t[m.end(2):]
    t = setg(t, "pal_owanim_00", [AMBER])                           # BG row 7 left (unused)
    t = setg(t, "pal_owmain_05", left)                              # BG rows 2-6 left halves
    t = setg(t, "pal_owaux_03", [SETS["A"], SETS["B"], SETS["C"]])  # right halves: rows 2&5, 3&6, 4&7
    t = re.sub(r"^note: .*?(?=^groups:)", "note: 'Title screen palettes (the intro loads these overworld palette slots; measured in MesenCE). pal_owmain_05 rows 0-4 = BG rows 2-6 LEFT half (sheet GFX_39): rows 0-3 idx 1 = backdrop band colour, row 4 = amber set (lantern, rule, PRESS START). pal_owaux_03 rows 0-2 = RIGHT halves of BG rows 2/5, 3/6, 4/7 (sheets GFX_40/41, the logo): A violet, B blend, C teal. Colours are RGB hex; the build converts to BGR555.'\n", t, flags=re.M | re.S)
    p.write_text(t)


def write_briefs():
    import json
    import re
    def block(family, note, names, cols):
        s = f"palette:\n  family: {family}\n  note: {json.dumps(note)}\n  indices:\n"
        for i, (n, c) in enumerate(zip(names, cols), start=1):
            s += f"    {i}: {json.dumps('#' + c + ' ' + n)}\n"
        return s
    logo_names = ["outline", "outer glow (dither)", "inner glow", "letter shade", "letter main", "letter highlight", "sparkle"]
    amber_names = ["outline (BG bands: backdrop colour)", "dim halo", "dark amber (cage, chain)", "AMBER", "bright amber", "pale core", "text shade"]
    for name, fam, note, names, cols in (
            ("GFX_40", "title-logo", "RIGHT half of BG rows 2/3/4: logo letters. Shown: set A (violet); the game uses A (rows 0-2 of the logo), B (row 3), C teal (rows 4-5) per cell row", logo_names, SETS["A"]),
            ("GFX_41", "title-logo", "RIGHT half of BG rows 2/3/4: logo letters. Shown: set A (violet); the game uses A, B, C per cell row", logo_names, SETS["A"]),
            ("GFX_39", "title-amber", "LEFT half of BG row 6: lantern, chain, rule, PRESS START (amber set); idx 1 of BG rows 2-5 = backdrop band colours", amber_names, AMBER)):
        p = ROOT / "gfx" / "src" / "title" / f"{name}.yaml"
        t = p.read_text()
        t = re.sub(r"^palette:\n(?:  .*\n)+", block(fam, note, names, cols), t, count=1, flags=re.M)
        p.write_text(t)


def preview(out):
    from PIL import Image
    tiles, runs = T._built()
    # compose BG2 + BG1 as the PPU would
    bg = {1: {}, 2: {}}
    for r in runs:
        ws = r.get("words") or [r["word"]] * r["count"]
        for i, w in enumerate(ws):
            row = r["row"] + (i if r.get("vertical") else 0)
            col = r["col"] + (0 if r.get("vertical") else i)
            if "count" in r and r["layer"] == 2:
                row, col = (r["row"] * 32 + i) // 32, (r["row"] * 32 + i) % 32
            bg[r["layer"]][(row, col)] = w
    left_rows = {2: [None] + [BANDS[0]] + AMBER[1:], 3: [None, BANDS[1]] + AMBER[1:], 4: [None, BANDS[2]] + AMBER[1:], 5: [None, BANDS[3]] + AMBER[1:], 6: AMBER, 7: AMBER}
    # left_rows[p] indexed by colour idx (0 = transparent)
    def lpal(p):
        if p in (2, 3, 4, 5):
            return [None, BANDS[p - 2]] + AMBER[1:][1:]  # idx 1 band, idx 2.. amber set idx 2..
        return [None] + AMBER
    right_pal = {2: SETS["A"], 3: SETS["B"], 4: SETS["C"], 5: SETS["A"], 6: SETS["B"], 7: SETS["C"]}
    im = Image.new("RGB", (256, 224), (0, 0, 0))
    for layer in (2, 1):
        for (row, col), w in bg[layer].items():
            if row >= 28 or col >= 32:
                continue
            tno, pal = w & 0x3FF, (w >> 10) & 7
            pix = tiles.get(tno)
            if pix is None:
                continue
            right = tno < 0x180
            colours = ([None] + right_pal[pal]) if right else lpal(pal)
            for y in range(8):
                for x in range(8):
                    v = pix[y][x]
                    if v:
                        im.putpixel((col * 8 + x, row * 8 + y), hex2rgb(colours[v]))
    im.resize((768, 672), Image.NEAREST).save(out)


if __name__ == "__main__":
    paint_sheets()
    write_yaml()
    write_briefs()
    print("title painted; stream", len(T.stream()), "bytes")
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
