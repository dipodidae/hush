"""Tile helpers for the art-map research tools: sheets from gfx/src PNGs, VRAM tile decode, expansion rules (research helper)."""
from __future__ import annotations
import os, sys, glob, warnings
from pathlib import Path
warnings.filterwarnings("ignore")
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from gfxlib import decode_tile  # noqa: E402
from PIL import Image  # noqa: E402

def sheet_png(name: str) -> Path | None:
    hits = glob.glob(str(ROOT / "gfx" / "src" / "**" / f"{name}.png"), recursive=True)
    return Path(hits[0]) if hits else None

def load_tiles(path) -> list[tuple]:
    im = Image.open(path)
    assert im.mode == "P", path
    w, h = im.size
    px = list(im.getdata())
    return [tuple(px[(ty * 8 + y) * w + tx * 8 + x] for y in range(8) for x in range(8))
            for ty in range(h // 8) for tx in range(w // 8)]

def vram_tile(vram: bytes, addr: int) -> tuple:
    rows = decode_tile(vram[addr:addr + 32], 4)
    return tuple(v for r in rows for v in r)

def expand(t: tuple, right: bool) -> tuple:
    """3bpp sheet pixel -> 4bpp VRAM pixel (docs/gfx/formats.md: left = as is, right = colours 9-15)."""
    return tuple(((s | 8) if s else 0) if right else s for s in t)

def cg(cgram: bytes, i: int) -> tuple:
    c = cgram[i * 2] | cgram[i * 2 + 1] << 8
    r, g, b = c & 31, (c >> 5) & 31, (c >> 10) & 31
    return (r << 3 | r >> 2, g << 3 | g >> 2, b << 3 | b >> 2)

def hexrgb(c) -> str:
    return "%02X%02X%02X" % c

# ---- trace ROM decoding (tools/art/make_trace_rom.py) --------------------------------------------------------------
DIGITS3 = [1, 2, 3, 4, 6]
DIGITS2 = [1, 2, 3]

def _val(pix, digits):
    v = 0
    for p in pix:
        if p not in digits:
            return None
        v = v * len(digits) + digits.index(p)
    return v

def trace_decode(t: tuple, bpp: int = 3):
    """t = 64 pixel values of one VRAM tile (4bpp values for sprites/BG, 2bpp for BG3). Returns (sheet, tile_idx|None) or None.
    Level-0 tiles carry (sheet, idx) in rows 6-7; level-1 tiles carry only the sheet in row 7 (x 4-7 for 3bpp, x 3-7 for 2bpp)."""
    if bpp == 3:
        m = tuple(p & 7 for p in t)
        v = _val(m[48:55], DIGITS3)
        if v is not None and v // 128 <= 0xDE and (v % 128) < 64:
            return (v // 128, v % 128)
        v = _val(m[60:64], DIGITS3)
        if v is not None and v <= 0xDE:
            return (v, None)
    else:
        v = _val(t[48:55], DIGITS2)
        if v is not None and v // 128 <= 4:
            return (0xDA + v // 128, v % 128)
        v = _val(t[59:64], DIGITS2)
        if v is not None and v <= 0xDE:
            return (v, None)
    return None
