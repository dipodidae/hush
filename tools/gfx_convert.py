#!/usr/bin/env python3
"""Convert PNGs in gfx/src/ to SNES 4bpp tiles + palettes in gfx/build/, and
validate SNES limits and HUSH's colour rules.

  gfx_convert.py all                    convert + validate every gfx/src/*.png
  gfx_convert.py convert path.png       one file (role from file-name prefix)
  gfx_convert.py check                  validate only, write nothing

Role comes from the file-name prefix:
  player_*  the player and their tools (faint violet)
  danger_*  guards, lanterns, alerts      (amber = danger)
  env_*     rooms, props, tiles           (deep indigo + warm light)
  ui_*      HUD / text

Output per <name>.png:
  gfx/build/<name>.4bpp   SNES 4bpp planar tiles, 32 bytes/tile, 8x8 tiles
                          left-to-right, top-to-bottom
  gfx/build/<name>.pal    16 x BGR555 little-endian (32 bytes); index 0 = transparent

SNES limits enforced (errors):
  * width and height are multiples of 8;
  * at most 15 opaque colours + transparent (index 0);
  * no two distinct source colours collapse to the same BGR555 colour;
  * source colours are BGR555-exact warning only (the SNES drops the low 3 bits).
Colour rules (errors), hue bands are HSV in degrees:
  * amber  hue 25-55, sat >= 0.40, val >= 0.35
  * violet hue 255-300, sat >= 0.20, val >= 0.30
  * player_*  must contain violet and must NOT contain amber
  * danger_*  must contain amber and must NOT contain violet
  * env_*     must NOT contain violet (player's colour) ; amber allowed (lamp light)
  * ui_*      unrestricted
This script validates; it does not make art. Final art is a human job.

Indexed (mode P) PNGs keep their palette order, with index 0 as transparent.
RGBA PNGs get indices in order of first appearance (alpha 0 -> index 0).
"""
from __future__ import annotations

import argparse
import colorsys
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "gfx" / "src"
OUT = ROOT / "gfx" / "build"

ROLES = ("player", "danger", "env", "ui")


def role_of(path: Path) -> str | None:
    prefix = path.stem.split("_", 1)[0]
    return prefix if prefix in ROLES else None


