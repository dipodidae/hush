#!/usr/bin/env python3
"""Unit test: the smooth light tiles, design/lighting.md section 4 (revision 2) + section 5 "Offline" sentence.

Run: .venv/bin/python tests/unit/test_light_tiles.py   (tests/unit/test_autotile.py main() runs it too, so `make test` does; exit 1 on failure)

EXPECTED ENGINE EXPORT (tools/autotile.py; the engine owns that file, names fixed here so the test can be written first):
  LIGHT_N   int  amber corner levels N (lighting.md 4.1: N >= 5)
  LIGHT_K   int  amber ramp size K incl. r0 = none (4.2: r0 + at least 4 amber colours -> K >= 5)
  LIGHT_NV  int  violet glow corner levels (4.3: at least 3 -> 0, 1, 2)
  LIGHT_KV  int  violet ramp size incl. none (4.3: at least 2 colours plus none -> KV >= 3)
  light_tiles() -> list of dicts, one per STORED (unflipped) BG1 light tile:
        {"tile": int  BG1 tile id (bits 0-9 of the tile word),
         "kind": "empty" | "amber" | "violet",
         "corners": (a, b, c, d)   levels of the unflipped tile: a top-left, b top-right, c bottom-left, d bottom-right,
         "px": 8 x 8 list (rows y = 0..7 of columns x = 0..7) of RAMP indices (0 = r0 none .. K-1 amber, 0 .. KV-1 violet)}
  light_word(kind, corners) -> int  the BG1 tile word (tile id | palette row << 10 | H flip 0x4000 | V flip 0x8000) the engine shows for
        that corner tuple; kind "amber" or "violet". Must resolve every tuple listed under "completeness" below (KeyError = unsupported).
  (the same data goes to build/rooms_gen.lua `light = {...}` for tests/smoke/lighting.lua, see that file's header)

Checks (each line cites the spec):
  * parameters: N >= 5, K >= 5, NV >= 3, KV >= 3                                                         (4.1, 4.2, 4.3)
  * every stored tile's px == the 4.2 formula for its corners: bilinear L, p = L (K-1)/(N-1), 4x4 Bayer B, r(lo+1) iff f > (B+0.5)/16
    (violet: the same with NV, KV, 4.3 "same lattice and interpolation (4.1, 4.2)")                       (4.2, 4.3, 5 "Offline")
  * every tile with a corner level >= 1 has a non-r0 pixel                                               (4.2 "Step 1 ... stays faintly visible", 5)
  * an all-zero tile is all r0 (the light only adds, the unlit room is untouched)                         (4.2 "never darkens", 4.3 "Else, the empty tile")
  * completeness: light_word() resolves (up to H/V flip, 4.2 "flips may be used") to a stored tile of that kind whose flipped corners equal
    the request, for EVERY corner tuple the 4.1 lattice can produce:
      amber: all 7^4 value combinations of the 4 cells around a tile corner (cell itself, its horizontal / vertical / diagonal neighbour;
             steps 0..6, cells outside the grid count 0), in all 4 quarter orientations, with Q(v) = floor(v (N-1)/6 + 1/2), any level > 0
             (section 5: "at every ... lattice point the shown level is exactly Q"; the rules allow any neighbour pattern: walls, faces,
             several guards, the ink cloud);
      violet: every tuple produced by the glow rule of section 3 (Link's cell 2, orthogonal floor neighbours 1, solid cells 0) on any
             2x2 cell block with any solidity and any Link position, Qv(v) = floor(v (NV-1)/2 + 1/2)  <- ASSUMPTION: lighting.md 4.3 gives
             violet "its own levels (at least 3: 0, 1, 2)" but no formula; this is the 4.1 formula with the violet maximum 2 instead of 6.
    (rev 4: amber is never displaced, so every amber tuple the 4.1 lattice makes must still be STORED, not substituted)
  * light_lut(kind) (4.5 item 4, section 5 "In-emulator"): all n^4 tuples; stored tuples show themselves, the rest show the stored
    orientation minimizing E(t, s) (ties: larger corner sum, then smaller tuple), never empty when a corner >= 1; light_shown() agrees
  * not checked here: the palette row of the word (art / engine own the slot) and the pixel -> CGRAM index mapping; the in-emulator
    test (tests/smoke/lighting.lua) checks the exported ramp colours in CGRAM.
Also prints the number of distinct amber tuples for N = 5, 6, 7 (to help the engine pick N).
"""
from __future__ import annotations

