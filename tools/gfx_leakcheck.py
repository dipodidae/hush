#!/usr/bin/env python3
"""Vanilla-graphics leak detector.

  gfx_leakcheck.py [--results DIR ...] [--control] [--report PATH]

Reads scene dumps written by tests/gfx/*.lua (via tests/lib/gfx.lua): for each scene
  <scene>.vram (64 KiB)  <scene>.cgram (512 B)  <scene>.oam  <scene>.ppu.txt  <scene>.png
and compares them with the vanilla reference built by tools/gfx_refdump.py (build/ref/):
  * every 32-byte VRAM chunk is read as a 4bpp tile, as a 3bpp-expanded tile (planes 0-2, only when
    plane 3 is 0 or the OR of planes 0-2 like the game's own expansion), and as two 2bpp tiles;
    each is looked up (with H/V flips) among all non-blank vanilla tiles;
  * every CGRAM row is compared with every vanilla palette row (runs of >= 4 identical colours).
A match is reported with the VRAM address, the scene and the inventory asset it belongs to (sheet
and tile). Decision rule (a single simple tile can coincide with a placeholder by chance):
  LEAK  = a rich tile (>= 3 colours, >= 24 opaque pixels) matches, or >= 3 DISTINCT tiles of the same
          vanilla sheet match (copies of one tile in VRAM count once), or >= 3 palette colours-runs match.
  weak  = an isolated simple-tile match: listed, not a failure.
Exit code 1 when any LEAK exists. Leaking tiles that are on screen are boxed in
build/test-results/leakcheck/<scene>_leaks.png.
`--control` runs the same check on a build with vanilla graphics and exits 0 only if leaks WERE found
(proves the detector works).
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT  # noqa: E402
from gfx_refdump import tile_key, variants  # noqa: E402
from gfxlib import decode_tile  # noqa: E402

REF = ROOT / "build" / "ref"
RESULTS = ROOT / "build" / "test-results"
OUT = RESULTS / "leakcheck"


def load_ref():
    if not (REF / "tilehash.json").exists():
        sys.exit("build/ref missing: run `.venv/bin/python tools/gfx_refdump.py` (make leakcheck does this)")
    d = json.loads((REF / "tilehash.json").read_text())
    sets = {k: set(v) for k, v in d["sets"].items()}
    pal = json.loads((REF / "palettes_full.json").read_text())
    grams: dict[tuple, str] = {}
    for row in pal:
        c = row["colors"]
        for i in range(len(c) - 3):
            g = tuple(c[i:i + 4])
            vals = {x for x in g if x not in (0x0000, 0x7FFF)}
            if len(vals) >= 3:
                grams.setdefault(g, f"{row['label']}@${row['addr']:06X}")
    return sets, d["attrib"], grams


def parse_ppu(path: Path) -> dict:
    d = {}
    for ln in path.read_text().splitlines():
        k, v = ln.split("=", 1)
        d[k] = v
    return d


def decode4(chunk: bytes):
    return decode_tile(chunk, 4)


def richness(rows) -> tuple[int, int]:
    vals = {v for r in rows for v in r}
    opaque = sum(1 for r in rows for v in r if v)
    return len(vals), opaque


def check_vram(vram: bytes, sets, attrib):
    hits = []
    for n in range(len(vram) // 32):
        chunk = vram[n * 32:(n + 1) * 32]
        if not any(chunk):
            continue
        base = n * 32
        cands = []
        rows4 = decode4(chunk)
        cands.append(("4", rows4, base))
        low = [[v & 7 for v in r] for r in rows4]
        sheetlike = all(((v >> 3) & 1) == 0 for r in rows4 for v in r) or \
            all(((v >> 3) & 1) == (1 if (v & 7) else 0) for r in rows4 for v in r)
        if sheetlike:
            cands.append(("3", low, base))
        cands.append(("2", decode_tile(chunk[:16], 2), base))
        cands.append(("2", decode_tile(chunk[16:], 2), base + 16))
        for bpp, rows, addr in cands:
            colors, opaque = richness(rows)
            if colors <= 1:
                continue
            for var in variants(rows):
                key = tile_key(var)
                if key in sets[bpp]:
                    hits.append(dict(addr=addr, bpp=int(bpp), key=key, owner=attrib.get(f"{bpp}:{key}", "?"),
                                     rich=colors >= 3 and opaque >= 24))
                    break
    return hits


def check_cgram(cg: bytes, grams):
    cols = [cg[i] | (cg[i + 1] << 8) for i in range(0, len(cg), 2)]
    hits = []
    for row in range(16):
        c = cols[row * 16:(row + 1) * 16]
        for i in range(len(c) - 3):
            g = tuple(c[i:i + 4])
            if g in grams:
                hits.append(dict(row=row, start=i, matches=grams[g], colors=[f"{x:04X}" for x in g]))
    # merge overlapping runs per row
    merged = {}
    for h in hits:
        merged.setdefault((h["row"], h["matches"].split("@")[0]), h)
    return list(merged.values())


def decide(hits):
    leaks, weak = [], []
    uniq = collections.defaultdict(set)          # distinct matching tiles per vanilla sheet (copies in VRAM don't count)
    for h in hits:
        uniq[h["owner"].split(":")[0]].add(h["key"])
    for h in hits:
        if h["rich"] or len(uniq[h["owner"].split(":")[0]]) >= 3:
            leaks.append(h)
        else:
            weak.append(h)
    return leaks, weak


def mark_screenshot(scene_base: Path, leaks, out_png: Path):
    """Box leaking tiles that are on screen (BG via tilemaps, OBJ via OAM). Best effort."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return 0
    png = scene_base.with_suffix(".png")
    if not png.exists():
        return 0
    vram = scene_base.with_suffix(".vram").read_bytes()
    oam = scene_base.with_suffix(".oam").read_bytes()
    ppu = parse_ppu(scene_base.with_suffix(".ppu.txt"))
    leak_addrs = {h["addr"] for h in leaks}
    img = Image.open(png).convert("RGB")
    sx = img.width / 256
    sy = img.height / 224
    d = ImageDraw.Draw(img)
    marked = 0
    mode = int(ppu["bgMode"])
    for i in range(3):
        tm, chr_, hs, vs, dw, dh, _ = ppu[f"layer{i}"].split(",")
        tm, chr_, hs, vs = int(tm), int(chr_), int(hs), int(vs)
        bpp = 4 if (i < 2 and mode == 1) or mode == 0 and False else 2
        if mode == 1 and i == 2:
            bpp = 2
        tb = 32 if bpp == 4 else 16
        w_maps = 2 if dw == "1" else 1
        h_maps = 2 if dh == "1" else 1
        for my in range(h_maps):
            for mx in range(w_maps):
                base = (tm + (my * w_maps + mx) * 0x400) * 2
                for ty in range(32):
                    for tx in range(32):
                        o = base + (ty * 32 + tx) * 2
                        if o + 1 >= len(vram):
                            continue
                        e = vram[o] | (vram[o + 1] << 8)
                        t = e & 0x3FF
                        a = (chr_ * 2 + t * tb) & 0xFFFF
                        if a in leak_addrs:
                            x = ((mx * 32 + tx) * 8 - hs) % (w_maps * 256)
                            y = ((my * 32 + ty) * 8 - vs) % (h_maps * 256)
                            if x < 256 and y < 224 and (mode != 1 or True):
                                d.rectangle([x * sx, y * sy, (x + 8) * sx, (y + 8) * sy], outline=(255, 0, 0))
                                marked += 1
    base_w = int(ppu["oamBaseAddress"]) * 2
    gap = int(ppu["oamAddressOffset"]) * 2
    sizes = {0: (8, 16), 1: (8, 32), 2: (8, 64), 3: (16, 32), 4: (16, 64), 5: (32, 64)}.get(int(ppu["oamMode"]), (8, 16))
    for i in range(128):
        x, y, tile, attr = oam[i * 4:i * 4 + 4]
        hi = oam[512 + i // 4] >> ((i % 4) * 2)
        x |= (hi & 1) << 8
        size = sizes[1] if hi & 2 else sizes[0]
        if x >= 256:
            x -= 512
        name = attr & 1
        for cy in range(size // 8):
            for cx in range(size // 8):
                t = (tile + cy * 16 + cx) & 0xFF
                a = (base_w + (gap if name else 0) + t * 32) & 0xFFFF
                if a in leak_addrs:
                    d.rectangle([(x + cx * 8) * sx, (y + 1 + cy * 8) * sy, (x + cx * 8 + 8) * sx, (y + 1 + cy * 8 + 8) * sy], outline=(255, 0, 0))
                    marked += 1
    out_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_png)
    return marked


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--results", action="append", type=Path, help="result dirs (default: build/test-results/gfx_*)")
    ap.add_argument("--results-root", type=Path, default=RESULTS, help="directory holding gfx_* result dirs")
    ap.add_argument("--control", action="store_true", help="expect leaks (vanilla-graphics control build)")
    ap.add_argument("--report", type=Path, default=ROOT / "docs" / "gfx" / "leak_report.md")
    ap.add_argument("--no-report", action="store_true")
    args = ap.parse_args()
    dirs = args.results or sorted(d for d in args.results_root.glob("gfx_*") if d.is_dir())
    scenes = [(d, p.with_suffix("")) for d in dirs for p in sorted(d.glob("*.vram"))]
    if not scenes:
        print("leakcheck: no scene dumps found (run `make leakcheck`, which runs tests/gfx first)", file=sys.stderr)
        return 2
    sets, attrib, grams = load_ref()
    total_leaks = total_weak = total_pal = 0
    lines = []
    summary = []
    for d, base in scenes:
        vram = base.with_suffix(".vram").read_bytes()
        cg = base.with_suffix(".cgram").read_bytes()
        hits = check_vram(vram, sets, attrib)
        leaks, weak = decide(hits)
        pal = check_cgram(cg, grams)
        total_leaks += len(leaks); total_weak += len(weak); total_pal += len(pal)
        scene = f"{d.name.removeprefix('gfx_')}/{base.name}"
        marked = 0
        if leaks:
            marked = mark_screenshot(base, leaks, OUT / ("control_" if args.control else "") / f"{d.name}_{base.name}_leaks.png")
        summary.append((scene, len(leaks), len(weak), len(pal), marked))
        lines.append(f"### {scene}")
        if not (leaks or weak or pal):
            lines.append("clean: no vanilla tiles or palettes found.\n")
            continue
        by_owner = collections.defaultdict(list)
        for h in leaks:
            by_owner[h["owner"].split(":")[0]].append(h)
        for o, hs in sorted(by_owner.items()):
            ex = ", ".join(f"${h['addr']:04X}({h['bpp']}bpp {h['owner'].split(':')[1]})" for h in hs[:6])
            lines.append(f"- LEAK `{o}`: {len(hs)} tile(s), e.g. VRAM {ex}" + (" ..." if len(hs) > 6 else ""))
        for h in weak[:5]:
            lines.append(f"- weak match `{h['owner']}` at VRAM ${h['addr']:04X} ({h['bpp']}bpp, simple tile; not a failure)")
        for h in pal:
            lines.append(f"- LEAK palette row {h['row']} (cols {h['start']}..): vanilla `{h['matches']}` {h['colors']}")
        if marked:
            lines.append(f"- screenshot with {marked} marked tile(s): build/test-results/leakcheck/{'control_' if args.control else ''}{d.name}_{base.name}_leaks.png")
        lines.append("")
    verdict_fail = (total_leaks + total_pal) > 0
    head = [f"# Vanilla-graphics leak report", "",
            "Generated by `tools/gfx_leakcheck.py` from the scene dumps of `tests/gfx/*.lua`. "
            "See the tool docstring for the matching rules.", "",
            f"**Result: {'LEAKS FOUND' if verdict_fail else 'CLEAN'}** (scenes: {len(scenes)}, tile leaks: {total_leaks}, "
            f"palette leaks: {total_pal}, weak matches: {total_weak})", "",
            "| scene | tile leaks | weak | palette leaks |", "|---|---|---|---|"]
    head += [f"| {s} | {a} | {b} | {c} |" for s, a, b, c, _ in summary] + [""]
    text = "\n".join(head + lines) + "\n"
    if not args.no_report and not args.control:
        args.report.write_text(text)
    print("\n".join(head))
    if verdict_fail:
        print("\n".join(l for l in lines if l.startswith("- LEAK"))[:6000])
    if args.control:
        ok = verdict_fail
        print("control build: " + ("leaks detected as expected, detector works" if ok else "NO leaks found in a vanilla-graphics build: detector is broken"))
        return 0 if ok else 1
    return 1 if verdict_fail else 0


if __name__ == "__main__":
    sys.exit(main())
