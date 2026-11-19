#!/usr/bin/env python3
"""Research helper (docs/gfx/art_map.md section 9): build a PRIVATE ROM whose palette yaml groups carry a unique code in every colour,
so a CGRAM dump shows exactly which gfx/src/palettes group, row and colour defines each CGRAM entry.

  .venv/bin/python tools/art/make_trace_pal_rom.py    # -> build/art_research/trace_pal/build/hush.sfc + groups.json
Colour code (15 bits, BGR555-exact): value = group_index * 128 + row * 8 + colour_in_row, split 5/5/5 bits into R, G, B (low bits first).
Decode with decode(rgb) below. The real repo is untouched.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
T = ROOT / "build" / "art_research" / "trace_pal"


def encode(g: int, r: int, j: int) -> str:
    v = g * 128 + r * 8 + j
    r5, g5, b5 = v & 31, (v >> 5) & 31, (v >> 10) & 31
    return "%02X%02X%02X" % (r5 << 3, g5 << 3, b5 << 3)


def decode(r8: int, g8: int, b8: int):
    v = (r8 >> 3) | ((g8 >> 3) << 5) | ((b8 >> 3) << 10)
    return v // 128, (v % 128) // 8, v % 8


def main() -> int:
    if T.exists():
        shutil.rmtree(T, ignore_errors=True)
    T.mkdir(parents=True)
    subprocess.check_call(["rsync", "-a", "--exclude", "build", "--exclude", ".git", "--exclude", "vendor", "--exclude", ".venv",
                           "--exclude", ".tools", "--exclude", "rom", "--exclude", "dist", "--exclude", "telemetry", str(ROOT) + "/", str(T) + "/"])
    for d in ("vendor", ".venv", ".tools", "rom"):
        (T / d).symlink_to(ROOT / d)
    (T / "build").mkdir()
    groups: list[str] = []
    for f in sorted((T / "gfx" / "src" / "palettes").glob("*.yaml")):
        y = yaml.safe_load(f.read_text())
        for name, g in y["groups"].items():
            gi = len(groups) + 1
            groups.append(f"{f.name}:{name}")
            g["colours"] = [[encode(gi, r, j + 1) if len(row) == 7 else encode(gi, r, j) for j in range(len(row))] for r, row in enumerate(g["colours"])]
        f.write_text(yaml.safe_dump(y, sort_keys=False))
    (T / "groups.json").write_text(json.dumps(groups))
    subprocess.check_call([str(T / ".venv/bin/python"), "tools/roomgen.py"], cwd=T, stdout=subprocess.DEVNULL)
    r = subprocess.run([str(T / ".venv/bin/python"), "tools/build.py", "build"], cwd=T)
    print(f"{len(groups)} palette groups coded")
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