import itertools
import math
import sys
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import autotile as A  # noqa: E402

FAILS: list[str] = []
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]     # lighting.md 4.2


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def Q(total: int, den: int, n: int, vmax: int) -> int:
    """lighting.md 4.1: Q(v) = floor(v * (N - 1) / 6 + 0.5) with v = total / den (exact rational arithmetic); vmax 6 amber, 2 violet."""
    return math.floor(F(total, den) * (n - 1) / vmax + F(1, 2))


def formula_px(corners, n: int, k: int):
    """lighting.md 4.2, exact."""
    a, b, c, d = corners
    out = []
    for y in range(8):
        row = []
        for x in range(8):
            u, w = F(2 * x + 1, 16), F(2 * y + 1, 16)
            L = a * (1 - u) * (1 - w) + b * u * (1 - w) + c * (1 - u) * w + d * u * w
            p = L * (k - 1) / (n - 1)
            lo = math.floor(p)
            f = p - lo
            row.append(lo + 1 if f > F(2 * BAYER[y % 4][x % 4] + 1, 32) else lo)
        out.append(row)
    return out


def hflip(t):
    a, b, c, d = t
    return (b, a, d, c)


def vflip(t):
    a, b, c, d = t
    return (c, d, a, b)


def orientations(t):
    return {t, hflip(t), vflip(t), hflip(vflip(t))}


def nw_tuple(C, H, V, D, n, vmax):
    """Corner levels of the NW quarter tile of cell C (H = west, V = north, D = north-west neighbour), lighting.md 4.1:
    a = cell corner (avg of 4), b = top edge midpoint (C, V), c = left edge midpoint (C, H), d = cell centre C."""
    return (Q(C + H + V + D, 4, n, vmax), Q(C + V, 2, n, vmax), Q(C + H, 2, n, vmax), Q(C, 1, n, vmax))


def amber_tuples(n):
    out = set()
    for C, H, V, D in itertools.product(range(7), repeat=4):
        t = nw_tuple(C, H, V, D, n, 6)
        if max(t) > 0:
            out |= orientations(t)
    return out


def violet_tuples(nv):
    """Every 2x2 block (cells 0 = C, 1 = H, 2 = V, 3 = D at block coords (1,1), (0,1), (1,0), (0,0)), any solidity, Link anywhere near."""
    pos = {0: (1, 1), 1: (0, 1), 2: (1, 0), 3: (0, 0)}
    out = set()
    for solid in range(16):
        for lx in range(-2, 4):
            for ly in range(-2, 4):
                vals = []
                for i in range(4):
                    x, y = pos[i]
                    if solid >> i & 1:
                        vals.append(0)
                    elif (x, y) == (lx, ly):
                        vals.append(2)
                    elif abs(x - lx) + abs(y - ly) == 1:
                        vals.append(1)
                    else:
                        vals.append(0)
                # Link cannot stand in a solid cell: skip blocks where Link's cell is in the block and solid
                if (lx, ly) in pos.values() and solid >> [i for i in pos if pos[i] == (lx, ly)][0] & 1:
                    continue
                t = nw_tuple(*vals, nv, 2)
                if max(t) > 0:
                    out |= orientations(t)
    return out


REQUIRED = ("LIGHT_N", "LIGHT_K", "LIGHT_NV", "LIGHT_KV", "light_tiles", "light_word")


def test_export_present():
    missing = [x for x in REQUIRED if not hasattr(A, x)]
    check(not missing, "engine export missing in tools/autotile.py (lighting.md 4 not built yet): " + ", ".join(missing))
    return not missing


def test_parameters():
    check(A.LIGHT_N >= 5, f"LIGHT_N = {A.LIGHT_N} < 5 (lighting.md 4.1 'N >= 5')")
    check(A.LIGHT_K >= 5, f"LIGHT_K = {A.LIGHT_K} < 5 (4.2: r0 + at least 4 amber colours)")
    check(A.LIGHT_NV >= 3, f"LIGHT_NV = {A.LIGHT_NV} < 3 (4.3: at least 3 levels)")
    check(A.LIGHT_KV >= 3, f"LIGHT_KV = {A.LIGHT_KV} < 3 (4.3: at least 2 colours plus none)")
    n = A.LIGHT_N
    check(Q(0, 1, n, 6) == 0 and Q(1, 1, n, 6) >= 1 and Q(6, 1, n, 6) == n - 1, "Q properties of 4.1")


