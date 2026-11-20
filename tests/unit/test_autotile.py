#!/usr/bin/env python3
"""Unit tests for the T0 autotile (design/tiles.md). Run: .venv/bin/python tests/unit/test_autotile.py   (make test runs it; exit 1 on failure)

Contract pinned here:
  * tools/autotile.py autotile(grid) -> {(c, r, qx, qy): (surface, class, tile_name)} follows design/tiles.md 3.1-3.3. The ORACLE below is written from the
    spec text as an explicit per-corner table (independent of the implementation's cls_of formula) and checked over all 256 neighbour patterns of a cell.
  * autotile is total + deterministic over random valid grids (incl. D / O / W);
  * collision (solid_cells, char solidity) = grid: '#' 'p' 'O' 'W' solid;
  * the gallery room (tests/dev/rooms/gallery.yaml) covers every expected (surface, quarter, class) + the face cases + door / pillar / exit;
  * the ROM data form round-trips: the RLE + cell dictionary decode (a Python mimic of src/hooks/roomload.asm Hush_Blit) to the autotile words;
  * seam sanity (the weak form of tiles.md section 4): interior floor quarters are slices of one periodic brick pattern, BRICK alternates A/B, interior roof is uniform;
  * budgets: <= 192 unique 8x8 cells (3 sheets x 64), <= 255 chars, cell dictionary <= 255.
"""
from __future__ import annotations

import itertools
import random
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import autotile as A  # noqa: E402
import roomgen  # noqa: E402

FAILS: list[str] = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def pad(cells: dict, base="#") -> list[str]:
    """14x16 grid of `base` with the given {(c, r): ch}."""
    g = [[base] * 16 for _ in range(14)]
    for (c, r), ch in cells.items():
        g[r][c] = ch
    return ["".join(r) for r in g]


# ---------------------------------------------------------------------------------------------------------------- oracle (spec 3.1, per corner)
def oracle_corner(v_joined, h_joined, d_joined):
    """Explicit table: which tile shape does a quarter get, from the three neighbours it touches (True = same surface continues)."""
    table = {
        (True, True, True): "FILL", (True, True, False): "INNER",
        (False, True, True): "V_EDGE", (False, True, False): "V_EDGE",
        (True, False, True): "H_EDGE", (True, False, False): "H_EDGE",
        (False, False, True): "OUTER", (False, False, False): "OUTER",
    }
    return table[(v_joined, h_joined, d_joined)]


NB = {"NW": (-1, -1), "NE": (1, -1), "SW": (-1, 1), "SE": (1, 1)}
QXY = {"NW": (0, 0), "NE": (1, 0), "SW": (0, 1), "SE": (1, 1)}


