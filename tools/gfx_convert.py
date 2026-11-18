#!/usr/bin/env python3
"""Convert indexed PNGs in gfx/src/ to SNES planar tiles + palettes in gfx/build/, and
validate SNES limits and HUSH's colour rules.

  gfx_convert.py all                    convert + validate every gfx/src/**/*.png
  gfx_convert.py convert path.png       one file
  gfx_convert.py check                  validate only, write nothing

Per image, an optional sibling `<name>.yaml` (the drawing brief) supplies:
  role: player | danger | env | ui | debug      (default: from the file-name prefix)
  bpp:  2 | 3 | 4 | 8                            (default 4)
Without a brief the role comes from the file-name prefix:
  player_*  the player and their tools (faint violet)
  danger_*  guards, lanterns, alerts      (amber = danger)
  env_*     rooms, props, tiles           (deep indigo + warm light)
  ui_*      HUD / text
  debug     placeholder UNUSED/CUT sheets (magenta): exempt from the colour-role rules ONLY;
            SNES limits still apply.

Output per <name>.png:
  gfx/build/<name>.<N>bpp   SNES planar tiles (8x8, left-to-right, top-to-bottom):
                            2bpp 16 B/tile, 3bpp 24 B/tile (ALttP layout), 4bpp 32 B/tile,
                            8bpp 64 B/tile (Mode 7 linear)
  gfx/build/<name>.pal      2^bpp (max 16) x BGR555 little-endian; index 0 = transparent

SNES limits enforced (errors):
  * width and height are multiples of 8;
  * at most 2^bpp - 1 opaque colours + transparent (index 0): 3bpp = 7, 4bpp = 15 ...;
  * indices used by the image are < 2^bpp;
  * no two distinct source colours collapse to the same BGR555 colour;
  * source colours are BGR555-exact (warning only; the SNES drops the low 3 bits).
Colour rules (errors), hue bands are HSV in degrees:
  * amber  hue 25-55, sat >= 0.40, val >= 0.35
  * violet hue 255-300, sat >= 0.20, val >= 0.30
  * player  must contain violet and must NOT contain amber
  * danger  must contain amber and must NOT contain violet
  * env     must NOT contain violet (player's colour) ; amber allowed (lamp light)
  * ui, debug  unrestricted
Colour rules look only at indices the image actually uses.
This script validates; it does not make art. Final art is a human job.
"""
from __future__ import annotations

import argparse
import colorsys
import sys
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from gfxlib import encode_tile  # noqa: E402

SRC = ROOT / "gfx" / "src"
OUT = ROOT / "gfx" / "build"

ROLES = ("player", "danger", "env", "ui", "debug")
EXT = {2: "2bpp", 3: "3bpp", 4: "4bpp", 8: "8bpp"}


def hsv(rgb):
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    return h * 360, s, v


def is_amber(rgb) -> bool:
    h, s, v = hsv(rgb)
    return 25 <= h <= 55 and s >= 0.40 and v >= 0.35


def is_violet(rgb) -> bool:
    h, s, v = hsv(rgb)
    return 255 <= h <= 300 and s >= 0.20 and v >= 0.30


def bgr555(rgb) -> int:
    r, g, b = (c >> 3 for c in rgb)
    return (b << 10) | (g << 5) | r


def brief_of(path: Path) -> dict:
    y = path.with_suffix(".yaml")
    return (yaml.safe_load(y.read_text()) or {}) if y.exists() else {}


def role_of(path: Path, brief: dict) -> str | None:
    if brief.get("role"):
        return brief["role"]
    prefix = path.stem.split("_", 1)[0]
    return prefix if prefix in ROLES else None