def test_tile_pixels():
    tiles = A.light_tiles()
    check(len(tiles) > 0, "light_tiles() is empty")
    ids = [t["tile"] for t in tiles]
    check(len(ids) == len(set(ids)), "light_tiles(): duplicate tile ids")
    nz = 0
    for t in tiles:
        kind, cor, px = t["kind"], tuple(t["corners"]), [list(r) for r in t["px"]]
        name = f"light tile {t['tile']:#x} {kind} {cor}"
        check(kind in ("empty", "amber", "violet"), f"{name}: unknown kind")
        check(len(px) == 8 and all(len(r) == 8 for r in px), f"{name}: px is not 8x8")
        if kind == "empty" or max(cor) == 0:
            check(max(cor) == 0, f"{name}: 'empty' tile with non-zero corners")
            check(all(v == 0 for r in px for v in r), f"{name}: all-zero corners but a non-r0 pixel (the light must only add)")
            continue
        n, k = (A.LIGHT_N, A.LIGHT_K) if kind == "amber" else (A.LIGHT_NV, A.LIGHT_KV)
        check(all(0 <= v < n for v in cor), f"{name}: corner level outside 0..{n - 1}")
        want = formula_px(cor, n, k)
        if px != want:
            diff = [(x, y, px[y][x], want[y][x]) for y in range(8) for x in range(8) if px[y][x] != want[y][x]]
            FAILS.append(f"{name}: {len(diff)} pixels differ from the 4.2 formula, first (x, y, got, want) {diff[:3]}")
        if max(cor) >= 1:
            check(any(v != 0 for r in px for v in r), f"{name}: a corner level >= 1 but every pixel is r0 (4.2 step 1 stays visible)")
            nz += 1
    print(f"     {len(tiles)} stored light tiles ({nz} non-empty) checked against the 4.2 formula")


def _resolve(by_id, kind, cor):
    try:
        w = A.light_word(kind, cor)
    except KeyError:
        return f"light_word('{kind}', {cor}) unsupported (KeyError)"
    t = by_id.get(w & 0x3FF)
    if t is None:
        return f"light_word('{kind}', {cor}) = {w:#06x}: tile id {w & 0x3FF:#x} is not in light_tiles()"
    shown = tuple(t["corners"])
    if w & 0x4000:
        shown = hflip(shown)
    if w & 0x8000:
        shown = vflip(shown)
    if t["kind"] != kind or shown != tuple(cor):
        return f"light_word('{kind}', {cor}) = {w:#06x} shows {t['kind']} {shown} (stored {tuple(t['corners'])}, flips h={w >> 14 & 1} v={w >> 15 & 1})"
    return None


def test_completeness():
    by_id = {t["tile"]: t for t in A.light_tiles()}
    for kind, tuples in (("amber", amber_tuples(A.LIGHT_N)), ("violet", violet_tuples(A.LIGHT_NV))):
        bad = [m for m in (_resolve(by_id, kind, c) for c in sorted(tuples)) if m]
        for m in bad[:6]:
            FAILS.append(m)
        if len(bad) > 6:
            FAILS.append(f"{kind}: ... {len(bad) - 6} more unresolved corner tuples ({len(bad)} of {len(tuples)})")
        print(f"     {kind}: {len(tuples)} reachable corner tuples, {len(tuples) - len(bad)} resolved")


def _metric():
    """M with sum over the 64 tile pixels of (L_t - L_s)^2 * 256^2 = d^T M d, d = t - s (lighting.md 4.2: L is linear in the corners,
    pixel weights (1-u)(1-w), u(1-w), (1-u)w, uw with u = (2x+1)/16, w = (2y+1)/16, here in 1/256 units)."""
    m = [[0] * 4 for _ in range(4)]
    for y in range(8):
        for x in range(8):
            u, w = 2 * x + 1, 2 * y + 1
            wt = ((16 - u) * (16 - w), u * (16 - w), (16 - u) * w, u * w)
            for i in range(4):
                for j in range(4):
                    m[i][j] += wt[i] * wt[j]
    return m


