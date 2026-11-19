#!/usr/bin/env python3
"""font_art.py: HUSH's text-box / dialogue font (gfx/src/font/FONT.png, 2bpp, ROM $0E8000, 256 tiles = 128 glyphs of 8x16).

  .venv/bin/python tools/art/font_art.py            # patch the glyphs listed in PATCHES into FONT.png (idempotent) + validate
  .venv/bin/python tools/art/font_art.py --preview docs/gfx/screenshots/font_preview.png   # sample text composed like the text box does

The font is the HUSH pixel font (5x7 caps, every pixel row doubled = 14 rows in a 16 row cell, index 1 only); the A0 sheet already
holds every vanilla glyph. This script only fixes what is wrong in it and adds the glyphs HUSH needs (ending screen: ':' and digits):

  * glyph code g sits at cell column (g & 15), cell row (g >> 4) * 2 (top tile) and the row below (bottom tile): tile idx = (g>>4)*32 + (g&15) (+16)
    (RenderText_PerformVWFing, bank_0E.asm:$0ECBA1-$0ECBCF: `(g & $F0) << 1 | (g & $0F)`, TheFont $0E8000, 16 bytes per tile).
  * advance width of every glyph = `.width` table (bank_0E.asm:$0ECADF-$0ECB41): the text box draws only that many pixel columns of a glyph,
    so a glyph must be at most `width` px wide and keep 1 px of its width as the gap. M T V W X Y (and lower case) have width 7: they are
    redrawn 6 px wide (the A0 versions were 5 px wide: 2 px gaps after them); '?' likewise.
  * NEW glyphs (vanilla symbols nobody uses in HUSH): $47 ':' (was ankh), $48 '/' (was waves), $49 '+' (was a stray 'S'). Apostrophe is $51, '-' $40, '.' $41,
    ',' $42, '!' $3E, '?' $3F, digits $34-$3D, space $59 (no pixels).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gfx_convert  # noqa: E402

FONT = ROOT / "gfx" / "src" / "font" / "FONT.png"

# advance widths, bank_0E.asm:$0ECADF-$0ECB41 (A-Z, a-z, 0-9, ! ? - . , ..., > ( ) 3 symbols, 2 link-face halves, " 4 arrows ', 7 hearts, space, < 4 buttons, I i ! space)
WIDTHS = (
    [6, 6, 6, 6, 6, 6, 6, 6, 3, 6, 6, 6, 7, 6, 6, 6, 6, 6, 6, 7, 6, 7, 7, 7, 7, 6]
    + [6, 6, 6, 6, 6, 6, 6, 6, 3, 5, 6, 3, 7, 6, 6, 6, 6, 5, 6, 6, 6, 7, 7, 7, 7, 6]
    + [6, 4, 6, 6, 6, 6, 6, 6, 6, 6]
    + [3, 7, 6, 4, 4, 6, 8, 6, 6, 6, 6, 6, 8, 8, 8, 7, 7, 7, 7, 4]
    + [8] * 7 + [4, 8, 8, 8, 8, 8, 8, 8, 8, 4]
)
CODE = {}
for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
    CODE[c] = i
for i, c in enumerate("abcdefghijklmnopqrstuvwxyz"):
    CODE[c] = 26 + i
for i, c in enumerate("0123456789"):
    CODE[c] = 52 + i
CODE.update({"!": 0x3E, "?": 0x3F, "-": 0x40, ".": 0x41, ",": 0x42, ":": 0x47, "/": 0x48, "+": 0x49, "'": 0x51, " ": 0x59})

# glyph = 7 pixel rows (each drawn twice), width <= advance; '#' = index 1
M6 = ["#....#", "##..##", "#.##.#", "#.##.#", "#....#", "#....#", "#....#"]
T6 = ["######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##.."]
V6 = ["#....#", "#....#", "#....#", "#....#", ".#..#.", ".#..#.", "..##.."]
W6 = ["#....#", "#....#", "#....#", "#.##.#", "#.##.#", "##..##", "#....#"]
X6 = ["#....#", "#....#", ".#..#.", "..##..", ".#..#.", "#....#", "#....#"]
Y6 = ["#....#", "#....#", ".#..#.", "..##..", "..##..", "..##..", "..##.."]
Q6 = [".####.", "#....#", ".....#", "...##.", "..#...", "......", "..#..."]
I2 = ["##."] * 7                                  # I i: plain 2 px stem (advance 3), as heavy as the 2 px horizontal bars
BANG = ["##."] * 5 + ["..."] + ["##."]
COLON = ["....", ".##.", ".##.", "....", ".##.", ".##.", "...."]
SLASH = ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."]
PLUS = [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."]

PATCHES = {
    0x0C: M6, 0x26: M6,                       # M m
    0x13: T6,                                 # T   (t, advance 6, keeps the 5 px T)
    0x15: V6, 0x2F: V6,                       # V v
    0x16: W6, 0x30: W6,                       # W w
    0x17: X6, 0x31: X6,                       # X x
    0x18: Y6, 0x32: Y6,                       # Y y
    0x3F: Q6,                                 # ?
    0x08: I2, 0x22: I2, 0x25: I2,             # I i l (l was only the bottom bar)
    0x3E: BANG,                               # !
    0x47: COLON, 0x48: SLASH, 0x49: PLUS,
}


def tile_xy(tile: int) -> tuple[int, int]:
    return (tile % 16) * 8, (tile // 16) * 8


def glyph_tiles(g: int) -> tuple[int, int]:
    t = (g >> 4) * 32 + (g & 15)
    return t, t + 16


def write_glyph(px, g: int, rows: list[str]) -> None:
    assert len(rows) == 7 and max(len(r) for r in rows) <= WIDTHS[g], (hex(g), WIDTHS[g], rows)
    cell = [[0] * 8 for _ in range(16)]
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c == "#":
                cell[1 + 2 * y][x] = cell[2 + 2 * y][x] = 1
    top, bottom = glyph_tiles(g)
    for part, t in enumerate((top, bottom)):
        ox, oy = tile_xy(t)
        for y in range(8):
            for x in range(8):
                px[ox + x, oy + y] = cell[part * 8 + y][x]


def read_glyph(im: Image.Image, g: int) -> list[list[int]]:
    px = im.load()
    out = []
    for t in glyph_tiles(g):
        ox, oy = tile_xy(t)
        for y in range(8):
            out.append([px[ox + x, oy + y] for x in range(8)])
    return out


def apply() -> None:
    im = Image.open(FONT)
    assert im.mode == "P" and im.size == (128, 128)
    px = im.load()
    for g, rows in PATCHES.items():
        write_glyph(px, g, rows)
    im.save(FONT, transparency=0)


def preview(out: Path, zoom: int = 3) -> None:
    """compose sample text like RenderText_PerformVWFing does: glyph pixels clipped to the advance width, 16 px per line, palette group 6"""
    import yaml

    pal = yaml.safe_load((ROOT / "gfx/src/palettes/hud.yaml").read_text())["groups"]["pal_hud_06"]["colours"][0]
    col = [tuple(int(str(h).zfill(6)[k:k + 2], 16) & 0xF8 for k in (0, 2, 4)) for h in pal]
    im = Image.open(FONT)
    lines = [
        "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "abcdefghijklm", "nopqrstuvwxyz", "0123456789 !?-.,:'/+",
        "THE VAULT IS EMPTY", "AND NOBODY HEARD A THING", "TIME 02:47  CAUGHT 3  FLOORS 3/3",
    ]
    W = 224
    img = Image.new("RGB", (W, 16 * len(lines) + 16), col[3])
    ip = img.load()
    fp = im.load()
    for ly, line in enumerate(lines):
        x = 8
        for ch in line:
            g = CODE[ch]
            w = WIDTHS[g]
            if ch != " ":
                for part, t in enumerate(glyph_tiles(g)):
                    ox, oy = tile_xy(t)
                    for yy in range(8):
                        for xx in range(min(w, 8)):
                            k = fp[ox + xx, oy + yy]
                            if k and x + xx < W:
                                ip[x + xx, 8 + ly * 16 + part * 8 + yy] = col[k]
            x += w
    img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="PNG")
    ap.add_argument("--zoom", type=int, default=3)
    a = ap.parse_args()
    if a.preview:
        preview(Path(a.preview), a.zoom)
        print("wrote", a.preview)
        return 0
    apply()
    errors: list[str] = []
    gfx_convert.process(FONT, False, errors, [])
    for e in errors:
        print("ERROR", e)
    print("FONT: patched glyphs", " ".join(f"{g:02X}" for g in sorted(PATCHES)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