def hsv(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    return h * 360, s, v


def is_amber(rgb) -> bool:
    h, s, v = hsv(rgb)
    return 25 <= h <= 55 and s >= 0.40 and v >= 0.35


def is_violet(rgb) -> bool:
    h, s, v = hsv(rgb)
    return 255 <= h <= 300 and s >= 0.20 and v >= 0.30


def bgr555(rgb: tuple[int, int, int]) -> int:
    r, g, b = (c >> 3 for c in rgb)
    return (b << 10) | (g << 5) | r


def load_indexed(path: Path, errors: list[str]) -> tuple[list[list[int]], list[tuple[int, int, int]]] | None:
    """Return (pixel index rows, palette[0..n]) with index 0 = transparent."""
    rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
    img = Image.open(path)
    w, h = img.size
    if w % 8 or h % 8:
        errors.append(f"{rel}: size {w}x{h} is not a multiple of 8")
        return None

    if img.mode == "P":
        pal_flat = img.getpalette() or []
        pal = [tuple(pal_flat[i * 3:i * 3 + 3]) for i in range(len(pal_flat) // 3)]
        px = list(img.getdata())
        used = sorted(set(px))
        if used and max(used) > 15:
            errors.append(f"{rel}: uses palette index {max(used)}; 4bpp allows indices 0-15")
            return None
        palette = [(pal[i] if i < len(pal) else (0, 0, 0)) for i in range(16)]
        rows = [px[y * w:(y + 1) * w] for y in range(h)]
        return rows, palette

    rgba = img.convert("RGBA")
    order: dict[tuple[int, int, int], int] = {}
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = rgba.getpixel((x, y))
            if a < 128:
                row.append(0)
                continue
            key = (r, g, b)
            if key not in order:
                order[key] = len(order) + 1
            row.append(order[key])
        rows.append(row)
    if len(order) > 15:
        errors.append(f"{rel}: {len(order)} opaque colours; SNES 4bpp allows 15 + transparent")
        return None
    palette = [(0, 0, 0)] + list(order) + [(0, 0, 0)] * (15 - len(order))
    return rows, palette


def encode_4bpp(rows: list[list[int]]) -> bytes:
    h, w = len(rows), len(rows[0])
    out = bytearray()
    for ty in range(h // 8):
        for tx in range(w // 8):
            planes = [bytearray(8) for _ in range(4)]
            for y in range(8):
                for x in range(8):
                    v = rows[ty * 8 + y][tx * 8 + x]
                    for p in range(4):
                        planes[p][y] |= ((v >> p) & 1) << (7 - x)
            for y in range(8):          # planes 0,1 interleaved by row
                out += bytes((planes[0][y], planes[1][y]))
            for y in range(8):          # planes 2,3 interleaved by row
                out += bytes((planes[2][y], planes[3][y]))
    return bytes(out)


def validate(path: Path, rows, palette, errors: list[str], warnings: list[str]) -> None:
    rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
    used = sorted({v for row in rows for v in row} - {0})

    seen: dict[int, tuple[int, int, int]] = {}
    for idx in used:
        rgb = tuple(palette[idx])
        c = bgr555(rgb)
        if c in seen and seen[c] != rgb:
            errors.append(f"{rel}: colours {seen[c]} and {rgb} collapse to the same SNES colour")
        seen.setdefault(c, rgb)
        if any(ch & 7 for ch in rgb):
            warnings.append(f"{rel}: colour {rgb} is not BGR555-exact (low 3 bits are dropped)")

    role = role_of(path)
    if role is None:
        errors.append(f"{rel}: file name must start with one of {', '.join(r + '_' for r in ROLES)}")
        return
    colours = [tuple(palette[i]) for i in used]
    has_amber = any(is_amber(c) for c in colours)
    has_violet = any(is_violet(c) for c in colours)
    if role == "player":
        if has_amber:
            errors.append(f"{rel}: player asset contains amber (amber = danger)")
        if not has_violet:
            errors.append(f"{rel}: player asset has no violet (violet = you)")
    elif role == "danger":
        if has_violet:
            errors.append(f"{rel}: danger asset contains violet (violet = you)")
        if not has_amber:
            errors.append(f"{rel}: danger asset has no amber (amber = danger)")
    elif role == "env" and has_violet:
        errors.append(f"{rel}: environment asset contains violet (reserved for the player and tools)")


def process(path: Path, write: bool, errors: list[str], warnings: list[str]) -> None:
    loaded = load_indexed(path, errors)
    if loaded is None:
        return
    rows, palette = loaded
    before = len(errors)
    validate(path, rows, palette, errors, warnings)
    if write and len(errors) == before:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"{path.stem}.4bpp").write_bytes(encode_4bpp(rows))
        pal = bytearray()
        for rgb in palette[:16]:
            pal += bgr555(tuple(rgb)).to_bytes(2, "little")
        (OUT / f"{path.stem}.pal").write_bytes(bytes(pal))
        tiles = (len(rows) // 8) * (len(rows[0]) // 8)
        print(f"  {path.name}: {tiles} tile(s) -> gfx/build/{path.stem}.4bpp/.pal")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["all", "convert", "check"])
    ap.add_argument("png", nargs="?", type=Path)
    args = ap.parse_args()

    if args.command == "convert":
        if not args.png:
            ap.error("convert needs a PNG path")
        files = [args.png.resolve()]
    else:
        files = sorted(SRC.glob("*.png"))

    errors: list[str] = []
    warnings: list[str] = []
    for f in files:
        process(f, write=args.command != "check", errors=errors, warnings=warnings)
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors:
        print("GFX VALIDATION FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"gfx: {len(files)} file(s) ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