def test_lut_substitutes():
    """lighting.md 4.5 item 4 + section 5 "In-emulator": light_lut(kind) (exported as light.lut_amber / lut_violet, the in-emulator oracle's
    reference) maps EVERY corner tuple ((a*n + b)*n + c)*n + d to a word that shows: the empty tile for (0,0,0,0); the tuple itself if a
    stored tile shows it in any H/V flip; else the stored orientation s minimizing E(t, s) = sum (L_t - L_s)^2 over the 64 pixels, ties ->
    larger corner sum, then the lexicographically smaller tuple; never empty when a corner >= 1. Also light_shown() agrees with the LUT."""
    if not hasattr(A, "light_lut"):
        FAILS.append("tools/autotile.py has no light_lut (lighting.md 4.5 item 4 / section 5: the exported corner LUTs)")
        return
    tiles = A.light_tiles()
    by_id = {t["tile"]: t for t in tiles}
    m = _metric()
    for kind, n in (("amber", A.LIGHT_N), ("violet", A.LIGHT_NV)):
        stored = sorted({o for t in tiles if t["kind"] == kind for o in orientations(tuple(t["corners"]))})
        lut = A.light_lut(kind)
        if len(lut) != n ** 4:
            FAILS.append(f"light_lut('{kind}') has {len(lut)} entries, want n^4 = {n ** 4}")
            continue
        bad, subst = [], 0
        for t in itertools.product(range(n), repeat=4):
            idx = ((t[0] * n + t[1]) * n + t[2]) * n + t[3]
            w = lut[idx]
            e = by_id.get(w & 0x3FF)
            if e is None:
                bad.append(f"{kind} {t}: word {w:#06x} is not a stored tile")
                continue
            shown = tuple(e["corners"])
            if w & 0x4000:
                shown = hflip(shown)
            if w & 0x8000:
                shown = vflip(shown)
            if max(t) == 0:
                if max(shown) != 0:
                    bad.append(f"{kind} {t}: all-zero tuple shows {e['kind']} {shown}, want the empty tile")
                continue
            if e["kind"] != kind or max(shown) == 0:
                bad.append(f"{kind} {t}: shows {e['kind']} {shown} (a tuple with a corner >= 1 is never drawn empty / of another kind)")
                continue
            if t in stored:
                want = t
            else:
                subst += 1
                best = None
                for s in stored:
                    d = [t[i] - s[i] for i in range(4)]
                    err = sum(m[i][j] * d[i] * d[j] for i in range(4) for j in range(4))
                    key = (err, -sum(s), s)
                    if best is None or key < best:
                        best = key
                want = best[2]
            if shown != want:
                bad.append(f"{kind} {t}: LUT shows {shown}, the 4.5 substitute rule says {want}")
            if hasattr(A, "light_shown") and tuple(A.light_shown(kind, t)) != shown:
                bad.append(f"{kind} {t}: light_shown() = {tuple(A.light_shown(kind, t))} but the LUT word shows {shown}")
        FAILS.extend(bad[:6])
        if len(bad) > 6:
            FAILS.append(f"{kind}: ... {len(bad) - 6} more LUT entries wrong ({len(bad)} of {n ** 4})")
        print(f"     {kind} LUT: {n ** 4} tuples, {subst} via the 4.5 substitute rule, {len(bad)} wrong")


def info_counts():
    for n in (5, 6, 7):
        ts = amber_tuples(n)
        canon = {min(orientations(t)) for t in ts}
        print(f"     info: N = {n}: {len(ts)} distinct amber corner tuples, {len(canon)} up to H/V flip (+1 empty tile)")
    for nv in (3,):
        ts = violet_tuples(nv)
        print(f"     info: NV = {nv}: {len(ts)} violet tuples, {len({min(orientations(t)) for t in ts})} up to H/V flip")


def main() -> int:
    info_counts()
    n0 = len(FAILS)
    ok = test_export_present()
    print(f"{'ok  ' if len(FAILS) == n0 else 'FAIL'} test_export_present")
    if ok:
        for fn in (test_parameters, test_tile_pixels, test_completeness, test_lut_substitutes):
            n0 = len(FAILS)
            fn()
            print(f"{'ok  ' if len(FAILS) == n0 else 'FAIL'} {fn.__name__}")
    else:
        for fn in ("test_parameters", "test_tile_pixels", "test_completeness", "test_lut_substitutes"):
            print(f"FAIL {fn} (not run: no export)")
    for m in FAILS[:30]:
        print("  -", m)
    if len(FAILS) > 30:
        print(f"  ... {len(FAILS) - 30} more")
    print("unit light tiles (lighting.md 4):", "FAILED" if FAILS else "passed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