def test_blob_patterns():
    """All 256 patterns of the 8 neighbours of a centre cell (15, 11 are interior so the neighbours exist): wall roof, floor, pit, water."""
    cx, cy = 8, 7
    n = 0
    for bits in range(256):
        offs = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        other = {(cx + dx, cy + dy) for i, (dx, dy) in enumerate(offs) if bits >> i & 1}
        # wall roof: centre '#', 'other' neighbours are floor ('.') -> the roof edge faces them; a floor cell SOUTH makes the bottom quarters FACE quarters (tested separately)
        if not any(o in other for o in ((cx, cy + 1), (cx - 1, cy + 1), (cx + 1, cy + 1))):
            g = pad({**{o: "." for o in other}, (cx, cy): "#"})
            res = A.autotile(g)
            for qp, (dx, dy) in NB.items():
                v, h, d = (cx, cy + dy), (cx + dx, cy), (cx + dx, cy + dy)
                want = oracle_corner(v not in other, h not in other, d not in other)
                s, cl, name = res[(cx, cy, *QXY[qp])]
                check(s == "roof" and cl == want, f"roof pattern {bits:08b} {qp}: got {s}/{cl}, want roof/{want}")
        # floor: centre '.', 'other' neighbours are walls -> shade toward them
        g = pad({**{o: "#" for o in other}, (cx, cy): "."}, base=".")
        res = A.autotile(g)
        for qp, (dx, dy) in NB.items():
            v, h, d = (cx, cy + dy), (cx + dx, cy), (cx + dx, cy + dy)
            want = oracle_corner(v not in other, h not in other, d not in other)
            s, cl, name = res[(cx, cy, *QXY[qp])]
            check(s == "floor" and cl == want, f"floor pattern {bits:08b} {qp}: got {s}/{cl}, want floor/{want}")
        # pit / water: centre basin; 'other' neighbours are floor. A wall next to a basin counts as joined (hides the interior), tested by the 3rd case below
        for ch, surf in (("O", "pit"), ("W", "water")):
            g = pad({**{o: "." for o in other}, (cx, cy): ch}, base=ch if False else "#")
            # surround by floor-less area: make everything around the basin that is not 'other' the same basin so only `other` breaks the surface
            full = {(cx + dx, cy + dy): ch for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
            full.update({o: "." for o in other})
            g = pad(full, base="#")
            res = A.autotile(g)
            for qp, (dx, dy) in NB.items():
                v, h, d = (cx, cy + dy), (cx + dx, cy), (cx + dx, cy + dy)
                want = oracle_corner(v not in other, h not in other, d not in other)
                s, cl, name = res[(cx, cy, *QXY[qp])]
                check(s == surf and cl == want, f"{surf} pattern {bits:08b} {qp}: got {s}/{cl}, want {surf}/{want}")
        n += 1
    check(n == 256, "pattern loop")


def test_face_cases():
    """tiles.md 3.3: wall cell with an open cell south; (h, d) per bottom quarter. Wall row at r=6 (c=5..9), floor below."""
    # h = WALL, d = open -> BRICK ; h = open -> END_CAP ; h = WALL, d = WALL -> FACE_INNER
    g = pad({**{(c, 6): "#" for c in range(5, 10)}, **{(c, 7): "." for c in range(4, 11)}, (7, 7): "#"}, base=".")
    res = A.autotile(g)
    # cell (6,6): SE quarter: h = east (7,6) wall, d = (7,7) wall -> FACE_INNER ; SW quarter: h = (5,6) wall, d = (5,7) floor -> BRICK
    check(res[(6, 6, 1, 1)][1] == "FACE_INNER", f"face h=WALL d=WALL: {res[(6, 6, 1, 1)]}")
    check(res[(6, 6, 0, 1)][1] == "BRICK", f"face h=WALL d=open: {res[(6, 6, 0, 1)]}")
    # cell (5,6): SW quarter: h = (4,6) open floor, d = (4,7) open -> END_CAP
    check(res[(5, 6, 0, 1)][1] == "END_CAP", f"face h=open d=open: {res[(5, 6, 0, 1)]}")
    # h = open, d = WALL (a floor cell beside a wall that stands on top of a wall below it): END_CAP reused
    g2 = pad({(5, 6): "#", (4, 6): ".", (4, 7): "#", (5, 7): "."}, base=".")
    res2 = A.autotile(g2)
    check(res2[(5, 6, 0, 1)][1] == "END_CAP", f"face h=open d=WALL: {res2[(5, 6, 0, 1)]}")
    check(all(res[(6, 6, qx, 1)][0] == "face" for qx in (0, 1)), "face surface")


def test_total_and_deterministic():
    rnd = random.Random(1234)
    for t in range(500):
        g = [["#"] * 16 for _ in range(14)]
        for r in range(2, 13):
            for c in range(1, 15):
                g[r][c] = rnd.choice("..#.#pOWDX.a")
        g = ["".join(r) for r in g]
        a, b = A.autotile(g), A.autotile(g)
        check(a == b, f"nondeterministic autotile (random grid {t})")
        check(len(a) == 14 * 16 * 4, f"autotile not total (random grid {t}): {len(a)} quarters")
        chars, plan = A.place("rnd%d" % t, g, bool(t & 1))
        check(len(chars) == 28 and all(len(r) == 32 for r in chars), "place() shape")
        check(A.place("rnd%d" % t, g, bool(t & 1)) == (chars, plan), "place() not deterministic")
        # collision = grid
        for r in range(14):
            for c in range(16):
                want = 1 if g[r][c] in "#pOW" else 0
                for qy in (0, 1):
                    for qx in (0, 1):
                        got = A.CHARS[chars[2 * r + qy][2 * c + qx]][4]
                        check(got == want, f"collision mismatch grid {t} cell ({c},{r}) '{g[r][c]}': {got} vs {want}")
        if FAILS:
            return


def load_room(path):
    d = yaml.safe_load(Path(path).read_text())
    return d["id"], d["grid"], d["lighting"] == "lit"


def test_collision_equals_old_rooms():
    """All shipped rooms: solid cells are exactly '#' and 'p' (the pre-T0 collision)."""
    for f in sorted((ROOT / "design" / "rooms").glob("[a-z]*.yaml")):
        rid, g, lit = load_room(f)
        chars, _ = A.place(rid, g, lit)
        for r in range(14):
            for c in range(16):
                want = 1 if g[r][c] in "#p" else 0
                got = {A.CHARS[chars[2 * r + qy][2 * c + qx]][4] for qy in (0, 1) for qx in (0, 1)}
                check(got == {want}, f"{rid} ({c},{r}) '{g[r][c]}': solidity {got}, old collision {want}")
        check(A.solid_cells(g) == {(c, r) for r in range(14) for c in range(16) if g[r][c] in "#p"}, f"{rid}: solid_cells")


def test_gallery_coverage():
    rid, g, lit = load_room(ROOT / "tests" / "dev" / "rooms" / "gallery.yaml")
    res = A.autotile(g)
    seen = {(s, qx, qy, cl) for (c, r, qx, qy), (s, cl, nm) in res.items()}
    classes = ("FILL", "V_EDGE", "H_EDGE", "OUTER", "INNER")
    for s in ("roof", "floor", "pit", "water"):
        for qx in (0, 1):
            for qy in (0, 1):
                for cl in classes:
                    if s == "roof" and qy == 1 and cl in ("V_EDGE", "OUTER"):
                        continue          # impossible by design: an open cell south turns the bottom quarters into FACE quarters (tiles.md 3.3)
                    check((s, qx, qy, cl) in seen, f"gallery lacks {s} quarter ({qx},{qy}) class {cl}")
    for cl in ("BRICK", "FACE_INNER", "END_CAP"):
        check(any(s == "face" and c == cl for (s, qx, qy, c) in seen), f"gallery lacks face {cl}")
    for s in ("door", "pillar", "exit"):
        check(any(x[0] == s for x in seen), f"gallery lacks {s}")


def test_rle_roundtrip():
    """Python mimic of Hush_Blit over the real roomgen data for every shipped room and the gallery."""
    specs = roomgen.load_specs(ROOT / "design" / "rooms") + roomgen.load_specs(ROOT / "tests" / "dev" / "rooms")
    for s in specs:
        r = roomgen.compile_room(s, 0, 0)
        r.update(index=0, song=0xFF, room_id=roomgen.ROOM_FIRST)
        asm, _ = roomgen.build_asm([r])
        # decode with the dictionary exactly as the asm does
        cdict = {}
        seq = []
        for line in asm.split("\n"):
            if line.startswith("    dw ") and "; cell " in line:
                words = [int(x.strip()[1:], 16) for x in line.split(";")[0][7:].split(",")]
                cdict[int(line.split("; cell ")[1])] = words
        rle = r["rle"] if "rle" in r else None
        check(rle is not None, "compile/build_asm did not store the RLE")
        if rle is None:
            continue
        out, i = [], 0
        while rle[i] != 0:
            out += [rle[i + 1]] * rle[i]
            i += 2
        check(len(out) == 224, f"{s['id']}: RLE decodes to {len(out)} cells")
        win = [[0] * 32 for _ in range(28)]
        for n, cid in enumerate(out):
            cy, cx = divmod(n, 16)
            w = cdict[cid]
            win[2 * cy][2 * cx], win[2 * cy][2 * cx + 1], win[2 * cy + 1][2 * cx], win[2 * cy + 1][2 * cx + 1] = w
        want = [[A.char_word(c) for c in row] for row in r["chars"]]
        check(win == want, f"{s['id']}: decoded window differs from the autotile words")


def test_seams():
    """Weak seam checks (tiles.md section 4, limitation: pixel-index identity only, not palette-row colour identity)."""
    floor = A.FLOOR
    for f in sorted((ROOT / "design" / "rooms").glob("[a-z]*.yaml")):
        rid, g, lit = load_room(f)
        px = A.autotile_px(g)
        for (c, r, qx, qy), q in px.items():
            if q.surface == "floor" and q.cls == "FILL":
                want = [row[qx * 8:qx * 8 + 8] for row in floor[qy * 8:qy * 8 + 8]]
                check(q.px == want, f"{rid} floor FILL ({c},{r},{qx},{qy}) is not a slice of the periodic brick pattern")
            if q.surface == "face" and q.cls == "BRICK":
                check(q.px == A.face_brick(qx), f"{rid} BRICK ({c},{r},{qx}) is not strip A/B by tile column parity")
            if q.surface == "roof" and q.cls == "FILL" and ".s" not in q.name[-3:] and not q.name.endswith(("s1", "s2", "s3")):
                check(all(v == 4 for row in q.px for v in row), f"{rid} plain roof FILL ({c},{r},{qx},{qy}) is not uniform")


def test_budgets():
    check(len(A.CELLS) <= 192, f"{len(A.CELLS)} unique 8x8 cells > 192 (3 sheets x 64)")
    check(len(A.CHARS) <= 255, f"{len(A.CHARS)} chars > 255")
    A.tile_types()          # asserts a cell is never both solid and walkable
    ids = {A.tile_id(c[0]) for c in A.CHARS}
    check(all(i < 64 or 128 <= i < 192 for i in ids), "tile ids must lie in the sheets that are loaded (GFX_00 ids 0-63, GFX_10 ids 128-191)")


def main() -> int:
    for fn in (test_blob_patterns, test_face_cases, test_total_and_deterministic, test_collision_equals_old_rooms, test_gallery_coverage,
               test_rle_roundtrip, test_seams, test_budgets):
        n0 = len(FAILS)
        fn()
        print(f"{'ok  ' if len(FAILS) == n0 else 'FAIL'} {fn.__name__}")
    for m in FAILS[:30]:
        print("  -", m)
    if len(FAILS) > 30:
        print(f"  ... {len(FAILS) - 30} more")
    print("unit autotile:", "FAILED" if FAILS else "passed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
