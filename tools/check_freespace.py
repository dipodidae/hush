#!/usr/bin/env python3
"""Enforce src/FREESPACE.md.

Static check (always):
  * ledger rows parse, are inside the 1 MiB LoROM, and do not overlap;
  * every `org` in src/**/*.asm is a literal $BBAAAA inside a ledger region;
  * automatic allocation (freecode/freedata/freespace/autoclean) is banned.

--rom check (after asar):
  * every byte that differs between rom/vanilla.sfc and build/hush.sfc lies
    inside a ledger region.

Exit 0 = clean, 1 = violation.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (  # noqa: E402
    BUILT_ROM, FREESPACE_MD, ROOT, SRC_DIR, VANILLA, VANILLA_SIZE, pc_to_snes, snes_to_pc,
)

ROW = re.compile(
    r"^\|\s*\$([0-9A-Fa-f]{6})\s*\|\s*\$([0-9A-Fa-f]{6})\s*\|\s*(free|hook)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*$"
)
ORG = re.compile(r"^\s*(?:[A-Za-z_][\w.]*:\s*)?org\s+(\S+)", re.IGNORECASE)
BANNED = re.compile(r"^\s*(freecode|freedata|freespace|autoclean|prot)\b", re.IGNORECASE)
LITERAL = re.compile(r"^\$([0-9A-Fa-f]{6})$")


class Region:
    def __init__(self, start: int, end: int, kind: str, owner: str, purpose: str):
        self.start, self.end, self.kind, self.owner, self.purpose = start, end, kind, owner, purpose
        self.pc_start, self.pc_end = snes_to_pc(start), snes_to_pc(end)

    def __repr__(self) -> str:
        return f"${self.start:06X}-${self.end:06X} ({self.kind}, {self.owner})"


def load_ledger(errors: list[str]) -> list[Region]:
    if not FREESPACE_MD.exists():
        errors.append("src/FREESPACE.md is missing")
        return []
    regions: list[Region] = []
    for lineno, line in enumerate(FREESPACE_MD.read_text().splitlines(), 1):
        if not line.startswith("|") or re.match(r"^\|\s*(Start|-)", line):
            continue
        m = ROW.match(line)
        if not m:
            errors.append(
                f"FREESPACE.md:{lineno}: unparseable row (need | $BBAAAA | $BBAAAA | free/hook | file | purpose |): {line}"
            )
            continue
        s, e = int(m.group(1), 16), int(m.group(2), 16)
        try:
            r = Region(s, e, m.group(3), m.group(4), m.group(5))
        except ValueError as ex:
            errors.append(f"FREESPACE.md:{lineno}: {ex}")
            continue
        if r.pc_end < r.pc_start:
            errors.append(f"FREESPACE.md:{lineno}: end before start: {r}")
        elif r.pc_end >= VANILLA_SIZE:
            errors.append(f"FREESPACE.md:{lineno}: region beyond 1 MiB ROM: {r}")
        else:
            regions.append(r)
    ordered = sorted(regions, key=lambda r: r.pc_start)
    for a, b in zip(ordered, ordered[1:]):
        if b.pc_start <= a.pc_end:
            errors.append(f"FREESPACE.md: regions overlap: {a} and {b}")
    return regions


def find_region(regions: list[Region], pc: int) -> Region | None:
    for r in regions:
        if r.pc_start <= pc <= r.pc_end:
            return r
    return None


def check_orgs(regions: list[Region], errors: list[str]) -> int:
    count = 0
    for path in sorted(SRC_DIR.rglob("*.asm")):
        rel = path.relative_to(ROOT)
        for lineno, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.split(";", 1)[0]
            if BANNED.match(line):
                errors.append(f"{rel}:{lineno}: automatic allocation is banned ({line.strip()}); use `org` + a ledger row")
                continue
            m = ORG.match(line)
            if not m:
                continue
            count += 1
            arg = m.group(1).strip()
            lit = LITERAL.match(arg)
            if not lit:
                errors.append(f"{rel}:{lineno}: `org {arg}` must be a literal $BBAAAA address so it can be checked")
                continue
            addr = int(lit.group(1), 16)
            try:
                pc = snes_to_pc(addr)
            except ValueError as ex:
                errors.append(f"{rel}:{lineno}: {ex}")
                continue
            if find_region(regions, pc) is None:
                errors.append(f"{rel}:{lineno}: `org ${addr:06X}` is outside every region in src/FREESPACE.md")
    return count


def check_rom_diff(regions: list[Region], errors: list[str]) -> int:
    if not BUILT_ROM.exists():
        errors.append("build/hush.sfc missing; cannot diff")
        return 0
    a, b = VANILLA.read_bytes(), BUILT_ROM.read_bytes()
    if len(b) != len(a):
        errors.append(f"built ROM is {len(b)} bytes; vanilla is {len(a)}. ROM expansion needs a spec + ledger change first")
        n = min(len(a), len(b))
    else:
        n = len(a)
    changed = 0
    i = 0
    reported = 0
    while i < n:
        if a[i] == b[i]:
            i += 1
            continue
        j = i
        while j < n and a[j] != b[j]:
            j += 1
        changed += j - i
        # The whole run must be inside one region.
        r = find_region(regions, i)
        if r is None or j - 1 > r.pc_end:
            if reported < 10:
                errors.append(
                    f"ROM bytes ${pc_to_snes(i):06X}-${pc_to_snes(j - 1):06X} ({j - i} bytes) changed outside any FREESPACE.md region"
                )
            reported += 1
        i = j
    if reported > 10:
        errors.append(f"... and {reported - 10} more out-of-ledger runs")
    return changed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", action="store_true", help="also diff vanilla vs build/hush.sfc")
    args = ap.parse_args()

    errors: list[str] = []
    regions = load_ledger(errors)
    orgs = check_orgs(regions, errors)
    msg = f"freespace: {len(regions)} region(s), {orgs} org(s) checked"
    if args.rom:
        changed = check_rom_diff(regions, errors)
        msg += f", {changed} changed byte(s) diffed"
    if errors:
        print("FREESPACE CHECK FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(msg + ": ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
