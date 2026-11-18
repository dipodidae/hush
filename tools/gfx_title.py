"""HUSH title screen (placeholder): logo "HUSH" + "PRESS START", the tilemap that shows it, and the
tile pixels it needs. Shared by gfx_placeholder.py (draws the pixels into the sheets) and
gfx_insert.py (writes the tilemap stripe stream).

Why this exists: the vanilla title is a big pre-made logo made of ~160 unique tiles; a placeholder with
labelled tiles is unreadable, and the player has to read PRESS START to test the game. So the title is
laid out again with OUR cells: one unique tile per logo cell, text drawn with the HUSH pixel font.
All of it is original (flat colours, a 5x7 font, scaled); only metadata is taken from vanilla:
  * the stream format of IntroLogoTilemap (vendor/usdasm bank_0C.asm:5351, bank_00.asm:3283-3330):
    header [VRAM word addr hi, lo, flags|len hi, len lo]; len = bytes-1; flag $40 = fixed (one word
    repeated, len = 2*words-2), flag $80 = vertical; data = tilemap words; $FF ends the stream;
  * which sheets the title tileset loads into which chr slots: tileset $23 + AA2 row $51 =
    GFX_40 (chr tiles $100-$13F), GFX_41 ($140-$17F), GFX_39 ($180-$1BF) (bank_00.asm:11562 AA1,
    :11158 AA2; chr base word $2000 = BG1/BG2 chr, 64 tiles per sheet slot). Sheets 40/41 are used
    only by title/attract tilesets (docs/gfx/inventory.yaml usage), so repurposing them is safe.
Screen: BG1 tilemap at word $1000, 32 columns per row.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gfx_pixfont import GLYPHS  # noqa: E402

COLS = 18
HUSH_ROWS = 7
PRESS_ROWS = 2
HUSH_Y0 = 9            # screen row of the first HUSH cell row
PRESS_Y0 = 20
COL0 = 7               # screen column of the first cell
FIRST_TILE = 0x100     # chr tile number of the first logo cell
BLANK_TILE = 0x1BF     # transparent tile used to wipe both layers
PAL = 6                # tilemap palette field (all title palettes are identical, so any works)
STREAM_PC_START_SNES = 0x0CDD6D   # IntroLogoTilemap (bank_0C.asm:5351)
VANILLA_STREAM_END_SNES = 0x0CE1C7   # the $FF terminator of the vanilla stream

# colour indices (title palette, see gfx_placeholder.FAMILIES["title"])
C_SHADOW, C_LETTER, C_AMBER, C_WHITE = 3, 4, 5, 6

SHEETS = {0x40: 0x100, 0x41: 0x140, 0x39: 0x180}   # sheet id -> first chr tile number it holds


def _text(px, x, y, s, c, scale):
    for i, ch in enumerate(s):
        g = GLYPHS.get(ch.upper(), GLYPHS["?"])
        for ry, row in enumerate(g):
            for rx, v in enumerate(row):
                if v == "#":
                    for dy in range(scale):
                        for dx in range(scale):
                            xx, yy = x + i * 6 * scale + rx * scale + dx, y + ry * scale + dy
                            if 0 <= yy < len(px) and 0 <= xx < len(px[0]):
                                px[yy][xx] = c


def composite():
    """The logo image: 144x56 (HUSH, with shadow and amber rules) and 144x16 (PRESS START)."""
    w = COLS * 8
    hush = [[0] * w for _ in range(HUSH_ROWS * 8)]
    for x in range(10, w - 10):
        hush[6][x] = C_AMBER; hush[7][x] = C_AMBER
        hush[48][x] = C_AMBER; hush[49][x] = C_AMBER
    _text(hush, 26 + 3, 14 + 3, "HUSH", C_SHADOW, 4)
    _text(hush, 26, 14, "HUSH", C_WHITE, 4)
    press = [[0] * w for _ in range(PRESS_ROWS * 8)]
    _text(press, 7, 1, "PRESS START", C_AMBER, 2)
    return hush, press


def cells():
    """list of (screen_row, screen_col, tile_number, pixel rows 8x8)."""
    hush, press = composite()
    out = []
    k = 0
    for img, rows, y0 in ((hush, HUSH_ROWS, HUSH_Y0), (press, PRESS_ROWS, PRESS_Y0)):
        for r in range(rows):
            for c in range(COLS):
                tile = [row[c * 8:(c + 1) * 8] for row in img[r * 8:(r + 1) * 8]]
                out.append((y0 + r, COL0 + c, FIRST_TILE + k, tile))
                k += 1
    return out


def sheet_tiles(sheet_id: int) -> dict[int, list[list[int]]]:
    """index-in-sheet -> 8x8 pixel rows, for the tiles of this sheet that carry title cells."""
    base = SHEETS[sheet_id]
    res = {}
    for _, _, t, pix in cells():
        if base <= t < base + 64:
            res[t - base] = pix
    return res


def _word(t: int) -> bytes:
    w = (PAL << 10) | t
    return bytes((w & 0xFF, w >> 8))


def stream() -> bytes:
    """The replacement IntroLogoTilemap stripe stream (see module docstring for the format)."""
    out = bytearray()
    for addr in (0x0000, 0x1000):          # wipe BG2 and BG1 (32x32 each) with the blank tile
        out += bytes((addr >> 8, addr & 0xFF, 0x40 | (2046 >> 8), 2046 & 0xFF)) + _word(BLANK_TILE)
    by_row: dict[int, list] = {}
    for y, x, t, _ in cells():
        by_row.setdefault(y, []).append((x, t))
    for y in sorted(by_row):
        row = sorted(by_row[y])
        addr = 0x1000 + y * 32 + row[0][0]
        data = b"".join(_word(t) for _, t in row)
        n = len(data) - 1
        out += bytes((addr >> 8, addr & 0xFF, n >> 8, n & 0xFF)) + data
    out.append(0xFF)
    return bytes(out)


if __name__ == "__main__":
    s = stream()
    print(f"title stream: {len(s)} bytes, {len(cells())} cells, tiles ${FIRST_TILE:X}..${FIRST_TILE + len(cells()) - 1:X}")
