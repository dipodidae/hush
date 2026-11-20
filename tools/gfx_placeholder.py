#!/usr/bin/env python3
"""Generate HUSH's original placeholder graphics from docs/gfx/inventory.yaml.

  gfx_placeholder.py            write gfx/src/<kind>/<id>.png + .yaml, gfx/guides/<id>_guide.png,
                                gfx/src/palettes/*.yaml and build/gfx_gallery.html

Placeholders are ORIGINAL: flat colours, simple shapes, outlines, text labels, tile-index
labels, frame numbers. The only thing taken from vanilla is metadata (inventory.yaml:
dimensions, tile positions, frame counts, bit depth, compressed capacity). This script never
reads vanilla pixels (it does not touch build/ref/sheets).

Each sheet is drawn as a 16-tile-wide indexed PNG, tile order row-major = ROM tile order, so it
can be inserted unchanged. 3bpp sheets use <= 7 opaque colours, 2bpp <= 3, 4bpp <= 15.
Compressed slots have a byte capacity (the slot is packed with no slack); the generator picks the
most detailed drawing level that compresses into the slot and records it in the brief
(`fit.level`: 0 labelled tiles, 1 bordered tiles, 2 flat, 3 empty).
These are PLACEHOLDERS, not final art. A human draws the real art over these files.
"""
from __future__ import annotations

import html
import sys
from pathlib import Path

import yaml
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from gfx_compress import compress  # noqa: E402
from gfx_convert import encode  # noqa: E402
from gfx_pixfont import GLYPHS, HEX3  # noqa: E402
import gfx_title  # noqa: E402

INV = ROOT / "docs" / "gfx" / "inventory.yaml"
SRC = ROOT / "gfx" / "src"
GUIDES = ROOT / "gfx" / "guides"
GALLERY = ROOT / "build" / "gfx_gallery.html"


def hexrgb(s: str):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# ---- palettes: index meanings are the contract between the PNGs and the ROM palettes ------------
FAMILIES = {
    "spr": dict(role_note="3bpp sprite sheets (indices 1-7)", colours={
        1: ("0B0A1E", "outline / ink (near-black indigo)"),
        2: ("38327A", "body / coat (indigo)"),
        3: ("231F4F", "shade (dark indigo)"),
        4: ("9A94D9", "light neutral / highlight"),
        5: ("F2A93B", "AMBER = danger: lantern, alert, guard accent"),
        6: ("ECE8FF", "glyphs, text, eyes (near white)"),
        7: ("A878F0", "VIOLET = you: player, tools"),
    }),
    "bg": dict(role_note="3bpp background tiles (indices 1-7)", colours={
        1: ("07061A", "pit / deepest dark"),
        2: ("2A2660", "floor base (indigo)"),
        3: ("322D70", "floor checker alternate"),
        4: ("171436", "wall (darker than floor)"),
        5: ("5A54A8", "wall highlight edge / rim"),
        6: ("F2A93B", "torch lit / lamp light (amber)"),
        7: ("8A88A0", "gray: unlit torch, door letters, labels"),
    }),
    "hud": dict(role_note="2bpp HUD / menu / font (indices 1-3)", colours={
        1: ("ECE8FF", "text light"),
        2: ("6C66C8", "mid tone / panel"),
        3: ("14123A", "dark / outline"),
    }),
    "link": dict(role_note="4bpp player sheet (indices 1-15)", colours={
        1: ("0B0A1E", "outline"), 2: ("4B2E8C", "cloak dark"), 3: ("7048C8", "cloak"),
        4: ("A878F0", "violet main"), 5: ("C9ABFF", "violet light"), 6: ("ECE8FF", "face dot / eyes"),
        7: ("231F4F", "boots / shade"), 8: ("E3D4FF", "blade edge / highlight"), 9: ("6E64B4", "belt / trim"),
        10: ("5E3AA8", "violet mid dark"), 11: ("8B63DD", "violet mid"), 12: ("B58FFF", "violet bright"),
        13: ("3B2470", "cloak deepest"), 14: ("D8C7FF", "pale violet"), 15: ("F4EEFF", "near white"),
    }),
    "title": dict(role_note="title screen sheets (indices 1-7); same colours in every title palette row", colours={
        1: ("07061A", "deep (shadow/outline)"), 2: ("2A2660", "indigo panel"), 3: ("5A54A8", "logo shadow"),
        4: ("B8B2F0", "lavender (spare)"), 5: ("F2A93B", "AMBER accent: rules, PRESS START"),
        6: ("ECE8FF", "logo letters (near white)"), 7: ("171436", "dark indigo (spare)"),
    }),
    "cut": dict(role_note="magenta debug sheets: UNUSED / CUT (indices 1-7)", colours={
        1: ("FF00FF", "magenta fill"), 2: ("101010", "label text (black)"), 3: ("FF66FF", "light magenta"),
        4: ("B000B0", "dark magenta"), 5: ("FF00FF", "magenta"), 6: ("FF99FF", "pale magenta"), 7: ("400040", "deep magenta"),
    }),
}


def family_palette(fam: str, n: int):
    cols = FAMILIES[fam]["colours"]
    pal = [(0, 0, 0)] + [hexrgb(cols[i][0]) for i in range(1, min(n, len(cols) + 1))]
    return pal + [(0, 0, 0)] * (n - len(pal))


