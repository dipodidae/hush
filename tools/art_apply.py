#!/usr/bin/env python3
"""art_apply: merge full-colour art (RGBA PNG authored elsewhere) into an indexed HUSH sheet in gfx/src/.

  art_apply.py <art.png> <gfx/src/.../SHEET.png>                       whole sheet (art must be the sheet's size)
  art_apply.py <art.png> <SHEET.png> --rect X Y W H                    replace only that rectangle (pixels, multiples of 8
                                                                       are NOT required, but tile edges are what you want)
  art_apply.py <patch.png> <SHEET.png> --at X Y                        paste a smaller patch with its top-left at (X, Y)
  art_apply.py --export <out.png> <SHEET.png> [--rect X Y W H] [--zoom N]
                                                                       write the sheet as full-colour RGBA (index 0 -> alpha 0)
                                                                       to paint over; round-trips through this tool unchanged

What happens (apply):
  * palette = the target PNG's own palette (what tools/gfx_convert.py validates). `--palette yaml` uses the sibling
    <SHEET>.yaml `palette.indices` instead; `--palette other.png` borrows another indexed PNG's palette. A mismatch between
    PNG palette and yaml is reported. Only indices 1 .. 2^bpp-1 can be chosen (bpp from the yaml, default 4); index 0 = transparent.
  * alpha < 128 -> index 0. Every other pixel -> the palette entry with the identical colour; if there is none, the entry
    whose colour is identical after the SNES's BGR555 rounding ("exact"), else the nearest entry (Euclidean RGB) = SNAPPED.
    Snapped pixels are listed (source colour -> index, count, distance). A pixel further than --max-dist (default 48) from
    every entry aborts the run with nothing written, unless --force. --strict aborts on any snapped pixel.
  * the result is written back as an indexed PNG (mode P, same palette, transparency = index 0) and then validated
    with the same code as `gfx_convert.py check` (SNES limits + colour rules, for that file). If validation fails the old
    file is restored, unless --keep-on-fail.
  * --dry-run does everything except writing.

The three colour-rule roles (docs/gfx/art_map.md section 10): player sheets must contain violet and no amber, danger sheets must
contain amber and no violet, env sheets no violet. The rules look at the PNG palette entries of the indices you actually use.
`make gfx` OVERWRITES gfx/src with placeholders; never run it once you have painted.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gfx_convert  # noqa: E402  (validation: SNES limits + colour roles, the same code as `gfx_convert.py check`)


def rel(p: Path) -> str:
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)


def bgr555(rgb) -> tuple:
    return tuple(c >> 3 for c in rgb)


def brief_of(sheet: Path) -> dict:
    y = sheet.with_suffix(".yaml")
    return (yaml.safe_load(y.read_text()) or {}) if y.exists() else {}


def png_palette(im: Image.Image, n: int) -> list[tuple]:
    flat = im.getpalette() or []
    pal = [tuple(flat[i * 3:i * 3 + 3]) for i in range(len(flat) // 3)]
    pal += [(0, 0, 0)] * (n - len(pal))
    return pal[:max(n, len(pal))]


def yaml_palette(brief: dict, n: int) -> list[tuple] | None:
    idx = (brief.get("palette") or {}).get("indices")
    if not idx:
        return None
    pal = [(0, 0, 0)] * n
    for k, v in idx.items():
        m = re.match(r"#?([0-9A-Fa-f]{6})", str(v).strip())
        if m and int(k) < n:
            h = m.group(1)
            pal[int(k)] = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return pal


def load_target(sheet: Path):
    im = Image.open(sheet)
    if im.mode != "P":
        sys.exit(f"{rel(sheet)} is not an indexed (mode P) PNG; refusing to touch it")
    return im


def export(sheet: Path, out: Path, rect, zoom: int) -> None:
    im = load_target(sheet)
    brief = brief_of(sheet)
    bpp = int(brief.get("bpp", 4))
    pal = png_palette(im, 1 << bpp)
    w, h = im.size
    x0, y0, rw, rh = rect or (0, 0, w, h)
    px = im.load()
    rgba = Image.new("RGBA", (rw, rh))
    for y in range(rh):
        for x in range(rw):
            v = px[x0 + x, y0 + y]
            rgba.putpixel((x, y), (0, 0, 0, 0) if v == 0 else (*pal[v], 255))
    if zoom > 1:
        rgba = rgba.resize((rw * zoom, rh * zoom), Image.NEAREST)
    out.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(out)
    print(f"exported {rel(sheet)} {rw}x{rh} at ({x0},{y0}) -> {rel(out)}" + (f" (zoom {zoom}x: shrink back to 1x before applying)" if zoom > 1 else ""))


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("art", type=Path, help="RGBA PNG to apply (or, with --export, the PNG to write)")
    ap.add_argument("target", type=Path, help="indexed sheet in gfx/src/")
    ap.add_argument("--rect", nargs=4, type=int, metavar=("X", "Y", "W", "H"), help="only this rectangle of the sheet is replaced")
    ap.add_argument("--at", nargs=2, type=int, metavar=("X", "Y"), help="paste a patch whose top-left lands here")
    ap.add_argument("--palette", default="png", help="png (default) | yaml | path of another indexed PNG")
    ap.add_argument("--max-dist", type=float, default=48.0, help="largest RGB distance a pixel may be snapped over (default 48)")
    ap.add_argument("--strict", action="store_true", help="fail if any pixel had to be snapped")
    ap.add_argument("--force", action="store_true", help="ignore --max-dist")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--keep-on-fail", action="store_true", help="keep the written file even if validation fails")
    ap.add_argument("--export", action="store_true", help="export the target as RGBA instead of applying")
    ap.add_argument("--zoom", type=int, default=1, help="with --export: nearest-neighbour zoom")
    args = ap.parse_args()

    target = args.target if args.target.is_absolute() else Path.cwd() / args.target
    if not target.exists():
        sys.exit(f"target {args.target} does not exist")
    if args.export:
        export(target, args.art, args.rect, args.zoom)
        return 0

    im = load_target(target)
    W, H = im.size
    brief = brief_of(target)
    bpp = int(brief.get("bpp", 4))
    ncol = 1 << bpp
    png_pal = png_palette(im, ncol)
    yaml_pal = yaml_palette(brief, ncol)
    if args.palette == "yaml":
        if yaml_pal is None:
            sys.exit("no palette.indices in the target's yaml")
        pal = yaml_pal
    elif args.palette == "png":
        pal = png_pal
    else:
        other = Image.open(args.palette)
        pal = png_palette(other, ncol)
    if yaml_pal is not None and args.palette != "yaml":
        diff = [i for i in range(1, ncol) if tuple(yaml_pal[i]) != tuple(png_pal[i]) and yaml_pal[i] != (0, 0, 0)]
        if diff:
            print(f"warning: yaml palette.indices differ from the PNG palette at index {diff}; using the PNG palette")

    art = Image.open(args.art).convert("RGBA")
    aw, ah = art.size
    if args.rect and args.at:
        sys.exit("use --rect or --at, not both")
    if args.rect:
        x0, y0, rw, rh = args.rect
        if (aw, ah) == (W, H):
            art = art.crop((x0, y0, x0 + rw, y0 + rh))
        elif (aw, ah) != (rw, rh):
            sys.exit(f"art is {aw}x{ah}; with --rect it must be the rect size {rw}x{rh} or the whole sheet {W}x{H}")
    elif args.at:
        x0, y0 = args.at
        rw, rh = aw, ah
    else:
        x0, y0, rw, rh = 0, 0, W, H
        if (aw, ah) != (W, H):
            sys.exit(f"art is {aw}x{ah} but {rel(target)} is {W}x{H}: give --rect X Y W H or --at X Y to merge a patch")
    if x0 < 0 or y0 < 0 or x0 + rw > W or y0 + rh > H:
        sys.exit(f"rect ({x0},{y0},{rw},{rh}) is outside the {W}x{H} sheet")
    if (x0 % 8 or y0 % 8 or rw % 8 or rh % 8):
        print(f"note: rect ({x0},{y0},{rw},{rh}) is not tile aligned (8 px); fine, but check the neighbouring tiles")

    # nearest-entry lookup: only indices the palette really defines (a short PNG palette is padded with black above)
    if args.palette == "yaml":
        defined = {int(k) for k in (brief.get("palette") or {}).get("indices", {})}
    elif args.palette == "png":
        defined = set(range(len(im.getpalette() or []) // 3))
    else:
        defined = set(range(len(Image.open(args.palette).getpalette() or []) // 3))
    cand = [i for i in range(1, ncol) if i in defined]
    if not cand:
        sys.exit("the palette defines no opaque colours")
    exact: dict = {}
    exact555: dict = {}
    for i in cand:
        if tuple(pal[i]) in exact:
            print(f"warning: indices {exact[tuple(pal[i])]} and {i} have the same colour; art_apply always picks {exact[tuple(pal[i])]}")
        exact.setdefault(tuple(pal[i]), i)
        exact555.setdefault(bgr555(pal[i]), i)
    cache: dict = {}
    snaps: Counter = Counter()
    snapinfo: dict = {}
    worst = 0.0
    used: Counter = Counter()
    out_px = im.copy()
    op = out_px.load()
    ap_ = art.load()
    for y in range(rh):
        for x in range(rw):
            r, g, b, a = ap_[x, y]
            if a < 128:
                idx = 0
            else:
                key = (r, g, b)
                if key in cache:
                    idx = cache[key]
                elif key in exact:
                    idx = cache[key] = exact[key]
                elif bgr555(key) in exact555:
                    idx = cache[key] = exact555[bgr555(key)]
                else:
                    dist, idx = min(((sum((a_ - b_) ** 2 for a_, b_ in zip(key, pal[i]))) ** 0.5, i) for i in cand)
                    cache[key] = idx
                    snapinfo[key] = (idx, dist)
                if key in snapinfo:
                    snaps[key] += 1
                    worst = max(worst, snapinfo[key][1])
            used[idx] += 1
            op[x0 + x, y0 + y] = idx

    total = rw * rh
    nsnap = sum(snaps.values())
    print(f"{rel(target)} {W}x{H} bpp {bpp}: region ({x0},{y0}) {rw}x{rh} = {total} px; "
          f"{total - nsnap - used[0]} exact opaque, {used[0]} transparent, {nsnap} snapped (worst distance {worst:.1f})")
    print("index usage: " + ", ".join(f"{i}:{n}" for i, n in sorted(used.items())))
    for key, n in snaps.most_common(12):
        idx, dist = snapinfo[key]
        print(f"  snapped #{key[0]:02X}{key[1]:02X}{key[2]:02X} -> index {idx} (#{pal[idx][0]:02X}{pal[idx][1]:02X}{pal[idx][2]:02X}), "
              f"{n} px, distance {dist:.1f}")
    if len(snaps) > 12:
        print(f"  ... {len(snaps) - 12} more source colours snapped")
    if nsnap and args.strict:
        print("--strict: pixels needed snapping; nothing written", file=sys.stderr)
        return 1
    if worst > args.max_dist and not args.force:
        print(f"a pixel is {worst:.1f} away from every palette entry (> --max-dist {args.max_dist}): wrong colours? "
              f"Nothing written. Use --force to snap anyway.", file=sys.stderr)
        return 1
    if args.dry_run:
        print("dry run: nothing written")
        return 0

    old = target.read_bytes()
    out_px.putpalette(im.getpalette())
    out_px.save(target, transparency=0)
    errors: list[str] = []
    warnings: list[str] = []
    gfx_convert.process(target.resolve(), write=False, errors=errors, warnings=warnings)
    rounding = [w for w in warnings if "BGR555-exact" in w]
    for w in warnings:
        if w not in rounding:
            print(f"warning: {w}")
    if rounding:
        print(f"note: {len(rounding)} palette colour(s) lose their low 3 bits on the SNES (BGR555); the placeholders' palette already does, harmless")
    if errors:
        print("GFX VALIDATION FAILED for this file:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        if not args.keep_on_fail:
            target.write_bytes(old)
            print("old file restored (use --keep-on-fail to keep the result)", file=sys.stderr)
        return 1
    print(f"wrote {rel(target)}; gfx_convert check for this file: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
