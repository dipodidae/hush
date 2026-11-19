"""Shared helpers for the cast-art painters (tools/art/cast_*.py): ASCII pixel blocks -> indexed gfx/src PNGs.

Original pixel art only: every block below is drawn by hand as text (digits = palette index, '.' = transparent).
Nothing is read from or derived from vanilla graphics.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "gfx" / "src"


def hex2rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def snap(h: str) -> str:
    """BGR555-exact colour (low 3 bits cleared), as hex."""
    r, g, b = hex2rgb(h)
    return "%02X%02X%02X" % (r & 0xF8, g & 0xF8, b & 0xF8)


def mirror(rows: list[str]) -> list[str]:
    """Rows are the LEFT half (8 chars) of a symmetric 16-wide block; returns full 16-char rows."""
    return [r + r[::-1] for r in rows]


def pad(rows: list[str], w: int, h: int) -> list[str]:
    rows = [r.ljust(w, ".") for r in rows]
    return rows + ["." * w] * (h - len(rows))


def hflip(rows: list[str]) -> list[str]:
    return [r[::-1] for r in rows]


def vflip(rows: list[str]) -> list[str]:
    return rows[::-1]


def check(rows: list[str], w: int, h: int, name: str) -> list[str]:
    assert len(rows) == h, f"{name}: {len(rows)} rows, want {h}"
    for i, r in enumerate(rows):
        assert len(r) == w, f"{name}: row {i} is {len(r)} wide, want {w}: {r!r}"
    return rows


class Sheet:
    """An indexed (mode P) gfx/src sheet to paint into; keeps its palette unless set_palette is called."""

    def __init__(self, path: str | Path):
        self.path = Path(path) if Path(path).is_absolute() else SRC / path
        self.im = Image.open(self.path)
        assert self.im.mode == "P", self.path
        self.px = self.im.load()
        self.w, self.h = self.im.size

    def set_palette(self, hexes: list[str]):
        """hexes[i] = colour of index i+1 (index 0 stays black/transparent); unspecified indices keep their entry."""
        flat = list(self.im.getpalette())
        flat += [0] * (768 - len(flat))
        for i, h in enumerate(hexes, start=1):
            flat[i * 3:i * 3 + 3] = hex2rgb(h)
        self.im.putpalette(flat)

    def clear(self, x0, y0, w, h):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.px[x, y] = 0

    def put(self, x0: int, y0: int, rows: list[str], clear: bool = True):
        """Write ASCII rows with top-left at (x0, y0); '.' = 0 (transparent); digits/letters = index (0-9, a-f hex)."""
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                v = 0 if ch == "." else int(ch, 16)
                if v == 0 and not clear:
                    continue
                self.px[x0 + i, y0 + j] = v

    def save(self):
        self.im.save(self.path, transparency=0)


def outline(rows: list[str], fill: set[str], edge: str = "1", diag: bool = True) -> list[str]:
    """Add a 1-px outline (index `edge`) around every pixel whose index is in `fill` (8-neighbourhood if diag)."""
    h, w = len(rows), len(rows[0])
    out = [list(r) for r in rows]
    for y in range(h):
        for x in range(w):
            if rows[y][x] != ".":
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if (dx or dy) and (diag or not (dx and dy)):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w and rows[yy][xx] in fill:
                            out[y][x] = edge
    return ["".join(r) for r in out]


def render_preview(sheet: Sheet, rect, pal_hex: list[str], zoom: int, bg=(52, 52, 62)) -> Image.Image:
    """Render a rectangle of a sheet with an arbitrary palette (pal_hex[i-1] = colour of index i), on a flat backdrop."""
    x0, y0, w, h = rect
    im = Image.new("RGB", (w * zoom, h * zoom), bg)
    for y in range(h):
        for x in range(w):
            v = sheet.px[x0 + x, y0 + y]
            if v:
                c = hex2rgb(pal_hex[v - 1])
                for dy in range(zoom):
                    for dx in range(zoom):
                        im.putpixel((x * zoom + dx, y * zoom + dy), c)
    return im
