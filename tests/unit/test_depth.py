#!/usr/bin/env python3
"""Unit test: the depth rule, design/tiles.md section 2.1 (revision 4) + acceptance criterion 7.10 (first sentence).

Run: .venv/bin/python tests/unit/test_depth.py   (tests/unit/test_autotile.py main() runs it too, so `make test` does; exit 1 on failure)

Oracle, written from tiles.md 2.1 only (independent of tools/autotile.py's PRIO table):
  bit 13 (BG priority) of the tile word of quarter (c, r, qx, qy) is 1  iff
      qy == 0 (NW / NE quarter)                                   -- 2.1 rule 1 "the two top quarters (NW, NE)"
  and grid[r][c] in '#p'                                          -- 2.1 rule 1 "a solid mass cell: # or p"
  and r > 0                                                       -- 2.1 rule 2 "room-edge cells in row 0" -> 0
  and grid[r - 1][c] not in '#pOW'                                -- 2.1 rule 1 "the cell directly above C is inside the grid and not solid"
  else 0 (SW / SE incl. the face strip, deep roof, row 0, D, floor, X, O, W: 2.1 rule 2).

Checked over the BUILD path (tools/roomgen.py compile_room -> r["chars"] -> tools/autotile.py char_word, i.e. the words that go into
build/rooms_gen.asm / the $7E2000 buffer) for every room in design/rooms (21) and the gallery (tests/dev/rooms/gallery.yaml), and over
A.place() on 300 random grids (decoration variants included: "the bit follows the quarter's position, not its art").
No engine export needed beyond what exists (autotile.place / char_word, roomgen.compile_room).
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import autotile as A  # noqa: E402
import roomgen  # noqa: E402

FAILS: list[str] = []
SOLID = set("#pOW")


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def depth_oracle(g, c, r, qx, qy) -> int:
    """tiles.md 2.1 rule 1 / rule 2, per 8x8 quarter."""
    return 1 if (qy == 0 and g[r][c] in "#p" and r > 0 and g[r - 1][c] not in SOLID) else 0


def _check_chars(name, g, chars, stats):
    bad = 0
    for r in range(14):
        for c in range(16):
            for qy in (0, 1):
                for qx in (0, 1):
                    w = A.char_word(chars[2 * r + qy][2 * c + qx])
                    got, want = (w >> 13) & 1, depth_oracle(g, c, r, qx, qy)
                    if got != want:
                        bad += 1
                        if bad <= 6:
                            above = g[r - 1][c] if r > 0 else "(outside)"
                            FAILS.append(f"{name} cell ({c},{r}) '{g[r][c]}' above '{above}' quarter {'NS'[qy]}{'WE'[qx]}: "
                                         f"priority {got}, tiles.md 2.1 says {want}")
                    if want:
                        stats["p1"] += 1
                        stats["p1_" + g[r][c]] = stats.get("p1_" + g[r][c], 0) + 1
                    else:
                        stats["p0"] += 1
                    if g[r][c] == "D":
                        stats["door_q"] += 1
    if bad > 6:
        FAILS.append(f"{name}: ... {bad - 6} more priority mismatches ({bad} of 896 quarters)")
    return bad


def test_rooms_build_path():
    """All design rooms + the gallery, through roomgen.compile_room (the data the ROM gets)."""
    specs = roomgen.load_specs(ROOT / "design" / "rooms") + roomgen.load_specs(ROOT / "tests" / "dev" / "rooms")
    stats = {"p1": 0, "p0": 0, "door_q": 0}
    rooms_bad = []
    for s in specs:
        r = roomgen.compile_room(s, 0, 0)
        if _check_chars(s["id"], s["grid"], r["chars"], stats):
            rooms_bad.append(s["id"])
    ids = {s["id"] for s in specs}
    check("gallery" in ids, "the gallery room (tests/dev/rooms/gallery.yaml) was not loaded")
    check(len(roomgen.load_specs(ROOT / "design" / "rooms")) == 21, "expected the 21 design rooms (tiles.md 7.10 'all 21 rooms')")
    # non-vacuity: the rule really selects quarters of both kinds (walls with open floor above, pillars, doors)
    check(stats["p1"] > 100, f"only {stats['p1']} priority-1 quarters expected over all rooms: the oracle is not exercised")
    check(stats.get("p1_p", 0) > 0, "no pillar top quarter with priority 1 expected: pillar case not exercised")
    check(stats.get("p1_#", 0) > 0, "no wall top quarter with priority 1 expected: wall case not exercised")
    check(stats["door_q"] > 0, "no door quarters in any room: the D case is not exercised")
    print(f"     rooms: {len(specs)} ({', '.join(sorted(rooms_bad)) or 'none'} with mismatches); expected priority 1: {stats['p1']} quarters "
          f"(# {stats.get('p1_#', 0)}, p {stats.get('p1_p', 0)}), priority 0: {stats['p0']}")


def test_random_grids():
    """A.place() on random grids (all cell kinds, decoration on): the bit follows the quarter's position (2.1 rule 1, last sentence)."""
    rnd = random.Random(2026_11_23)
    stats = {"p1": 0, "p0": 0, "door_q": 0}
    for t in range(300):
        g = [["#"] * 16 for _ in range(14)]
        for r in range(1, 13):
            for c in range(1, 15):
                g[r][c] = rnd.choice("..#.#pOWDX.a#p")
        g = ["".join(r) for r in g]
        chars, _ = A.place("rnd%d" % t, g, bool(t & 1))
        if _check_chars(f"random grid {t}", g, chars, stats) and len(FAILS) > 30:
            return


def main() -> int:
    for fn in (test_rooms_build_path, test_random_grids):
        n0 = len(FAILS)
        fn()
        print(f"{'ok  ' if len(FAILS) == n0 else 'FAIL'} {fn.__name__}")
    for m in FAILS[:30]:
        print("  -", m)
    if len(FAILS) > 30:
        print(f"  ... {len(FAILS) - 30} more")
    print("unit depth (tiles.md 2.1):", "FAILED" if FAILS else "passed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
