#!/usr/bin/env python3
"""Research helper for docs/gfx/art_map.md: build a PRIVATE copy of the ROM whose placeholder sheets carry a machine-readable
(sheet id, tile index) code in their last two pixel rows, so every tile found in VRAM can be traced back to its exact sheet and
tile index (the normal placeholders only show the tile index, identically in every sheet).

  .venv/bin/python tools/art/make_trace_rom.py          # -> build/art_research/trace/build/hush.sfc

Nothing in the real repo is touched: the repo is rsynced into build/art_research/trace/ (gitignored), the PNGs there are
patched, and that copy is built with its own tools/build.py. The vanilla ROM stays a symlink to rom/vanilla.sfc (never copied).
Code format (see decode() below): value = sheet_code * tiles_per_sheet + tile_idx written in base len(DIGITS) over the last
16 pixels (rows 6-7) of each 8x8 tile, most significant digit first, using palette indices that satisfy every colour rule.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
T = ROOT / "build" / "art_research" / "trace"
DIGITS3 = [1, 2, 3, 4, 6]        # 3bpp: avoids 5 (amber: forbidden in player sheets) and 7 (violet: forbidden in env/danger)
DIGITS2 = [1, 2, 3]              # 2bpp HUD
NDIG3, NDIG2 = 7, 7


def encode_value(value: int, digits: list[int], n: int) -> list[int]:
    out = []
    for _ in range(n):
        out.append(digits[value % len(digits)])
        value //= len(digits)
    return out[::-1]


def decode_value(pix: list[int], digits: list[int]) -> int:
    v = 0
    for p in pix:
        v = v * len(digits) + digits.index(p)
    return v


def code_of(name: str) -> int:
    return int(name.split("_")[1], 16)


def patch_png(path: Path, level: int = 0) -> bool:
    """level 0: (sheet, tile) code on every tile; 1: sheet code only, on non-blank tiles (compresses better); 2: untouched."""
    name = path.stem
    if not name.startswith("GFX_"):
        return False
    im = Image.open(path)
    if im.mode != "P":
        return False
    w, h = im.size
    bpp3 = im.getpalette() is not None and (len(im.getpalette()) // 3) > 4
    sheet = code_of(name)
    if sheet in (0x39, 0x40, 0x41):      # title sheets are laid out by tools/gfx_title.py
        return False
    if level >= 2:
        return False
    px = im.load()
    digits, n = (DIGITS3, NDIG3) if bpp3 else (DIGITS2, NDIG2)
    tpr = w // 8
    for ty in range(h // 8):
        for tx in range(tpr):
            idx = ty * tpr + tx
            if level == 0:
                d = encode_value(((sheet - 0xDA) if not bpp3 else sheet) * 128 + idx, digits, n)
                pos = [(k % 8, 6 + k // 8) for k in range(n)]
            else:
                if not any(px[tx * 8 + x, ty * 8 + y] for x in range(8) for y in range(8)):
                    continue
                d = encode_value(sheet, digits, 4 if bpp3 else 5)
                pos = [(4 + k, 7) for k in range(len(d))] if bpp3 else [(3 + k, 7) for k in range(len(d))]
            for (x, y), dv in zip(pos, d):
                px[tx * 8 + x, y + ty * 8] = dv
    im.save(path, transparency=0)
    return True


def main() -> int:
    if T.exists():
        shutil.rmtree(T, ignore_errors=True)
    T.mkdir(parents=True)
    subprocess.check_call(["rsync", "-a", "--exclude", "build", "--exclude", ".git", "--exclude", "vendor", "--exclude", ".venv",
                           "--exclude", ".tools", "--exclude", "rom", "--exclude", "dist", "--exclude", "telemetry", str(ROOT) + "/", str(T) + "/"])
    for d in ("vendor", ".venv", ".tools", "rom"):
        (T / d).symlink_to(ROOT / d)
    (T / "build").mkdir()
    import re
    levels: dict[str, int] = {}
    subprocess.check_call([str(T / ".venv/bin/python"), "tools/roomgen.py"], cwd=T, stdout=subprocess.DEVNULL)
    for attempt in range(4):
        pristine = ROOT / "gfx" / "src"
        for p in sorted(pristine.rglob("GFX_*.png")):
            shutil.copy2(p, T / "gfx" / "src" / p.relative_to(pristine))
        n = sum(patch_png(p, levels.get(p.stem, 0)) for p in sorted((T / "gfx" / "src").rglob("GFX_*.png")))
        print(f"attempt {attempt}: patched {n} sheets; downgraded: {levels}")
        r = subprocess.run([str(T / ".venv/bin/python"), "tools/build.py", "build"], cwd=T, capture_output=True, text=True)
        if r.returncode == 0:
            print(r.stdout.strip().splitlines()[-1])
            return 0
        bad = re.findall(r"- (GFX_[0-9A-F]+): compressed", r.stdout + r.stderr)
        if not bad:
            print(r.stdout, r.stderr)
            return r.returncode
        for b in bad:
            levels[b] = levels.get(b, 0) + 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