# ---- canvas ------------------------------------------------------------------------------------
class Canvas:
    def __init__(self, wt: int, ht: int, fill: int = 0):
        self.w, self.h = wt * 8, ht * 8
        self.px = [[fill] * self.w for _ in range(self.h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def frame(self, x, y, w, h, c):
        for xx in range(x, x + w):
            self.set(xx, y, c); self.set(xx, y + h - 1, c)
        for yy in range(y, y + h):
            self.set(x, yy, c); self.set(x + w - 1, yy, c)

    def line(self, x0, y0, x1, y1, c, thick=1):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i // n
            y = y0 + (y1 - y0) * i // n
            self.rect(x, y, thick, thick, c)

    def disc(self, cx, cy, r, c):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1:
                    self.set(x, y, c)

    def glyph(self, x, y, ch, c, scale=1):
        g = GLYPHS.get(ch.upper(), GLYPHS["?"])
        for ry, row in enumerate(g):
            for rx, v in enumerate(row):
                if v == "#":
                    self.rect(x + rx * scale, y + ry * scale, scale, scale, c)

    def text(self, x, y, s, c, scale=1):
        for i, ch in enumerate(s):
            self.glyph(x + i * 6 * scale, y, ch, c, scale)

    def hex2(self, x, y, n, c):
        for i, d in enumerate(f"{n:02X}"):
            for ry, row in enumerate(HEX3[d]):
                for rx, v in enumerate(row):
                    if v == "#":
                        self.set(x + i * 4 + rx, y + ry, c)

    def tile_rect(self, tx, ty):
        return tx * 8, ty * 8


# ---- sheet drawers ------------------------------------------------------------------------------
def draw_tiles_grid(cv: Canvas, gw: int, gh: int, level: int, base: int, edge: int, label: int, nonblank=None):
    """Labelled tile grid. Tiles that are blank in vanilla (metadata: inventory `nonblank_idx`) stay
    empty so layouts that rely on blank spacer tiles (HUD, backgrounds) remain readable."""
    for ty in range(gh):
        for tx in range(gw):
            x, y = tx * 8, ty * 8
            n = ty * gw + tx
            if level >= 3 or (nonblank is not None and n not in nonblank):
                continue
            cv.rect(x, y, 8, 8, base)
            if level <= 1:
                for k in range(8):
                    cv.set(x + 7, y + k, edge); cv.set(x + k, y + 7, edge)
            if level == 0:
                cv.hex2(x, y + 1, n, label)


def draw_unused_or_cut(cv: Canvas, e: dict, level: int):
    word = "UNUSED" if e["decision"] == "unused" else "CUT"
    cv.rect(0, 0, cv.w, cv.h, 1)
    if level >= 3:
        return
    sid = e["id"].replace("_", " ")
    step_x = 64
    for ox in range(0, cv.w, step_x):
        y = 4
        for ly in range(0, cv.h, 32):
            cv.text(ox + 3, ly + y, word, 2)
            cv.text(ox + 3, ly + y + 10, sid, 2)
            if level == 0:
                cv.text(ox + 3, ly + y + 18, f"{e['bpp']}BPP", 2)


def nb(e):
    v = e.get("nonblank_idx")
    return set(v) if v else None


def draw_sprite_sheet(cv, e, level):
    draw_tiles_grid(cv, cv.w // 8, cv.h // 8, level, base=2, edge=1, label=6, nonblank=nb(e))


def draw_bg_sheet(cv, e, level):
    """Dungeon BG tiles. Tile semantics come from the game's own tile-type tables via the inventory
    (`tile_classes`, one letter per tile); tiles of unknown class stay labelled grid tiles.
    f floor (indigo checker), w wall (dark + 1px highlight edge), p pit (near black + rim), s stairs
    (stripes), c chest (amber + C), l liftable (gray blob), h hazard (amber spikes), a water, v conveyor."""
    gw, gh = cv.w // 8, cv.h // 8
    classes = e.get("tile_classes")
    if not classes or level >= 2:
        draw_tiles_grid(cv, gw, gh, level, base=4, edge=5, label=7, nonblank=nb(e))
        return
    for ty in range(gh):
        for tx in range(gw):
            n = ty * gw + tx
            x, y = tx * 8, ty * 8
            if nb(e) is not None and n not in nb(e):
                continue
            c = classes[n % 64] if n < 64 else "?"
            if c == "f":
                for yy in range(8):
                    for xx in range(8):
                        cv.set(x + xx, y + yy, 3 if ((xx // 4) + (yy // 4) + n) % 2 else 2)
            elif c == "w":
                cv.rect(x, y, 8, 8, 4)
                for k in range(8):
                    cv.set(x + k, y, 5); cv.set(x, y + k, 5)
            elif c == "p":
                cv.rect(x, y, 8, 8, 1)
                for k in range(8):
                    cv.set(x + k, y, 4); cv.set(x, y + k, 4)
            elif c == "s":
                cv.rect(x, y, 8, 8, 5)
                for k in (1, 3, 5, 7):
                    cv.rect(x, y + k, 8, 1, 7)
            elif c == "c":
                cv.rect(x, y, 8, 8, 2); cv.rect(x + 1, y + 2, 6, 5, 6); cv.frame(x + 1, y + 2, 6, 5, 1)
            elif c == "l":
                cv.rect(x, y, 8, 8, 2); cv.disc(x + 4, y + 4, 3, 7)
            elif c == "h":
                cv.rect(x, y, 8, 8, 2)
                for k in (1, 5):
                    cv.set(x + k + 1, y + 3, 6); cv.rect(x + k, y + 4, 3, 1, 6); cv.rect(x + k - 1, y + 5, 5, 2, 6)
            elif c == "a":
                cv.rect(x, y, 8, 8, 3)
                for k in range(0, 8, 4):
                    cv.set(x + k, y + 2, 5); cv.set(x + k + 1, y + 3, 5); cv.set(x + k + 2, y + 2, 5)
                    cv.set(x + k + 2, y + 6, 5); cv.set(x + k + 3, y + 7, 5)
            elif c == "v":
                cv.rect(x, y, 8, 8, 3)
                for k in range(4):
                    cv.set(x + 1 + k, y + 3, 7); cv.set(x + 1 + k, y + 4, 7)
                cv.set(x + 5, y + 2, 7); cv.set(x + 5, y + 5, 7); cv.set(x + 6, y + 3, 7); cv.set(x + 6, y + 4, 7)
            else:
                cv.rect(x, y, 8, 8, 4)
                for k in range(8):
                    cv.set(x + 7, y + k, 5); cv.set(x + k, y + 7, 5)
                if level == 0:
                    cv.hex2(x, y + 1, n, 7)


def draw_hud_sheet(cv, e, level):
    draw_tiles_grid(cv, cv.w // 8, cv.h // 8, level, base=3, edge=2, label=1, nonblank=nb(e))


def draw_item_sheet(cv, e, level):
    gw, gh = cv.w // 8, cv.h // 8
    draw_tiles_grid(cv, gw, gh, 3, 0, 0, 0)
    for ty in range(gh):
        for tx in range(gw):
            n = ty * gw + tx
            x, y = tx * 8, ty * 8
            if level >= 3:
                continue
            # violet diagonal stroke with outline; direction alternates so neighbours look different
            if n % 2 == 0:
                cv.line(x, y + 7, x + 7, y, 1, 3); cv.line(x, y + 7, x + 7, y, 7, 1)
            else:
                cv.line(x, y, x + 7, y + 7, 1, 3); cv.line(x, y, x + 7, y + 7, 7, 1)
            if level <= 1:
                cv.frame(x, y, 8, 8, 3)
            if level == 0:
                cv.hex2(x, y + 1, n, 6)


ARROWS = {
    "UP": [".....", "..#..", ".###.", "#.#.#", "..#..", "..#..", "..#.."],
    "DOWN": ["..#..", "..#..", "#.#.#", ".###.", "..#..", ".....", "....."],
    "LEFT": ["..#..", ".#...", "#####", ".#...", "..#..", ".....", "....."],
    "RIGHT": ["..#..", "...#.", "#####", "...#.", "..#..", ".....", "....."],
    "HEART": [".#.#.", "#####", "#####", "#####", ".###.", "..#..", "....."],
    "FACE": ["#####", "#...#", "#.#.#", "#...#", "#.#.#", "#...#", "#####"],
    "DOTS": [".....", ".....", ".....", ".....", ".....", "#.#.#", "....."],
}


def text_code_glyph(code: int):
    """Text code -> (rows or None). Codes verified in vendor/usdasm text.asm message comments and the
    width table of RenderText_PerformVWFing (bank_0E.asm:8700+): $00-19 A-Z, $1A-33 a-z, $34-3D 0-9,
    $3E ! $3F ? $40 - $41 . $42 , $43 ... $44 > $45 ( $46 ) ..., $59 space, $5B-5E button letters A B X Y."""
    if code <= 0x19:
        return GLYPHS[chr(ord("A") + code)]
    if code <= 0x33:
        return GLYPHS[chr(ord("A") + code - 0x1A)]          # uppercase-only font: lowercase codes show capitals
    if code <= 0x3D:
        return GLYPHS[str(code - 0x34)]
    table = {0x3E: GLYPHS["!"], 0x3F: GLYPHS["?"], 0x40: GLYPHS["-"], 0x41: GLYPHS["."], 0x42: GLYPHS[","],
             0x43: ARROWS["DOTS"], 0x44: GLYPHS[">"], 0x45: GLYPHS["("], 0x46: GLYPHS[")"], 0x47: GLYPHS["+"],
             0x48: GLYPHS["="], 0x49: GLYPHS["#"], 0x4A: ARROWS["FACE"], 0x4B: ARROWS["FACE"], 0x4C: GLYPHS['"'],
             0x4D: ARROWS["UP"], 0x4E: ARROWS["DOWN"], 0x4F: ARROWS["LEFT"], 0x50: ARROWS["RIGHT"], 0x51: GLYPHS["'"],
             0x52: ARROWS["HEART"], 0x53: ARROWS["HEART"], 0x54: ARROWS["HEART"], 0x55: ARROWS["HEART"],
             0x56: ARROWS["HEART"], 0x57: ARROWS["HEART"], 0x58: ARROWS["HEART"],
             0x5A: GLYPHS["<"], 0x5B: GLYPHS["A"], 0x5C: GLYPHS["B"], 0x5D: GLYPHS["X"], 0x5E: GLYPHS["Y"],
             0x5F: GLYPHS["I"], 0x60: GLYPHS["I"], 0x61: GLYPHS["!"]}
    return table.get(code)


def draw_font_sheet(cv, e, level):
    """TheFont layout (bank_0E.asm:8630-8700): glyph for text code c is an 8x16 cell: top tile
    ((c & $F0) << 1) | (c & $0F), bottom tile +$10. The renderer advances `glyph_widths[c]` pixels and
    drops columns beyond it, so glyphs are cropped to that width."""
    widths = e.get("glyph_widths", [])
    gw = cv.w // 8
    for code in range(0x63):
        g = text_code_glyph(code)
        if g is None:
            continue
        top = ((code & 0xF0) << 1) | (code & 0x0F)
        tx, ty = top % gw, top // gw
        w = widths[code] if code < len(widths) else 6
        start = max(0, (5 - min(w, 5)) // 2)
        for ry, row in enumerate(g):
            for rx in range(min(w, 5)):
                if row[start + rx] == "#":
                    cv.rect(tx * 8 + rx, ty * 8 + 1 + ry * 2, 1, 2, 1)


def draw_link_sheet(cv, e, level):
    gw = cv.w // 8
    frames = e.get("frames", [])
    if level >= 3:
        return
    for i, f in enumerate(frames):
        c, r = f["tile"] % gw, f["tile"] // gw
        x, y = c * 8, r * 8
        if f["part"] == "head":
            cv.disc(x + 8, y + 8, 6, 1); cv.disc(x + 8, y + 8, 5, 3)
            cv.rect(x + 7, y + 10, 3, 3, 6)               # light face dot
        elif f["part"] == "body":
            shift = (i % 3) - 1
            for k in range(14):                             # cloak triangle
                cv.rect(x + 8 - k // 2, y + 1 + k, k + 1 if k < 8 else 8, 1, 3)
            cv.rect(x + 3 + shift, y + 12, 3, 4, 2); cv.rect(x + 10 - shift, y + 12, 3, 4, 2)  # limb shift
            cv.frame(x, y, 16, 16, 13)
        else:
            cv.rect(x + 2, y + 2, 12, 12, 9); cv.frame(x + 1, y + 1, 14, 14, 1)
        if level == 0:
            cv.hex2(x, y, f["tile"] & 0xFF, 6 if f["part"] != "head" else 1)


def draw_title_sheet(cv, e, level):
    """GFX_40/41/39: HUSH logo + PRESS START cells (tools/gfx_title.py); every other tile blank."""
    gw = cv.w // 8
    for idx, pix in gfx_title.sheet_tiles(int(e["id"][4:], 16)).items():
        tx, ty = idx % gw, idx // gw
        for y in range(8):
            for x in range(8):
                cv.set(tx * 8 + x, ty * 8 + y, pix[y][x])


STYLE_DRAW = dict(title=draw_title_sheet, sprite=draw_sprite_sheet, bg=draw_bg_sheet, hud=draw_hud_sheet, item=draw_item_sheet,
                  font=draw_font_sheet, link=draw_link_sheet, unused=draw_unused_or_cut, cut=draw_unused_or_cut)


def style_family(e):
    st = e["style"]
    if st in ("unused", "cut"):
        return "cut", "debug"
    return dict(title=("title", "ui"), sprite=("spr", "env"), bg=("bg", "env"), hud=("hud", "ui"), item=("spr", "player"),
                font=("hud", "ui"), link=("link", "player")).get(st, ("spr", "env"))


def render(e: dict, level: int):
    gw, gh = e["grid_tiles"]
    cv = Canvas(gw, gh)
    STYLE_DRAW[e["style"]](cv, e, level)
    if e["bpp"] == 3 and not e.get("compressed"):
        # GFX_73..GFX_7E are stored uncompressed, but InitializeTilesets also runs the DECOMPRESSOR on
        # some of them (e.g. the title/intro sprite set $7D -> GFX_7B, bank_00.asm:11076 AA3 row $7D +
        # LoadSpriteGraphics). A stream that does not start with $FF can run away and overwrite WRAM
        # (it wiped the intro palettes). Plane 0 of tile 0 row 0 is the first byte: colour 1 across the
        # whole row makes it $FF = "end of stream" immediately, and is harmless as a drawn pixel row.
        for x in range(8):
            cv.px[0][x] = 1
    return cv


def fits(e, cv) -> int | None:
    bpp = e["bpp"]
    data = encode(cv.px, bpp)
    if not e.get("compressed"):
        return len(data)
    return len(compress(data))


# ---- new assets (not vanilla slots): guard, awareness icons, tools ------------------------------------
def new_guard():
    cv = Canvas(16, 4)
    names = []
    for i in range(16):
        x, y = (i % 8) * 16, (i // 8) * 16
        alert = i >= 8
        face = ["down", "down", "up", "up", "left", "left", "sleep", "down-out"][i % 8]
        names.append(f"{'alert' if alert else 'unaware'} {face} {1 + (i % 2)}")
        body = 5 if alert else 2
        cv.rect(x + 3, y + 5, 10, 9, body); cv.frame(x + 3, y + 5, 10, 9, 1)         # coat block
        cv.disc(x + 8, y + 4, 3, 4 if not alert else 5); cv.frame(x + 5, y + 1, 7, 7, 1)
        step = 1 if i % 2 else 0
        cv.rect(x + 4, y + 14, 3, 2 - step, 1); cv.rect(x + 9, y + 14, 3, 1 + step, 1)  # legs
        lx = x + 12 if face != "left" else x + 1
        cv.rect(lx, y + 8, 3, 3, 1); cv.rect(lx + 1 if not alert else lx, y + 8 if not alert else y + 7, 2 if not alert else 3, 2 if not alert else 5, 5)  # lantern
        if face in ("down", "down-out"):
            cv.rect(x + 7, y + 3, 2, 2, 6)
        elif face == "left":
            cv.rect(x + 5, y + 3, 2, 2, 6)
        if face == "sleep":
            cv.text(x + 4, y + 7, "Z", 6)
        if alert:
            cv.rect(x + 2, y + 15, 12, 1, 5)
        # facing arrow
        ax, ay = {"down": (x + 8, y + 15), "up": (x + 8, y), "left": (x, y + 9)}.get(face, (x + 8, y + 15))
        cv.set(ax, ay, 6)
    return cv, names


def new_icons():
    cv = Canvas(16, 4)
    names = ["? small", "! small", "Z small", "z small", "z tiny", "(spare)", "(spare)", "(spare)"]
    cv.glyph(1, 0, "?", 5); cv.glyph(9, 0, "!", 5); cv.glyph(17, 0, "Z", 6); cv.glyph(25, 1, "Z", 6)
    cv.glyph(33, 2, "Z", 6)
    big = [("?", 5), ("!", 5), ("Z", 6)]
    for i, (g, c) in enumerate(big):
        cv.glyph(i * 16 + 3, 17, g, c, 2)
        cv.frame(i * 16, 16, 16, 16, 2)
    names += ["? big (16x16)", "! big (16x16)", "Zzz big (16x16)"]
    cv.frame(0, 0, 8, 8, 2)
    return cv, names


def new_tools():
    cv = Canvas(16, 4)
    names = []
    for i in range(4):                               # slash arc frames, growing sweep
        x, y = i * 16, 0
        for k in range(2 + 3 * i):
            cv.disc(x + 3 + k, y + 13 - (k * k) // 8 - k // 2, 1, 7)
        names.append(f"shade knife slash arc {i + 1}/4 (frame {i + 1} is the wind-up)" if i == 0 else f"shade knife slash arc {i + 1}/4")
    cv.line(70, 8, 90, 8, 7, 1); cv.rect(88, 6, 3, 5, 7); names.append("hush dart horizontal")
    cv.line(104, 2, 104, 14, 7, 1); cv.rect(102, 2, 5, 3, 7); names.append("hush dart vertical")
    cv.disc(120, 8, 3, 7); names.append("hush dart in flight (small)")
    # ink pot + cloud frames
    cv.disc(8, 24, 5, 7); cv.frame(4, 17, 9, 3, 2); names.append("ink pot")
    for i in range(4):
        cv.disc(24 + i * 16, 24, 3 + 2 * i, 3 if i % 2 == 0 else 2)
        cv.frame(16 + i * 16, 16, 16, 16, 1) if False else None
        names.append(f"ink cloud {i + 1}/4")
    while len(names) < 16:
        names.append("(spare)")
    return cv, names


NEW_ASSETS = [
    dict(id="NEW_guard", kind="new", style="guard", role="danger", family="spr", bpp=3, prio="P0", build=new_guard,
         notes="Lantern guard: coat block, light dot for the face, amber lantern. Rows: unaware (top) / alert (bottom, amber fill). "
               "Right-facing = horizontal flip of left. Target slot: TBD at M1 (reuse an underworld sprite sheet slot; see inventory).",
         where=["every guard room"]),
    dict(id="NEW_awareness_icons", kind="new", style="icons", role="danger", family="spr", bpp=3, prio="P0", build=new_icons,
         notes="Awareness glyphs: ? suspicious, ! alert (amber), Zzz asleep (light). Small 8x8 and big 16x16 variants. Target slot: TBD at M1.",
         where=["above a guard's head"]),
    dict(id="NEW_tools", kind="new", style="tools", role="player", family="spr", bpp=3, prio="P0", build=new_tools,
         notes="Violet tool effects: Shade Knife slash arc (4 frames), Hush Dart (3), Ink Pot + ink cloud (4 frames). "
               "Vanilla slots they replace: see D1/D2/C7 reuse-as entries in the inventory.",
         where=["when the player uses a tool"]),
]


# ---- writers --------------------------------------------------------------------------------------
def save_png(path: Path, cv: Canvas, pal):
    img = Image.new("P", (cv.w, cv.h))
    flat = []
    for r, g, b in pal:
        flat += [r, g, b]
    img.putpalette(flat)
    img.putdata([v for row in cv.px for v in row])
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, transparency=0, optimize=False)


def save_guide(path: Path, cv: Canvas, pal, e: dict, fam: str, frames=None):
    S = 4
    tw, th = cv.w * S, cv.h * S
    head, foot = 70, 150 if fam == "link" else 110
    img = Image.new("RGB", (max(tw + 20, 640), th + head + foot + 20), (20, 18, 40))
    d = ImageDraw.Draw(img)
    # checkerboard behind transparent pixels
    ox, oy = 10, head
    for y in range(0, th, 16):
        for x in range(0, tw, 16):
            d.rectangle([ox + x, oy + y, ox + x + 15, oy + y + 15], fill=(34, 32, 60) if ((x + y) // 16) % 2 else (28, 26, 52))
    px = img.load()
    for y in range(cv.h):
        for x in range(cv.w):
            v = cv.px[y][x]
            if v:
                c = tuple(pal[v])
                for dy in range(S):
                    for dx in range(S):
                        px[ox + x * S + dx, oy + y * S + dy] = c
    for tx in range(0, cv.w // 8 + 1):
        d.line([ox + tx * 8 * S, oy, ox + tx * 8 * S, oy + th], fill=(90, 86, 150), width=1)
    for ty in range(0, cv.h // 8 + 1):
        d.line([ox, oy + ty * 8 * S, ox + tw, oy + ty * 8 * S], fill=(90, 86, 150), width=1)
    gw = cv.w // 8
    for n in range((cv.w // 8) * (cv.h // 8)):
        d.text((ox + (n % gw) * 8 * S + 2, oy + (n // gw) * 8 * S + 2), f"{n:02X}", fill=(255, 255, 255) if n % 2 == 0 else (200, 200, 255))
    for f in frames or []:
        d.rectangle([ox + f["x"] * S, oy + f["y"] * S, ox + (f["x"] + f["w"]) * S - 1, oy + (f["y"] + f["h"]) * S - 1], outline=(255, 220, 100))
        d.text((ox + f["x"] * S + 2, oy + (f["y"] + f["h"]) * S - 12), f["label"][:14], fill=(255, 220, 100))
    d.text((10, 8), f"{e['id']}  kind={e.get('kind')}  decision={e.get('decision', 'new')}  prio={e.get('priority', e.get('prio'))}", fill=(255, 255, 255))
    d.text((10, 24), f"{cv.w}x{cv.h}px = {cv.w // 8}x{cv.h // 8} tiles, {e['bpp']}bpp, role {e.get('role')}; guide scaled {S}x, tile index in hex at each tile corner", fill=(200, 200, 230))
    d.text((10, 40), (e.get("notes") or "")[:110], fill=(180, 180, 210))
    y0 = oy + th + 14
    d.text((10, y0), "PALETTE (index: colour - role)", fill=(255, 255, 255))
    cols = FAMILIES[fam]["colours"]
    for i in range(1, min(len(pal), 8)):
        x = 10 + (i - 1) * 90
        d.rectangle([x, y0 + 16, x + 30, y0 + 34], fill=tuple(pal[i]), outline=(255, 255, 255))
        d.text((x + 34, y0 + 16), str(i), fill=(255, 255, 255))
        d.text((x, y0 + 38), (cols[i][1] if i in cols else "")[:14], fill=(180, 180, 210))
    img.save(path, optimize=True)


def brief(e: dict, fam: str, role: str, level: int, size: int, frames_desc):
    gw, gh = e["grid_tiles"]
    b = dict(id=e["id"], kind=e["kind"], role=role, decision=e["decision"], priority=e["priority"],
             what_it_is=e.get("notes", ""), reuse_as=e.get("reuse_as"),
             where_it_appears=e.get("where_in_vanilla", []),
             bpp=e["bpp"], size_tiles=[gw, gh], size_px=[gw * 8, gh * 8], tile_order="row-major, 16 tiles per row",
             palette=dict(family=fam, note=FAMILIES[fam]["role_note"],
                          indices={i: f"#{c} {t}" for i, (c, t) in FAMILIES[fam]["colours"].items() if i < (1 << e["bpp"])}),
             slot=dict(rom=e.get("rom"), compressed=e.get("compressed"), capacity_bytes=e.get("capacity_bytes")),
             insert=bool(e.get("insert", True)),
             fit=dict(level=level, placeholder_bytes=size,
                      level_meaning="0 labelled tiles, 1 bordered tiles, 2 flat, 3 empty"),
             frames=frames_desc,
             placeholder_notice="PLACEHOLDER generated by tools/gfx_placeholder.py. Replace the pixels; keep size, grid and palette.")
    return b


def main() -> int:
    if not INV.exists():
        print("run tools/gfx_inventory.py first", file=sys.stderr)
        return 1
    inv = yaml.safe_load(INV.read_text())
    GUIDES.mkdir(parents=True, exist_ok=True)
    written, rows = 0, []
    fall = []
    for e in inv["assets"]:
        if e["id"] == "WORLDMAP":
            e = dict(e)
        fam, role = style_family(e)
        blank_unused = e["decision"] == "unused" and e.get("capacity_bytes", 99) < 64
        e["insert"] = not blank_unused
        if e["id"] == "WORLDMAP":
            e["style"] = "cut"; e["bpp"] = 8
        bpp = e["bpp"]
        level, size, cv = 0, 0, None
        for level in range(4):
            cv = render(e, level)
            if e["bpp"] == 8:
                size = len(encode(cv.px, 8)); break
            size = fits(e, cv)
            cap = e.get("capacity_bytes") if e.get("compressed") else None
            if cap is None or size <= cap or blank_unused:
                break
        cap = e.get("capacity_bytes")
        if e.get("compressed") and size > cap and not blank_unused:
            fall.append(f"{e['id']}: does not fit ({size} > {cap})")
        if level > 0:
            fall.append(f"{e['id']}: level {level} (size {size}/{cap})")
        n = (1 << bpp) if bpp < 8 else 16
        pal = family_palette(fam, min(n, 16)) if fam != "link" else [(0, 0, 0)] + [hexrgb(FAMILIES["link"]["colours"][i][0]) for i in range(1, 16)]
        if bpp == 3 and len(pal) < 8:
            pal += [(0, 0, 0)] * (8 - len(pal))
        if bpp == 2:
            pal = pal[:4] + [(0, 0, 0)] * (4 - len(pal[:4]))
        kdir = SRC / e["kind"]
        png = kdir / f"{e['id']}.png"
        save_png(png, cv, pal if bpp != 8 else pal + [(0, 0, 0)] * 0)
        frames_desc, frames_box = [], []
        if e["style"] == "link":
            gw = e["grid_tiles"][0]
            for i, f in enumerate(e.get("frames", [])):
                c, r = f["tile"] % gw, f["tile"] // gw
                frames_desc.append(dict(name=f"{f['part']} block @tile {f['tile']:#04x} (col {c}, row {r})",
                                        rect_px=[c * 8, r * 8, 16, 16], anim_indices=[f"0x{a:03X}" for a in f["anims"][:6]]))
                frames_box.append(dict(x=c * 8, y=r * 8, w=16, h=16, label=f"{f['part'][0]}{f['tile']:X}"))
        b = brief(e, fam, role, level, size, frames_desc)
        (kdir / f"{e['id']}.yaml").write_text(yaml.safe_dump(b, sort_keys=False, width=110))
        save_guide(GUIDES / f"{e['id']}_guide.png", cv, pal, e | dict(role=role), fam, frames_box)
        rows.append((e, role, level, size, b))
        written += 1
    for na in NEW_ASSETS:
        cv, names = na["build"]()
        fam, role = na["family"], na["role"]
        pal = family_palette(fam, 8)
        png = SRC / "new" / f"{na['id']}.png"
        save_png(png, cv, pal)
        frames_desc, boxes = [], []
        for i, nm in enumerate(names):
            if na["style"] == "icons" and i < 5:
                r = [i * 8, 0, 8, 8]
            elif na["style"] == "icons" and i >= 8:
                r = [(i - 8) * 16, 16, 16, 16]
            elif na["style"] == "icons":
                continue
            else:
                r = [(i % 8) * 16, (i // 8) * 16, 16, 16]
            frames_desc.append(dict(name=nm, rect_px=r, index=i))
            boxes.append(dict(x=r[0], y=r[1], w=r[2], h=r[3], label=str(i)))
        e = dict(id=na["id"], kind="new", decision="redraw", priority=na["prio"], notes=na["notes"], bpp=3,
                 where_in_vanilla=na["where"], grid_tiles=[16, 4], rom=None, compressed=True, capacity_bytes=None,
                 role=role, insert=False)
        b = brief(e, fam, role, 0, len(encode(cv.px, 3)), frames_desc)
        b["slot"] = dict(rom="TBD at M1 (not inserted by A0)", compressed=True, capacity_bytes=None)
        (SRC / "new" / f"{na['id']}.yaml").write_text(yaml.safe_dump(b, sort_keys=False, width=110))
        save_guide(GUIDES / f"{na['id']}_guide.png", cv, pal, e, fam, boxes)
        rows.append((e, role, 0, 0, b))
        written += 1
    write_palettes(inv)
    write_gallery(rows, inv)
    print(f"placeholders: {written} sheets, guides, briefs; palettes yaml; gallery -> {GALLERY.relative_to(ROOT)}")
    for f in fall:
        print("  fit:", f)
    return 0


# ---- palettes ---------------------------------------------------------------------------------------
def bgr(rgb):
    r, g, b = rgb
    return (b >> 3 << 10) | (g >> 3 << 5) | (r >> 3)


def pal_rows_for(p: dict):
    """Colour rows for an inventory palette group, honouring each ROM row's width."""
    fam = p["family"]
    pid = p["id"]
    dec = p["decision"]
    rows = []
    for n in p.get("rows", []):
        if dec in ("cut", "unused") or pid.startswith("pal_shield"):
            cols = [FAMILIES["cut"]["colours"][1 + k % 7][0] for k in range(n)]
        elif pid.startswith("pal_link") or pid.startswith("pal_Palettes_"):
            L = FAMILIES["link"]["colours"]
            cols = [L[1 + k][0] for k in range(7)] if n == 7 else [L[8 + k][0] for k in range(8)]
        elif pid.startswith("pal_sword"):
            cols = [("A878F0", "C9ABFF", "4B2E8C", "ECE8FF")[k % 4] for k in range(n)]
        elif pid.startswith("pal_hud"):
            cols = ["000000", "ECE8FF", "6C66C8", "14123A"][:n]
        elif p["family"] == "title":
            T = FAMILIES["title"]["colours"]
            cols = [T[1 + k][0] for k in range(7)]
        elif pid.startswith("pal_dungeon"):
            B = FAMILIES["bg"]["colours"]
            cols = [B[1 + k][0] for k in range(7)] if n == 7 else ["8A88A0"] + [B[1 + k][0] for k in range(7)]
        else:
            S = FAMILIES["spr"]["colours"]
            cols = [S[1 + k][0] for k in range(7)] if n == 7 else ["ECE8FF"] + [S[1 + k][0] for k in range(7)]
        rows.append(cols[:n] + [cols[-1]] * max(0, n - len(cols)))
    return rows


def write_palettes(inv):
    out = SRC / "palettes"
    out.mkdir(parents=True, exist_ok=True)
    files = {"title": {}, "link": {}, "sprites": {}, "bg_dungeon": {}, "hud": {}, "sword": {}, "cut_unused": {}}
    for p in inv["palettes"]:
        pid = p["id"]
        if "rows" not in p:                           # map/triforce/flash tables: magenta, 16-byte rows or 14
            nbytes = p["bytes"]
            w = 14 if nbytes % 14 == 0 and nbytes != 16 else 16
            rows = [[FAMILIES["cut"]["colours"][1 + k % 7][0] for k in range(w // 2)] for _ in range(nbytes // w)]
            addrs = [f"${int(p['rom'][1:], 16) + w * i:06X}" for i in range(len(rows))]
            files["cut_unused"][pid] = dict(decision=p["decision"], rom_rows=addrs, colours=rows)
            continue
        rows = pal_rows_for(p)
        if p["family"] == "title":
            key = "title"
        elif p["decision"] in ("cut", "unused") or pid.startswith("pal_shield"):
            key = "cut_unused"
        elif pid.startswith(("pal_link", "pal_Palettes_")):
            key = "link"
        elif pid.startswith("pal_sword"):
            key = "sword"
        elif pid.startswith("pal_hud"):
            key = "hud"
        elif pid.startswith("pal_dungeon"):
            key = "bg_dungeon"
        else:
            key = "sprites"
        files[key][pid] = dict(decision=p["decision"], rom_rows=p["row_addrs"], colours=rows)
    notes = dict(
        title="Title screen palettes (the intro loads these overworld palette slots). Every row is the same: index meanings in gfx/src/title/*.yaml.",
        link="Link/player palettes (15 colours = 7 + 8 per palette; index meanings in gfx/src/player/LINK.yaml). Violet only.",
        sprites="Universal HUSH sprite palette (index meanings in any gfx/src/sprite/*.yaml). 8-colour rows repeat 1-7 as colours 9-15.",
        bg_dungeon="Underworld room palettes: universal HUSH background palette (indigo walls/floors, amber light).",
        hud="HUD / menu / text 2bpp palettes: [black, light, mid, dark].",
        sword="Shade Knife blade colours (violet).",
        cut_unused="Magenta: palettes for scenes HUSH cuts or never shows. If one appears on screen it is a bug.")
    for key, groups in files.items():
        doc = dict(note=notes[key] + " Colours are RGB hex; the build converts to BGR555.", groups=groups)
        (out / f"{key}.yaml").write_text(yaml.safe_dump(doc, sort_keys=False, width=140, default_flow_style=None))


# ---- gallery ---------------------------------------------------------------------------------------
def write_gallery(rows, inv):
    GALLERY.parent.mkdir(parents=True, exist_ok=True)
    out = ["<!doctype html><meta charset=utf-8><title>HUSH placeholder gallery</title>",
           "<style>body{background:#141230;color:#e6e1ff;font:14px sans-serif;margin:20px}h1,h2,h3{color:#f2a93b}"
           ".card{display:inline-block;vertical-align:top;margin:8px;padding:8px;background:#1d1a40;border:1px solid #38327a;max-width:680px}"
           "img{image-rendering:pixelated;max-width:660px}code{color:#a878f0}small{color:#9a94d9}</style>",
           "<h1>HUSH placeholder gallery (A0)</h1>",
           "<p>Every placeholder next to its drawing brief. These are PLACEHOLDERS: ugly on purpose. Grouped by priority, then kind. "
           "Image paths are relative: open this file from the repo checkout (build/gfx_gallery.html).</p>"]
    for prio in ("P0", "P1", "P2"):
        sel = [r for r in rows if (r[0].get("priority") or r[0].get("prio")) == prio]
        if not sel:
            continue
        out.append(f"<h2>{prio} ({len(sel)})</h2>")
        for kind in sorted({r[0]["kind"] for r in sel}):
            ks = [r for r in sel if r[0]["kind"] == kind]
            out.append(f"<h3>{kind} ({len(ks)})</h3>")
            for e, role, level, size, b in ks:
                nid = e["id"]
                out.append(f"<div class=card><b>{html.escape(nid)}</b> <small>{e.get('decision')} · {e['bpp']}bpp · role {role} · "
                           f"fit level {level} · {size} B{' / cap ' + str(e.get('capacity_bytes')) if e.get('capacity_bytes') else ''}</small><br>"
                           f"<img src='../gfx/guides/{nid}_guide.png' loading=lazy><br>"
                           f"<small>{html.escape((e.get('reuse_as') or e.get('notes') or '')[:240])}</small><br>"
                           f"<small>where: {html.escape('; '.join(e.get('where_in_vanilla', [])[:3]))}</small><br>"
                           f"<small>brief: <code>gfx/src/{e['kind']}/{nid}.yaml</code></small></div>")
    out.append("<h2>Palettes</h2><p>See <code>gfx/src/palettes/*.yaml</code>. Universal index meanings:</p><ul>")
    for k, f in FAMILIES.items():
        out.append(f"<li><b>{k}</b>: {html.escape(f['role_note'])}<br>" + "".join(
            f"<span style='display:inline-block;background:#{c};width:14px;height:14px;border:1px solid #fff;vertical-align:middle'></span> {i} {html.escape(t)} &nbsp; "
            for i, (c, t) in f["colours"].items()) + "</li>")
    out.append("</ul>")
    GALLERY.write_text("\n".join(out))


# ---- stealth meter cells (design/pillars.md "Stealth meter", HUD part) ------------------------------
# PLACEHOLDER-quality but ORIGINAL: two 8x8 2bpp cells drawn from the ASCII below, nothing read from vanilla.
# They overwrite the old heart cells in GFX_DE (docs/gfx/hud_map.md section 3), because the engine already
# points the hearts row at these tile ids:  $A0 (DE idx 32) = filled cell,  $A2 (DE idx 34) = drained cell.
# Index meaning (same in both palette groups, so only the palette bits change the colour):
#   1 = glint (light), 2 = cell colour (violet in pal_hud_01, amber in pal_hud_05), 3 = dark interior.
# Filled vs drained differ by SHAPE (solid block vs hollow frame), not colour alone.
# 6x6 block inside an 8x8 cell, 1 px clear border -> 2 px gap between neighbouring cells, so cells can be counted.
METER_CELLS = {
    32: ["........",   # $A0 filled: solid cell, glint top-left
         ".222222.",
         ".211222.",
         ".212222.",
         ".222222.",
         ".222222.",
         ".222222.",
         "........"],
    34: ["........",   # $A2 drained: empty container, cell-colour outline, dark interior
         ".222222.",
         ".233332.",
         ".233332.",
         ".233332.",
         ".233332.",
         ".222222.",
         "........"],
}


# ---- meter label (replaces "LIFE" in the same two cells: $AB = DE 43, $AC = DE 44; tilemap unchanged) --------
# PLACEHOLDER-quality but ORIGINAL. "HUSH": 4 letters of 3x6 px with a 1 px gap = 15 px, + 1 px shadow = 16 px.
# Letters on rows 1-6 (centre 3.5 = the centre of the ornament line $8B/$8F on rows 3-4), shadow down-right on rows 2-7.
# Indices: 2 = violet (pal_hud_01 A878F0, "violet = you"), 3 = dark shadow (PANEL 1A2456). No amber.
LABEL_TEXT = "HUSH"
LABEL_GLYPHS = {
    "H": ["#.#", "#.#", "###", "#.#", "#.#", "#.#"],
    "U": ["#.#", "#.#", "#.#", "#.#", "#.#", "###"],
    "S": ["###", "#..", "###", "..#", "..#", "###"],
}


def meter_label() -> list[str]:
    """16x8 label, glyph ink 2 over a 1 px down-right shadow 3"""
    grid = [["."] * 16 for _ in range(8)]
    for ink, dx, dy in (("3", 1, 1), ("2", 0, 0)):
        for i, ch in enumerate(LABEL_TEXT):
            for y, r in enumerate(LABEL_GLYPHS[ch]):
                for x, c in enumerate(r):
                    if c == "#":
                        grid[1 + y + dy][i * 4 + x + dx] = ink
    return ["".join(r) for r in grid]


def hud_cells() -> dict[int, list[str]]:
    """GFX_DE cell idx -> 8 ASCII rows, for every cell this generator owns"""
    lab = meter_label()
    cells = dict(METER_CELLS)
    cells[43] = [r[0:8] for r in lab]   # $AB
    cells[44] = [r[8:16] for r in lab]  # $AC
    return cells


def label_preview(out: Path, zoom: int = 8) -> None:
    """zoomed preview of ornaments + label + 8 meter cells in pal_hud_01/02 colours on the room-dark backdrop"""
    p1 = [None, (0xE8, 0xE8, 0xF8), (0xA8, 0x78, 0xF0), (0x1A, 0x24, 0x56)]
    p2 = [None, (0x80, 0xD8, 0xD0), (0x30, 0x80, 0x88), (0x0A, 0x10, 0x28)]
    im = Image.open(SRC / "hud" / "GFX_DE.png")
    src = im.load()
    canvas = Image.new("RGB", (8 * 8, 16), (0x14, 0x12, 0x3A))
    c = canvas.load()

    def put(idx, pal, cx, cy, hflip=False):
        ox, oy = (idx % 16) * 8, (idx // 16) * 8
        for y in range(8):
            for x in range(8):
                v = src[ox + (7 - x if hflip else x), oy + y]
                if v:
                    c[cx * 8 + x, cy * 8 + y] = pal[v]
    # row 2 of the HUD, cols 22-27: $8B $8F $AB $AC $8F(H) $8B(H)
    for col, (idx, pal, h) in enumerate([(11, p2, False), (15, p2, False), (43, p1, False), (44, p1, False),
                                         (15, p2, True), (11, p2, True)]):
        put(idx, pal, col + 1, 0, h)
    for col in range(8):  # row 3: 5 filled + 3 drained meter cells
        put(32 if col < 5 else 34, p1, col, 1)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((canvas.width * zoom, canvas.height * zoom), Image.NEAREST).save(out)
    print(f"preview: {out.relative_to(ROOT)}")


def hud_meter(check: bool = False, preview: bool = False) -> int:
    """Patch the meter cells (DE 32, 34) and the meter label (DE 43, 44) into gfx/src/hud/GFX_DE.png.
    No other cell and no palette change. Prints every 8x8 cell whose pixels differ from the file before the write.
    --check: write nothing, exit 1 if the sheet differs from these definitions."""
    import gfx_convert
    path = SRC / "hud" / "GFX_DE.png"
    im = Image.open(path)
    assert im.mode == "P" and im.size == (128, 64), (im.mode, im.size)
    before = im.copy().load()
    px = im.load()
    for idx, rows in hud_cells().items():
        assert len(rows) == 8 and all(len(r) == 8 for r in rows), idx
        ox, oy = (idx % 16) * 8, (idx // 16) * 8
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                px[ox + x, oy + y] = 0 if ch == "." else int(ch)
    changed = [i for i in range(128)
               if any(before[(i % 16) * 8 + x, (i // 16) * 8 + y] != px[(i % 16) * 8 + x, (i // 16) * 8 + y]
                      for y in range(8) for x in range(8))]
    print(f"GFX_DE cells changed vs file on disk: {changed if changed else 'none'}")
    if check:
        return 1 if changed else 0
    if changed:
        im.save(path, transparency=0)
    if preview:
        label_preview(ROOT / "build" / "art_preview" / "hud_label.png")
    errors: list[str] = []
    warnings: list[str] = []
    data = gfx_convert.process(path, False, errors, warnings)
    for e in errors:
        print("ERROR", e)
    if data is None:
        return 1
    cap = yaml.safe_load((SRC / "hud" / "GFX_DE.yaml").read_text())["slot"]["capacity_bytes"]
    size = len(compress(data))
    print(f"GFX_DE: meter cells DE 32 ($A0 filled), DE 34 ($A2 drained), label '{LABEL_TEXT}' DE 43-44 ($AB $AC); "
          f"{len(data)} B raw, {size} B compressed / slot {cap} B -> {'fits' if size <= cap else 'DOES NOT FIT'}")
    return 0 if size <= cap else 1


if __name__ == "__main__":
    if sys.argv[1:2] == ["hud-meter"]:
        sys.exit(hud_meter(check="--check" in sys.argv, preview="--preview" in sys.argv))
    sys.exit(main())
