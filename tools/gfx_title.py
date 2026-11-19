"""HUSH title screen: the logo "HUSH" (violet-to-teal bevelled letters with a glow), a hanging amber lantern, an amber rule, "PRESS START",
a banded deep-indigo backdrop - and the tilemap that shows it, plus the tile pixels it needs.
Shared by gfx_placeholder.py (draws the pixels into the sheets via sheet_tiles), tools/art/cast_title.py (paints PNGs + yaml palettes)
and gfx_insert.py (writes the tilemap stripe stream).

All of it is original (hand-built geometry + the HUSH 5x7 pixel font); only metadata is taken from vanilla:
  * the stream format of IntroLogoTilemap (vendor/usdasm bank_0C.asm:5351, bank_00.asm:3283-3330):
    header [VRAM word addr hi, lo, flags|len hi, len lo]; data runs: len = bytes-1; flag $40 = fixed (one word repeated, len = 2*words-2),
    flag $80 = vertical (+32 words per step); data = tilemap words; $FF ends the stream;
  * which sheets the title tileset loads into which chr slots: tileset $23 + AA2 row $51 =
    GFX_40 (chr tiles $100-$13F), GFX_41 ($140-$17F), GFX_39 ($180-$1BF) (bank_00.asm:11562 AA1, :11158 AA2; chr base word $2000 =
    BG1/BG2 chr, 64 tiles per sheet slot). Sheets 40/41 are used only by title/attract tilesets, so repurposing them is safe.
  * MEASURED (MesenCE, art agent): sheets 40/41 are expanded to the RIGHT half (colours 9-15), sheet 39 to the LEFT half (colours 1-7). BG rows 2-6
    left halves come from `pal_owmain_05` rows 0-4, row 7 left from `pal_owanim_00`; right halves: rows 2&5 / 3&6 / 4&7 = `pal_owaux_03` rows 0 / 1 / 2.
Screen: BG1 tilemap at word $1000, BG2 at $0000, 32 columns per row; BG1 draws over BG2.

Layout (screen cells, 8x8): backdrop = BG2 bands of one solid tile in four left palettes (dark -> lighter around the logo -> dark);
chain cols 15/16 rows 0-3 + lantern cols 15-16 rows 4-6; logo cols 9-22 rows 8-13 (right sheets; palette sets A violet / B blend / C teal by row);
amber rule row 14; PRESS START cols 8-23 rows 19-20 (left sheet, amber). The stream must stay <= 373 bytes (src/FREESPACE.md row $0CDD6D).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gfx_pixfont import GLYPHS  # noqa: E402

STREAM_PC_START_SNES = 0x0CDD6D   # IntroLogoTilemap (bank_0C.asm:5351)
VANILLA_STREAM_END_SNES = 0x0CE1C7   # the $FF terminator of the vanilla stream
STREAM_MAX = 373                  # ledger row $0CDD6D-$0CDEE1

SHEETS = {0x40: 0x100, 0x41: 0x140, 0x39: 0x180}   # sheet id -> first chr tile number it holds
RIGHT_FIRST, LEFT_FIRST = 0x100, 0x180            # tile pools: right-expanded sheets (40, 41) and the left-expanded sheet 39
BLANK_TILE = 0x1BF                                 # transparent tile that wipes BG1

# tilemap palette fields
PAL_A, PAL_B, PAL_C = 2, 3, 4       # right halves of BG rows 2/3/4 (= rows 5/6/7): violet, blend, teal  (pal_owaux_03 rows 0-2)
PAL_AMBER = 6                       # left half of BG row 6: amber set (pal_owmain_05 row 4)
BAND_PALS = (2, 3, 4, 5)            # left halves of BG rows 2-5: idx 1 = the backdrop colour of each band

# ---- colours (hex), written to gfx/src/palettes/title.yaml by tools/art/cast_title.py -----------------------------------------
SET_A = ["06041A", "1A1454", "2E2078", "5A3CC0", "8C64F0", "D8C8FF", "F8F8FF"]      # violet
SET_B = ["06041A", "14284E", "233C7C", "4364B0", "6896D8", "CCE4F8", "F8FFFF"]      # blend
SET_C = ["06041A", "0C3040", "105068", "2C8CA0", "48C8C0", "C0FFF0", "F8FFFF"]      # teal
AMBER = ["0A0618", "3A2008", "7A4A10", "F0A838", "FFD060", "FFF4C8", "B87820"]
BANDS = ["04031A", "08062A", "100C40", "0A0830"]                                    # idx 1 of BG rows 2-5 (left)

LOGO_COL0, LOGO_COLS, LOGO_ROW0, LOGO_ROWS = 9, 14, 8, 6
RULE_ROW = 14
PRESS_COL0, PRESS_COLS, PRESS_ROW0, PRESS_ROWS = 8, 16, 19, 2
LANT_COL0, LANT_ROW0 = 15, 4
CHAIN_ROWS = 4


# ------------------------------------------------------------------------------------------------ the HUSH wordmark
def _rect(m, x0, y0, x1, y1):
    for y in range(y0, y1):
        for x in range(x0, x1):
            m.add((x, y))


def _chamfer(m, w, h, corners, n=3):
    for cx, cy in corners:
        for i in range(n):
            for j in range(n - i):
                m.discard(((0 if cx == 0 else w - 1) + (j if cx == 0 else -j), (0 if cy == 0 else h - 1) + (i if cy == 0 else -i)))


W, H, T = 22, 34, 8        # letter box and stroke


def glyph_H():
    m = set(); _rect(m, 0, 0, T, H); _rect(m, W - T, 0, W, H); _rect(m, T, 13, W - T, 21)
    return m


def glyph_U():
    m = set(); _rect(m, 0, 0, T, H); _rect(m, W - T, 0, W, H); _rect(m, 0, H - T, W, H)
    _chamfer(m, W, H, ((0, 1), (1, 1)), 4)
    return m


def glyph_S():
    m = set(); _rect(m, 0, 0, W, T); _rect(m, 0, 0, T, 21); _rect(m, 0, 13, W, 21); _rect(m, W - T, 13, W, H); _rect(m, 0, H - T, W, H)
    _chamfer(m, W, H, ((0, 0), (1, 0), (0, 1), (1, 1)), 3)
    return m


def logo_canvas():
    """(LOGO_COLS*8) x (LOGO_ROWS*8) pixel rows of palette indices 0-7 (0 transparent), the cell-row gradient is done by the palette per cell row."""
    cw, ch = LOGO_COLS * 8, LOGO_ROWS * 8
    gap, y0 = 4, 7
    total = 4 * W + 3 * gap
    x0 = (cw - total) // 2
    mask = set()
    for i, g in enumerate((glyph_H(), glyph_U(), glyph_S(), glyph_H())):
        for (x, y) in g:
            mask.add((x0 + i * (W + gap) + x, y0 + y))
    img = [[0] * cw for _ in range(ch)]
    near = {}
    for y in range(ch):
        for x in range(cw):
            if (x, y) in mask:
                continue
            d = 9.0
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    if (x + dx, y + dy) in mask:
                        d = min(d, math.hypot(dx, dy))
            near[(x, y)] = d
    for (x, y), d in near.items():
        if d < 1.5:
            img[y][x] = 1
        elif d < 2.6:
            img[y][x] = 3
        elif d < 3.8 and (x + y) % 2 == 0:
            img[y][x] = 2
    for (x, y) in mask:
        up, lf = (x, y - 1) in mask, (x - 1, y) in mask
        dn, rt = (x, y + 1) in mask, (x + 1, y) in mask
        if not up or not lf:
            v = 6
        elif not dn or not rt:
            v = 4
        else:
            v = 5
        if (x, y - 2) not in mask and (x - 2, y) not in mask and v == 6 and (x, y - 1) not in mask and (x - 1, y) not in mask:
            v = 7                                                       # sparkle on every outer top-left corner
        if v == 5 and (x * 7 + y * 13) % 37 == 0:
            v = 6                                                       # a few specular specks
        img[y][x] = v
    return img


# ------------------------------------------------------------------------------------------------ text, lantern, rule, chain
def _glyph_px(ch):
    g = GLYPHS.get(ch.upper(), GLYPHS["?"])
    return [[1 if c == "#" else 0 for c in row] for row in g]


def press_canvas():
    cw, chh = PRESS_COLS * 8, PRESS_ROWS * 8
    img = [[0] * cw for _ in range(chh)]
    text = "PRESS START"
    fill = set()
    adv = 11
    x0 = (cw - (len(text) * adv - 1)) // 2
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        for ry, row in enumerate(_glyph_px(ch)):
            for rx, v in enumerate(row):
                if v:
                    for dy in range(2):
                        for dx in range(2):
                            fill.add((x0 + i * adv + rx * 2 + dx, 1 + ry * 2 + dy))
    for (x, y) in fill:
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                p = (x + dx, y + dy)
                if p not in fill and 0 <= p[0] < cw and 0 <= p[1] < chh:
                    img[p[1]][p[0]] = 1
    for (x, y) in fill:
        r = y - 1
        img[y][x] = 5 if r < 2 else (4 if r < 11 else 7)
    return img


LANTERN = [   # 16 x 24, amber set; 1 outline 3 cage 4 amber 5 bright 6 core 7 dim
    ".......11.......",
    "......1331......",
    "......1..1......",
    "......1..1......",
    ".....111111.....",
    "....13333331....",
    "....13333331....",
    "...1344444431...",
    "...1345555431...",
    "...1345665431...",
    "...1345665431...",
    "...1345665431...",
    "...1345555431...",
    "...1345555431...",
    "...1344554431...",
    "...1344444431...",
    "....13333331....",
    "....13333331....",
    ".....111111.....",
    "......1771......",
    ".......11.......",
    "................",
    "................",
    "................",
]

CHAIN_L = [[0] * 8 for _ in range(8)]
CHAIN_R = [[0] * 8 for _ in range(8)]
for _y in range(8):
    if _y % 4 != 3:
        CHAIN_L[_y][7] = 3 if _y % 4 else 4
        CHAIN_R[_y][0] = 3 if _y % 4 else 4

RULE_MID = [[0] * 8 for _ in range(8)]
for _x in range(8):
    RULE_MID[2][_x] = 2; RULE_MID[3][_x] = 4; RULE_MID[4][_x] = 5; RULE_MID[5][_x] = 2
RULE_L = [[0] * 8 for _ in range(8)]
for _x in range(8):
    if _x >= 4:
        RULE_L[2][_x] = 2; RULE_L[3][_x] = 4; RULE_L[4][_x] = 5; RULE_L[5][_x] = 2
    elif _x >= 2 and _x % 2 == 0:
        RULE_L[3][_x] = 3; RULE_L[4][_x] = 3
RULE_R = [r[::-1] for r in RULE_L]
SOLID = [[1] * 8 for _ in range(8)]
BLANK = [[0] * 8 for _ in range(8)]


def _cells_of(img, cols, rows):
    return {(r, c): [row[c * 8:(c + 1) * 8] for row in img[r * 8:(r + 1) * 8]] for r in range(rows) for c in range(cols)}


# ------------------------------------------------------------------------------------------------ layout
def build():
    """Return (tiles, runs): tiles = {tile_no: 8x8 pixel rows}; runs = list of dicts {layer, row, col, words|word+count, vertical}."""
    tiles: dict[int, list] = {}
    by_pix: dict[tuple, int] = {}
    pools = {"right": RIGHT_FIRST, "left": LEFT_FIRST}

    def tile(pix, pool):
        key = (pool, tuple(map(tuple, pix)))
        if key not in by_pix:
            by_pix[key] = pools[pool]
            tiles[pools[pool]] = [list(r) for r in pix]
            pools[pool] += 1
        return by_pix[key]

    # tile 0x1BF is the blank tile of sheet 39: reserve it (never allocated below)
    tiles[BLANK_TILE] = BLANK
    runs = []
    solid = tile(SOLID, "left")
    # backdrop (BG2): bands of the solid tile; (first row, rows, left palette)
    for r0, n, pal in ((0, 4, 2), (4, 4, 3), (8, 10, 4), (18, 5, 5), (23, 9, 2)):
        runs.append(dict(layer=2, row=r0, col=0, word=(pal << 10) | solid, count=32 * n))
    # chain + lantern (BG1, amber set)
    cl, cr = tile(CHAIN_L, "left"), tile(CHAIN_R, "left")
    runs.append(dict(layer=1, row=0, col=LANT_COL0, word=(PAL_AMBER << 10) | cl, count=CHAIN_ROWS, vertical=True))
    runs.append(dict(layer=1, row=0, col=LANT_COL0 + 1, word=(PAL_AMBER << 10) | cr, count=CHAIN_ROWS, vertical=True))
    lant = _cells_of([[int(ch) if ch != "." else 0 for ch in row] for row in LANTERN], 2, 3)
    for r in range(3):
        runs.append(dict(layer=1, row=LANT_ROW0 + r, col=LANT_COL0,
                         words=[(PAL_AMBER << 10) | tile(lant[(r, c)], "left") for c in range(2)]))
    # logo (BG1, right sheets; palette set per cell row)
    pal_rows = [PAL_A, PAL_A, PAL_A, PAL_B, PAL_C, PAL_C]
    cells = _cells_of(logo_canvas(), LOGO_COLS, LOGO_ROWS)
    for r in range(LOGO_ROWS):
        words = []
        for c in range(LOGO_COLS):
            pix = cells[(r, c)]
            words.append((pal_rows[r] << 10) | (BLANK_TILE if not any(any(p) for p in pix) else tile(pix, "right")))
        # trim blank cells at both ends
        a, b = 0, len(words)
        while a < b and (words[a] & 0x3FF) == BLANK_TILE:
            a += 1
        while b > a and (words[b - 1] & 0x3FF) == BLANK_TILE:
            b -= 1
        if a < b:
            runs.append(dict(layer=1, row=LOGO_ROW0 + r, col=LOGO_COL0 + a, words=words[a:b]))
    # rule (BG1)
    rl, rm, rr = tile(RULE_L, "left"), tile(RULE_MID, "left"), tile(RULE_R, "left")
    runs.append(dict(layer=1, row=RULE_ROW, col=LOGO_COL0, words=[(PAL_AMBER << 10) | rl]))
    runs.append(dict(layer=1, row=RULE_ROW, col=LOGO_COL0 + 1, word=(PAL_AMBER << 10) | rm, count=LOGO_COLS - 2))
    runs.append(dict(layer=1, row=RULE_ROW, col=LOGO_COL0 + LOGO_COLS - 1, words=[(PAL_AMBER << 10) | rr]))
    # PRESS START (BG1, left sheet, amber set)
    pc = _cells_of(press_canvas(), PRESS_COLS, PRESS_ROWS)
    for r in range(PRESS_ROWS):
        words = [(PAL_AMBER << 10) | (BLANK_TILE if not any(any(p) for p in pc[(r, c)]) else tile(pc[(r, c)], "left")) for c in range(PRESS_COLS)]
        a, b = 0, len(words)
        while a < b and (words[a] & 0x3FF) == BLANK_TILE:
            a += 1
        while b > a and (words[b - 1] & 0x3FF) == BLANK_TILE:
            b -= 1
        if a < b:
            runs.append(dict(layer=1, row=PRESS_ROW0 + r, col=PRESS_COL0 + a, words=words[a:b]))
    return tiles, runs


_CACHE: dict = {}


def _built():
    if "b" not in _CACHE:
        _CACHE["b"] = build()
    return _CACHE["b"]


def sheet_tiles(sheet_id: int) -> dict[int, list[list[int]]]:
    """index-in-sheet -> 8x8 pixel rows, for the tiles of this sheet that carry title art (the rest of the sheet stays blank)."""
    base = SHEETS[sheet_id]
    return {t - base: pix for t, pix in _built()[0].items() if base <= t < base + 64 and t != BLANK_TILE}


def cells():
    """Compat: list of (screen_row, screen_col, tile_number, pixel rows) for every non-backdrop BG1 cell."""
    tiles, runs = _built()
    out = []
    for r in runs:
        if r["layer"] != 1:
            continue
        ws = r.get("words") or [r["word"]] * r["count"]
        for i, w in enumerate(ws):
            row = r["row"] + (i if r.get("vertical") else 0)
            col = r["col"] + (0 if r.get("vertical") else i)
            out.append((row, col, w & 0x3FF, tiles[w & 0x3FF]))
    return out


def stream() -> bytes:
    """The replacement IntroLogoTilemap stripe stream (see module docstring for the format)."""
    tiles, runs = _built()
    out = bytearray()
    # wipe BG1 (BG2 is covered by the backdrop bands) with the blank tile
    out += bytes((0x10, 0x00, 0x40 | (2046 >> 8), 2046 & 0xFF)) + _word(BLANK_TILE_WORD)
    for r in runs:
        base = 0x1000 if r["layer"] == 1 else 0x0000
        addr = base + r["row"] * 32 + r["col"]
        if "word" in r:
            n = r["count"]
            flags = 0x40 | (0x80 if r.get("vertical") else 0)
            ln = 2 * n - 2
            out += bytes((addr >> 8, addr & 0xFF, flags | (ln >> 8), ln & 0xFF)) + r["word"].to_bytes(2, "little")
        else:
            data = b"".join(w.to_bytes(2, "little") for w in r["words"])
            ln = len(data) - 1
            out += bytes((addr >> 8, addr & 0xFF, ln >> 8, ln & 0xFF)) + data
    out.append(0xFF)
    assert len(out) <= STREAM_MAX, f"title stream {len(out)} B > ledger row {STREAM_MAX} B"
    return bytes(out)


BLANK_TILE_WORD = (PAL_AMBER << 10) | BLANK_TILE


def _word(w: int) -> bytes:
    return w.to_bytes(2, "little")


if __name__ == "__main__":
    s = stream()
    t, runs = _built()
    print(f"title stream: {len(s)} / {STREAM_MAX} bytes, {len(runs)} runs, {len(t)} tiles "
          f"(right pool ${RIGHT_FIRST:X}..${max(k for k in t if k < 0x180):X}, left pool ${LEFT_FIRST:X}..${max(k for k in t if 0x180 <= k < 0x1BF):X})")