def rel(path: Path):
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def load_indexed(path: Path, bpp: int, errors: list[str]):
    """Return (pixel index rows, palette[0..2^bpp-1]) with index 0 = transparent."""
    img = Image.open(path)
    w, h = img.size
    if w % 8 or h % 8:
        errors.append(f"{rel(path)}: size {w}x{h} is not a multiple of 8")
        return None
    ncol = 1 << bpp
    if img.mode == "P":
        pal_flat = img.getpalette() or []
        pal = [tuple(pal_flat[i * 3:i * 3 + 3]) for i in range(len(pal_flat) // 3)]
        px = list(img.getdata())
        used = sorted(set(px))
        if used and max(used) >= ncol:
            errors.append(f"{rel(path)}: uses palette index {max(used)}; {bpp}bpp allows indices 0-{ncol - 1}")
            return None
        palette = [(pal[i] if i < len(pal) else (0, 0, 0)) for i in range(ncol)]
        rows = [px[y * w:(y + 1) * w] for y in range(h)]
        return rows, palette
    rgba = img.convert("RGBA")
    order: dict = {}
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
    if len(order) > ncol - 1:
        errors.append(f"{rel(path)}: {len(order)} opaque colours; {bpp}bpp allows {ncol - 1} + transparent")
        return None
    palette = [(0, 0, 0)] + list(order) + [(0, 0, 0)] * (ncol - 1 - len(order))
    return rows, palette


def encode(rows, bpp: int) -> bytes:
    h, w = len(rows), len(rows[0])
    out = bytearray()
    for ty in range(h // 8):
        for tx in range(w // 8):
            tile = [rows[ty * 8 + y][tx * 8:tx * 8 + 8] for y in range(8)]
            if bpp == 8:
                for r in tile:
                    out += bytes(r)
            else:
                out += encode_tile(tile, bpp)
    return bytes(out)


encode_4bpp = lambda rows: encode(rows, 4)  # noqa: E731  (kept for M0 compatibility)


def validate(path: Path, rows, palette, role, errors: list[str], warnings: list[str]) -> None:
    used = sorted({v for row in rows for v in row} - {0})
    seen: dict = {}
    for idx in used:
        rgb = tuple(palette[idx])
        c = bgr555(rgb)
        if c in seen and seen[c] != rgb:
            errors.append(f"{rel(path)}: colours {seen[c]} and {rgb} collapse to the same SNES colour")
        seen.setdefault(c, rgb)
        if any(ch & 7 for ch in rgb):
            warnings.append(f"{rel(path)}: colour {rgb} is not BGR555-exact (low 3 bits are dropped)")
    if role is None:
        errors.append(f"{rel(path)}: no role (add a brief with `role:` or start the file name with one of "
                      f"{', '.join(r + '_' for r in ROLES)})")
        return
    if role not in ROLES:
        errors.append(f"{rel(path)}: unknown role '{role}'")
        return
    colours = [tuple(palette[i]) for i in used]
    has_amber = any(is_amber(c) for c in colours)
    has_violet = any(is_violet(c) for c in colours)
    if role == "player":
        if has_amber:
            errors.append(f"{rel(path)}: player asset contains amber (amber = danger)")
        if not has_violet:
            errors.append(f"{rel(path)}: player asset has no violet (violet = you)")
    elif role == "danger":
        if has_violet:
            errors.append(f"{rel(path)}: danger asset contains violet (violet = you)")
        if not has_amber:
            errors.append(f"{rel(path)}: danger asset has no amber (amber = danger)")
    elif role == "env" and has_violet:
        errors.append(f"{rel(path)}: environment asset contains violet (reserved for the player and tools)")


def process(path: Path, write: bool, errors: list[str], warnings: list[str]):
    brief = brief_of(path)
    bpp = int(brief.get("bpp", 4))
    if bpp not in EXT:
        errors.append(f"{rel(path)}: unsupported bpp {bpp}")
        return None
    loaded = load_indexed(path, bpp, errors)
    if loaded is None:
        return None
    rows, palette = loaded
    before = len(errors)
    validate(path, rows, palette, role_of(path, brief), errors, warnings)
    if len(errors) != before:
        return None
    data = encode(rows, bpp)
    if write:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"{path.stem}.{EXT[bpp]}").write_bytes(data)
        pal = bytearray()
        for rgb in palette[:16]:
            pal += bgr555(tuple(rgb)).to_bytes(2, "little")
        (OUT / f"{path.stem}.pal").write_bytes(bytes(pal))
    return data


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
        files = sorted(SRC.rglob("*.png"))
    errors: list[str] = []
    warnings: list[str] = []
    for f in files:
        process(f, write=args.command != "check", errors=errors, warnings=warnings)
    for w in warnings[:20]:
        print(f"warning: {w}", file=sys.stderr)
    if len(warnings) > 20:
        print(f"warning: ... {len(warnings) - 20} more", file=sys.stderr)
    if errors:
        print("GFX VALIDATION FAILED", file=sys.stderr)
        for e in errors[:60]:
            print(f"  - {e}", file=sys.stderr)
        if len(errors) > 60:
            print(f"  ... {len(errors) - 60} more", file=sys.stderr)
        return 1
    print(f"gfx: {len(files)} file(s) ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
