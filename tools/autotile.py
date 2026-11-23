#!/usr/bin/env python3
"""autotile: HUSH tile art + autotiler + char registry (design/tiles.md). The ONE source of truth for background tiles.

* Tiles are painted procedurally as 8x8 quarters with sheet indices 1-7 (index semantics of env_art.py: 1 deepest, 2 base, 3 lit,
  4 dark/mortar, 5 accent, 6 amber, 7 pale). Only original pixels; no vanilla data is read.
* `autotile(grid)`: pure neighbour-based result per cell quarter (design/tiles.md sections 1-3), no decoration.
* `place(rid, grid, lit)`: autotile + deterministic E5 decoration -> one CHAR per tile of the 32x28 window (section 4).
* The char registry (`CHARS`, `char_words()`, `TILE_TYPES`, `sheet_cells()`) is the global tileset the ROM carries:
  char byte -> tile word, tile id -> collision type, sheet cell -> pixels. Consumed by tools/roomgen.py and tools/art/autotile_art.py.
* Engine/QA contract: tests/unit/test_autotile.py pins autotile() against an independent oracle.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "art"))
import env_art  # noqa: E402
PAL = yaml.safe_load((ROOT / "gfx" / "src" / "palettes" / "bg_dungeon.yaml").read_text())["groups"]

W, H = 16, 14
ROW = {"floor": 3, "exit": 4, "pillar": 5, "face": 6, "roof": 7, "pit": 7, "water": 5, "door_top": 6, "door_bot": 3}
PRIO = {"floor": 0, "exit": 0, "pillar": 0, "face": 0, "roof": 0, "pit": 0, "water": 0, "door_top": 0, "door_bot": 0}
SOLID = {"roof", "face", "pit", "water", "pillar"}   # surfaces whose cells block Link / guards (design/tiles.md section 2)
SOLID_BASIN = {"O": "pit", "W": "water"}


# ------------------------------------------------------------------------------------------------------------------ helpers
def blank(w=8, h=8, v=0):
    return [[v] * w for _ in range(h)]


def hflip(t):
    return [r[::-1] for r in t]


def hsh(*a) -> float:
    d = hashlib.sha256("/".join(map(str, a)).encode()).digest()
    return int.from_bytes(d[:4], "big") / 0x100000000


def quarter(t16, qx, qy):
    return [r[qx * 8:qx * 8 + 8] for r in t16[qy * 8:qy * 8 + 8]]


def rim_depth(qx, qy, x, y, v_edge, h_edge, d_edge):
    """Distance (px) of pixel (x,y) of a quarter from the nearest 'open' side; None = interior. Rounds the outer corner."""
    dx = x if qx == 0 else 7 - x
    dy = y if qy == 0 else 7 - y
    ds = []
    if v_edge:
        ds.append(dy)
    if h_edge:
        ds.append(dx)
    if d_edge and not v_edge and not h_edge:
        ds.append(max(dx, dy))
    if not ds:
        return None
    d = min(ds)
    if v_edge and h_edge and dx == 0 and dy == 0:
        d = 1                                   # round the convex corner
    return d


# ------------------------------------------------------------------------------------------------------------------ floor (row 3)
FLOOR = env_art.FLOOR


def floor_q(qx, qy, v_edge, h_edge, d_edge):
    """Floor quarter. Edges (toward a WALL) are SHADE only, subtle on purpose (guards must stay readable): n = contact shadow."""
    t = quarter(FLOOR, qx, qy)
    for y in range(8):
        for x in range(8):
            d = rim_depth(qx, qy, x, y, v_edge, h_edge, d_edge)
            if d is None:
                continue
            north = v_edge and qy == 0 and d == y
            if north:                                       # contact shadow under the wall face: mortar colour, dithered tail
                if d <= 1:
                    t[y][x] = 4
                elif d == 2 and (x + y) % 2 == 0:
                    t[y][x] = 4
                elif d == 3 and x % 4 == 1:
                    t[y][x] = 4
            elif d == 0:
                t[y][x] = 4 if t[y][x] in (2, 3) else t[y][x]
            elif d == 1 and (x + y) % 2 == 0 and t[y][x] == 2:
                t[y][x] = 4
    return t


# ------------------------------------------------------------------------------------------------------------------ wall roof (row 7)
def roof_q(qx, qy, v_edge, h_edge, d_edge, deep=0):
    t = blank(8, 8, 4)
    if deep:                                                # speckle variants on the calm mass only
        for i in range(deep):
            t[int(hsh("sp", qx, qy, deep, i, "y") * 8)][int(hsh("sp", qx, qy, deep, i, "x") * 8)] = 1
    for y in range(8):
        for x in range(8):
            d = rim_depth(qx, qy, x, y, v_edge, h_edge, d_edge)
            if d is None:
                continue
            if d == 0:
                t[y][x] = 3
            elif d == 1:
                t[y][x] = 2
            elif d == 2 and (x + y) % 2 == 0:
                t[y][x] = 2
    return t


# ------------------------------------------------------------------------------------------------------------------ wall face (row 6)
def face_brick(qx):
    """16x8 strip: A (qx=0) / B (qx=1). lip, brick band, mortar, brick band, base shadow; 16-px period."""
    t = blank(8, 8, 2)
    for x in range(8):
        t[0][x] = 3
        t[3][x] = 4
        t[7][x] = 1
    # joints: band 1 (y1-2) at global x=7 (A.x7), band 2 (y4-6) at global x=15 (B.x7)
    for y in (1, 2):
        if qx == 0:
            t[y][7] = 4
    for y in (4, 5, 6):
        if qx == 1:
            t[y][7] = 4
    for y in (1, 2):                                        # lit top of each brick
        for x in range(8):
            if y == 1 and t[y][x] == 2:
                t[y][x] = 3 if x % 4 != 3 else 2
    return t


def face_cap(qx):
    """END_CAP: the face stops at open floor. Drawn for the W side (qx=0); the E side is its H mirror."""
    t = face_brick(0)
    for y in range(8):
        t[y][0] = 1
        if 0 < y < 7:
            t[y][1] = 3
    t[0][1] = 3
    return t if qx == 0 else hflip(t)


def face_inner(qx):
    """FACE_INNER: the face meets a wall mass that continues south (concave corner): the brick fades into shade at that side."""
    t = face_brick(1 if qx == 0 else 0)
    side = range(0, 2) if qx == 0 else range(6, 8)
    for y in range(1, 7):
        for x in side:
            if (x + y) % 2 == 0 or x in (0, 7):
                t[y][x] = 4
    return t


# ------------------------------------------------------------------------------------------------------------------ pit / water
def pit_q(qx, qy, v_edge, h_edge, d_edge):
    t = blank(8, 8, 1)
    for y in range(8):
        for x in range(8):
            if (x * 3 + y * 5) % 11 == 0:
                t[y][x] = 4
            d = rim_depth(qx, qy, x, y, v_edge, h_edge, d_edge)
            if d is None:
                continue
            north = v_edge and qy == 0 and d == y
            if d == 0:
                t[y][x] = 3
            elif north and d <= 3:
                t[y][x] = 4 if d != 2 else 2             # the far wall of the pit: brick course
            elif d == 1:
                t[y][x] = 4
    return t


def water_q(qx, qy, v_edge, h_edge, d_edge):
    t = blank(8, 8, 2)
    for y in range(8):
        for x in range(8):
            if y % 4 == 1 and (x + (y // 4) * 3) % 6 in (0, 1):
                t[y][x] = 3                              # ripple dashes, two tiles never differ at the seam rows' ends
            d = rim_depth(qx, qy, x, y, v_edge, h_edge, d_edge)
            if d is None:
                continue
            if d == 0:
                t[y][x] = 7
            elif d == 1:
                t[y][x] = 5 if (x + y) % 2 == 0 else 3
    return t


# ------------------------------------------------------------------------------------------------------------------ fixed 16x16 art
def art16(text):
    g = [[int(c, 16) for c in l] for l in text.split()]
    assert len(g) == 16 and all(len(r) == 16 for r in g), [len(r) for r in g]
    return g


PILLAR = art16("""
1111111111111111
1111111111111111
1153333333333511
1153333333333511
1152222222222411
1152222222222411
1152222332222411
1152222332222411
1152222222222411
1152222222222411
1152222222222411
1152222222222411
1144444444444411
1111111111111111
1111111111111111
1111111111111111
""")
EXIT = art16("""
4444444444444444
4333333333333333
4322222222222222
4322225555222222
4322255665522222
4322556776552222
4325567777655222
4325567777655222
4325567777655222
4322556776552222
4322255665522222
4322225555222222
4322222222222222
4322222222222222
4322222222222222
4444444444444444
""")
DOOR = art16("""
2222222222222222
3333333333333333
2444444444444442
2411111111111142
2411111111111142
2411111111111142
2411111111111142
2411111111111142
4444111111114444
4344444444444344
4344333333334344
4344222222224344
4344222222224344
4344222222224344
4344444444444344
4444444444444444
""")

# quarter -> (tile pixels) for fixed art, with the BG row used per quarter
FIXED = {"pillar": (PILLAR, ("pillar",) * 4), "exit": (EXIT, ("exit",) * 4), "door": (DOOR, ("door_top", "door_top", "door_bot", "door_bot"))}


# ------------------------------------------------------------------------------------------------------------------ autotiler
QPOS = ("NW", "NE", "SW", "SE")
EDGE_COMBOS = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1)]   # (v_edge, h_edge, d_edge): FILL, V_EDGE, H_EDGE, OUTER, INNER


class Q:
    """One tile quarter: surface, class name, logical tile name, 8x8 pixels (indices 1-7), BG palette row, BG priority."""
    __slots__ = ("surface", "cls", "name", "px", "row", "prio")

    def __init__(self, surface, cls, name, px, row, prio):
        self.surface, self.cls, self.name, self.px, self.row, self.prio = surface, cls, name, px, row, prio


def kind(grid, c, r) -> str:
    """Neighbour class of a grid position. Out of the grid = WALL."""
    if not (0 <= c < W and 0 <= r < H):
        return "wall"
    ch = grid[r][c]
    return {"#": "wall", "p": "pillar", "O": "pit", "W": "water", "D": "door"}.get(ch, "floor")


def cls_of(v, h, d):
    """design/tiles.md 3.1: v, h, d = 'joined' booleans of the vertical, horizontal and diagonal neighbour of a quarter."""
    if v and h and d:
        return "FILL"
    if not v and not h:
        return "OUTER"
    if not v:
        return "V_EDGE"
    if not h:
        return "H_EDGE"
    return "INNER"


def solid_cells(grid) -> set:
    return {(c, r) for r in range(H) for c in range(W) if grid[r][c] in "#pOW"}


def autotile_px(grid) -> dict:
    """-> {(c, r, qx, qy): Q}. One entry per cell quarter. Pure function of the grid (no decoration, no randomness except the deep-mass speckle seed)."""
    out = {}
    for r in range(H):
        for c in range(W):
            k = kind(grid, c, r)
            if k in ("pillar", "door") or grid[r][c] == "X":
                name = "pillar" if k == "pillar" else "door" if k == "door" else "exit"
                art, rows = FIXED[name]
                for qy in range(2):
                    for qx in range(2):
                        rk = rows[qy * 2 + qx]
                        out[(c, r, qx, qy)] = Q(name, "FIXED", f"{name}.{QPOS[qy * 2 + qx]}", quarter(art, qx, qy), ROW[rk], PRIO[rk])
                continue
            for qy in range(2):
                for qx in range(2):
                    dv, dh = (-1, 1)[qy], (-1, 1)[qx]
                    nv, nh, nd = kind(grid, c, r + dv), kind(grid, c + dh, r), kind(grid, c + dh, r + dv)
                    qp = QPOS[qy * 2 + qx]
                    if k == "wall":
                        south_open = kind(grid, c, r + 1) != "wall"
                        if qy == 1 and south_open:                       # face quarter (table 3.3, total over h, d)
                            hc = min(max(c + dh, 0), W - 1)               # off-screen sides continue the face
                            hk, dk = kind(grid, hc, r), kind(grid, hc, r + 1)
                            if hk == "wall" and dk != "wall":
                                name, px = "BRICK", face_brick(qx)
                            elif hk == "wall":
                                name, px = "FACE_INNER", face_inner(qx)
                            else:
                                name, px = "END_CAP", face_cap(qx)
                            out[(c, r, qx, qy)] = Q("face", name, f"face.{name}.{'W' if qx == 0 else 'E'}", px, ROW["face"], PRIO["face"])
                            continue
                        v, h, d = nv == "wall", nh == "wall", nd == "wall"
                        cl = cls_of(v, h, d)
                        deep, nm = 0, f"roof.{cl}.{qp}"
                        if cl == "FILL" and all(kind(grid, c + i, r + j) == "wall" for i in (-2, -1, 0, 1, 2) for j in (-2, -1, 0, 1, 2)):
                            q = hsh("deep", c, r)                      # one choice per CELL: the four quarters stay coordinated
                            deep = 0 if q < 0.88 else 1 + int(q * 1000) % 3
                            nm = f"roof.FILL.{qp}.s{deep}"
                        out[(c, r, qx, qy)] = Q("roof", cl, nm, roof_q(qx, qy, not v, not h, (not d) and v and h, deep), ROW["roof"], PRIO["roof"])
                    elif k in ("pit", "water"):
                        same = lambda n, k=k: n in ("wall", k)           # a wall hides the basin interior: no rim against walls
                        v, h, d = same(nv), same(nh), same(nd)
                        cl = cls_of(v, h, d)
                        fn = pit_q if k == "pit" else water_q
                        out[(c, r, qx, qy)] = Q(k, cl, f"{k}.{cl}.{qp}", fn(qx, qy, not v, not h, (not d) and v and h), ROW[k], PRIO[k])
                    else:                                                 # floor: edges only toward WALL
                        ve, he, de = nv == "wall", nh == "wall", nd == "wall"
                        cl = cls_of(not ve, not he, not de)
                        out[(c, r, qx, qy)] = Q("floor", cl, f"floor.{cl}.{qp}", floor_q(qx, qy, ve, he, de and not ve and not he), ROW["floor"], PRIO["floor"])
    return out


def depth_prio(grid, c, r, qx, qy) -> int:
    """design/tiles.md 2.1 rule 1: BG priority 1 exactly on the NW/NE quarters of a '#' / 'p' cell whose cell above is inside the grid and
    not solid ('#' 'p' 'O' 'W'): an actor north of a wall / pillar is drawn behind its top edge. Everything else priority 0."""
    return 1 if qy == 0 and r > 0 and grid[r][c] in "#p" and grid[r - 1][c] not in "#pOW" else 0


def with_prio(q: Q, prio: int) -> Q:
    return q if q.prio == prio else Q(q.surface, q.cls, q.name, q.px, q.row, prio)


def autotile(grid) -> dict:
    """The QA contract: {(c, r, qx, qy): (surface, class_name, tile_name)}."""
    return {k: (q.surface, q.cls, q.name) for k, q in autotile_px(grid).items()}


# ------------------------------------------------------------------------------------------------------------------ decoration (E5 survivors)
def _tiles16(g, rows, prios, surface, nm):
    return [Q(surface, "DECOR", f"{nm}.{QPOS[i]}", quarter(g, i % 2, i // 2), rows[i], prios[i]) for i in range(4)]


def _flip16(qs):
    """H-flip of a 2x2 decoration cell: swap columns and mirror the pixels."""
    n = [Q(q.surface, q.cls, q.name + "_h", hflip(q.px), q.row, q.prio) for q in qs]
    return [n[1], n[0], n[3], n[2]]


ROOF_FILL0 = lambda: roof_q(0, 0, 0, 0, 0, 0)      # noqa: E731  (a plain wall-top quarter; every FILL quarter without speckle is this pixel pattern)


def _build_decor() -> dict:
    # the decoration art of env_art.py is painted on the NEW floor / face base: env_art.FLOOR is already ours; face strips copy env_art.FACE
    env_art.FACE = [face_brick(0)[y] + face_brick(1)[y] for y in range(8)]
    D = {}

    def floor_dec(name, g):
        qs = _tiles16(g, (3, 3, 3, 3), (0, 0, 0, 0), "floor", name)
        D[name] = ("floor", qs)
        D[name + "_h"] = ("floor", _flip16(qs))

    floor_dec("f_crack", env_art.floor_crack())
    floor_dec("f_crack2", env_art.floor_crack2())
    floor_dec("f_worn", env_art.floor_worn())
    floor_dec("f_moss", env_art.floor_moss())
    D["f_rune"] = ("floor", _tiles16(env_art.floor_rune(), (3, 3, 3, 3), (0, 0, 0, 0), "floor", "f_rune"))

    def face_dec(name, strip, top_roof=True):
        g = [[0] * 16 for _ in range(16)]
        for y in range(8):
            g[8 + y] = list(strip[y])
        qs = _tiles16(g, (7, 7, 6, 6), (0, 0, 0, 0), "face", name)
        qs[0] = Q("face", "DECOR", name + ".NW", ROOF_FILL0(), 7, 0)
        qs[1] = Q("face", "DECOR", name + ".NE", ROOF_FILL0(), 7, 0)
        D[name] = ("face", qs)

    face_dec("fc_crack", env_art.face_crack())
    face_dec("fc_banner", env_art.face_banner())
    face_dec("fc_sigil", env_art.face_sigil())
    face_dec("fc_warm", env_art.face_warm())
    face_dec("fc_sconce", env_art.sconce_strip())
    D["fc_torch"] = ("face", _tiles16(env_art.torch_block(True), (6, 6, 6, 6), (0, 0, 0, 0), "face", "fc_torch"))
    return D


DECOR = _build_decor()


def decor_plan(rid: str, grid, lit: bool, base: dict) -> dict:
    """{(c, r): decoration name}. Deterministic (seeded by room id + cell). Rules: design/tiles.md 3.5; every decoration replaces a cell whose
    quarters are all calm FILL / BRICK, so edges, corners, caps and doorways stay clean."""
    plan: dict = {}

    def ch(c, r):
        return grid[r][c] if 0 <= c < W and 0 <= r < H else "#"

    def clean_face(c, r):
        if grid[r][c] != "#" or kind(grid, c, r + 1) == "wall" or r + 1 >= H:
            return False
        return (base[(c, r, 0, 1)].name.startswith("face.BRICK") and base[(c, r, 1, 1)].name.startswith("face.BRICK")
                and base[(c, r, 0, 0)].cls == "FILL" and base[(c, r, 1, 0)].cls == "FILL")

    def clean_floor(c, r):
        return grid[r][c] == "." and all(base[(c, r, a, b)].cls == "FILL" for a in (0, 1) for b in (0, 1))

    face = {(c, r) for r in range(H) for c in range(W) if clean_face(c, r)}
    torch_name = "fc_torch" if lit else "fc_sconce"
    spacing, first = (5, 2) if lit else (6, 3)
    torches = []
    for r in range(H):
        c = 0
        while c < W:
            if (c, r) not in face:
                c += 1
                continue
            e = c
            while e < W and (e, r) in face:
                e += 1
            k = 0
            while True:
                x = c + first + k * spacing + (1 if hsh(rid, c, r, "tj%d" % k) < 0.4 else 0)
                if x >= e - 1:
                    break
                k += 1
                if any(ch(x + dx, r + 1) == "X" for dx in (-1, 0, 1)) or ch(x, r + 1) in "abcdefgh":
                    continue
                torches.append((x, r))
                plan[(x, r)] = torch_name
            c = e
    if lit:
        for (x, r) in torches:
            for dx in (-1, 1):
                if (x + dx, r) in face and (x + dx, r) not in plan:
                    plan[(x + dx, r)] = "fc_warm"
    deco = list(torches)
    for r in range(H):
        for c in range(W):
            if (c, r) not in face or (c, r) in plan:
                continue
            if any(abs(c - x) < 3 and r == y for x, y in deco):
                continue
            v = hsh(rid, c, r, "fd")
            name = "fc_banner" if v < 0.09 else "fc_sigil" if v < 0.15 else "fc_crack" if v < 0.24 else None
            if name:
                plan[(c, r)] = name
                deco.append((c, r))
    runes = []
    for r in range(H):
        for c in range(W):
            if (c, r) in plan or not clean_floor(c, r) or hsh(rid, c, r, "fv") >= 0.18:
                continue
            if any((c + dx, r + dy) in plan and plan[(c + dx, r + dy)].startswith("f_") and not plan[(c + dx, r + dy)].startswith("f_glow")
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            t = hsh(rid, c, r, "ft")
            if t < 0.12 and len(runes) < 2 and all(abs(c - x) + abs(r - y) > 5 for x, y in runes):
                name = "f_rune"
                runes.append((c, r))
            elif t < 0.37:
                name = "f_crack" if hsh(rid, c, r, "fs") < 0.5 else "f_crack2"
            elif t < 0.68:
                name = "f_worn"
            else:
                name = "f_moss"
            if name != "f_rune" and hsh(rid, c, r, "ff") < 0.5:
                name += "_h"
            plan[(c, r)] = name
    return plan


# ------------------------------------------------------------------------------------------------------------------ char registry
def _universe() -> list:
    """Every quarter the autotiler or the decoration can produce, in a fixed order -> list of Q."""
    U = []
    for qy in range(2):
        for qx in range(2):
            qp = QPOS[qy * 2 + qx]
            for ve, he, de in EDGE_COMBOS:
                cl = cls_of(not ve, not he, not de)
                for deep in ((0, 1, 2, 3) if cl == "FILL" else (0,)):
                    U.append(Q("roof", cl, "", roof_q(qx, qy, ve, he, de, deep), ROW["roof"], PRIO["roof"]))
                U.append(Q("floor", cl, "", floor_q(qx, qy, ve, he, de), ROW["floor"], PRIO["floor"]))
                U.append(Q("pit", cl, "", pit_q(qx, qy, ve, he, de), ROW["pit"], PRIO["pit"]))
                U.append(Q("water", cl, "", water_q(qx, qy, ve, he, de), ROW["water"], PRIO["water"]))
    for qx in range(2):
        for fn in (face_brick, face_inner, face_cap):
            U.append(Q("face", "", "", fn(qx), ROW["face"], PRIO["face"]))
    for name, (art, rows) in FIXED.items():
        for qy in range(2):
            for qx in range(2):
                rk = rows[qy * 2 + qx]
                U.append(Q(name, "FIXED", "", quarter(art, qx, qy), ROW[rk], PRIO[rk]))
    for name in sorted(DECOR):
        U.extend(DECOR[name][1])
    # design/tiles.md 2.1: the top quarters of a wall / pillar cell (any surface or decoration they can carry) also exist with priority 1
    U.extend([with_prio(q, 1) for q in list(U) if q.surface in ("roof", "face", "pillar")])
    return U


def _key(q: Q):
    return (q.surface in SOLID or q.surface == "face" and True, tuple(map(tuple, q.px)), q.row, q.prio)


def _canon(px):
    t = tuple(map(tuple, px))
    f = tuple(map(tuple, hflip(px)))
    return min(t, f), (t != min(t, f))


def _solid(q: Q) -> int:
    return 1 if q.surface in SOLID else 0


CHARS: list = []          # char index -> (cell, hflip, row, prio, solid)
CHAR_OF: dict = {}        # (pixels tuple, row, prio, solid) -> char index
CELLS: list = []          # cell index -> canonical pixels (8x8)
_CELL_OF: dict = {}
for _q in _universe():
    _k = (tuple(map(tuple, _q.px)), _q.row, _q.prio, _solid(_q))
    if _k in CHAR_OF:
        continue
    _cp, _fl = _canon(_q.px)
    if _cp not in _CELL_OF:
        _CELL_OF[_cp] = len(CELLS)
        CELLS.append(_cp)
    CHAR_OF[_k] = len(CHARS)
    CHARS.append((_CELL_OF[_cp], 1 if _fl else 0, _q.row, _q.prio, _solid(_q)))
assert len(CHARS) <= 255, len(CHARS)     # char 0 stays free as "empty"
assert len(CELLS) <= 192, len(CELLS)

# ---- lighting (design/lighting.md): BG1 light tiles, added onto the room by colour math. Pixel index i -> colour 8+i of BG row LIGHT_ROW.
# 1 amber edge, 2 amber mid, 3 amber core, 4 violet glow. Registered as raw cells (no H-flip canonicalisation: the checker phase must
# stay the same in every tile so neighbouring tiles continue the pattern). Never in CHARS: BG1 has no collision.
LIGHT_ROW = 2


def _lt(a, b=None):
    b = a if b is None else b
    return tuple(tuple(a if (x + y) % 2 == 0 else b for x in range(8)) for y in range(8))


LIGHT_PATTERNS = [_lt(0), _lt(1, 0), _lt(1), _lt(2, 1), _lt(2), _lt(3, 2), _lt(3),   # steps 0..6 (amber)
                  _lt(4, 0), _lt(4)]                                                # violet glow 1, 2
LIGHT_CELL: list = []
for _p in LIGHT_PATTERNS:
    if _p not in _CELL_OF:
        _CELL_OF[_p] = len(CELLS)
        CELLS.append(_p)
    LIGHT_CELL.append(_CELL_OF[_p])
assert len(CELLS) <= 192, len(CELLS)

SHEET_ORDER = (("GFX_00", 0), ("GFX_10", 128), ("GFX_06", 192))     # sheet, first tile id (VRAM slots 0, 2, 3; docs/gfx/art_map.md 2.1)


def tile_id(cell: int) -> int:
    s, m = divmod(cell, 64)
    return SHEET_ORDER[s][1] + m


def char_word(ci: int) -> int:
    cell, fl, row, prio, _ = CHARS[ci]
    return tile_id(cell) | (row << 10) | (prio << 13) | (0x4000 if fl else 0)


def char_words() -> list:
    return [char_word(i) if i < len(CHARS) else 0 for i in range(256)]


def light_words() -> list:
    """BG1 tile words of the 9 light tiles (index = amber step 0..6, then violet 1, 2): palette row LIGHT_ROW, priority 0."""
    return [tile_id(c) | (LIGHT_ROW << 10) for c in LIGHT_CELL]


# ---- smooth light (design/lighting.md section 4, revision 2): bilinear gradient tiles with a 4x4 Bayer dither -----------------------------
# Corner levels: amber 0..LIGHT_N-1 (N = 7: Q(step) = step), violet 0..LIGHT_NV-1. Tiles are raw 4bpp (not part of any 3bpp sheet): uploaded
# by src/hooks/light.asm to the BG character slots 4-6 (tile ids $100-$1BF, VRAM byte $6000-$77FF; docs/gfx/art_map.md 2.1: never drawn by a
# room). Pixel value = colour index of BG palette row LIGHT_ROW: amber ramp r1..r12 -> colours 1..12, violet v1..v3 -> colours 13..15.
LIGHT_N, LIGHT_K, LIGHT_NV, LIGHT_KV = 7, 13, 3, 4
LIGHT_TILE_BASE = 0x100
LIGHT_TILE_MAX = 192
LIGHT_BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
# BGR555 components (r, g, b) of the ramps, ADDED by colour math: faint deep amber -> bright warm core; faint violet (4.2, 4.3)
LIGHT_AMBER = [(2, 1, 0), (3, 1, 0), (5, 2, 0), (6, 3, 0), (8, 4, 0), (9, 5, 0), (11, 6, 0), (12, 7, 0), (14, 8, 0), (15, 9, 1), (16, 9, 1), (18, 10, 1)]
LIGHT_VIOLET = [(1, 0, 3), (3, 1, 5), (4, 1, 8)]


def _light_px(cor, n, k):
    """design/lighting.md 4.2, exact rational arithmetic."""
    from fractions import Fraction as Fr
    a, b, c, d = cor
    out = []
    for y in range(8):
        row = []
        for x in range(8):
            u, w = Fr(2 * x + 1, 16), Fr(2 * y + 1, 16)
            lv = a * (1 - u) * (1 - w) + b * u * (1 - w) + c * (1 - u) * w + d * u * w
            p = lv * (k - 1) / (n - 1)
            lo = int(p)
            row.append(lo + 1 if p - lo > Fr(2 * LIGHT_BAYER[y % 4][x % 4] + 1, 32) else lo)
        out.append(row)
    return out


def _orients(t):
    a, b, c, d = t
    return {(0, 0): t, (1, 0): (b, a, d, c), (0, 1): (c, d, a, b), (1, 1): (d, c, b, a)}     # (hflip, vflip) -> shown corners


def _light_q(total, den, n, vmax):
    return (2 * total * (n - 1) + den * vmax) // (2 * den * vmax)      # floor(total / den * (n - 1) / vmax + 1/2)


def _light_reachable(n, vmax, cells):
    """Corner tuples of a NW quarter tile (a = cell corner, b = top edge, c = left edge, d = centre) over the cell value combos, all 4 orientations."""
    out = set()
    for C, H, V, D in cells:
        t = (_light_q(C + H + V + D, 4, n, vmax), _light_q(C + V, 2, n, vmax), _light_q(C + H, 2, n, vmax), _light_q(C, 1, n, vmax))
        if max(t):
            out |= set(_orients(t).values())
    return out


def _glow_cells():
    """(C, H, V, D) glow values of a 2x2 block (C at (1,1), H (0,1), V (1,0), D (0,0)) for any solidity and Link position (section 3 glow rule)."""
    pos = ((1, 1), (0, 1), (1, 0), (0, 0))
    for solid in range(16):
        for lx in range(-2, 4):
            for ly in range(-2, 4):
                if (lx, ly) in pos and solid >> pos.index((lx, ly)) & 1:
                    continue
                yield tuple(0 if solid >> i & 1 else 2 if (x, y) == (lx, ly) else 1 if abs(x - lx) + abs(y - ly) == 1 else 0
                            for i, (x, y) in enumerate(pos))


def _build_light():
    import itertools
    amber = _light_reachable(LIGHT_N, 6, itertools.product(range(7), repeat=4))
    violet = _light_reachable(LIGHT_NV, 2, _glow_cells())
    tiles = [{"tile": LIGHT_TILE_BASE, "kind": "empty", "corners": (0, 0, 0, 0), "px": [[0] * 8 for _ in range(8)]}]
    words = {}
    for kind, tset, n, k in (("amber", amber, LIGHT_N, LIGHT_K), ("violet", violet, LIGHT_NV, LIGHT_KV)):
        for canon in sorted({min(_orients(t).values()) for t in tset}):
            tid = LIGHT_TILE_BASE + len(tiles)
            tiles.append({"tile": tid, "kind": kind, "corners": canon, "px": _light_px(canon, n, k)})
            for (h, v), shown in _orients(canon).items():
                words.setdefault((kind, shown), tid | (LIGHT_ROW << 10) | (0x4000 if h else 0) | (0x8000 if v else 0))
    assert len(tiles) <= LIGHT_TILE_MAX, len(tiles)
    return tiles, words


LIGHT_TILES, LIGHT_WORDS = _build_light()
LIGHT_EMPTY_WORD = LIGHT_TILE_BASE | (LIGHT_ROW << 10)


def light_tiles() -> list:
    """One dict per stored (unflipped) BG1 light tile: tile id, kind, corners (a TL, b TR, c BL, d BR), 8x8 ramp indices (tests/unit/test_light_tiles.py)."""
    return LIGHT_TILES


def light_word(kind: str, corners) -> int:
    """BG1 tile word shown for a corner tuple (KeyError if no stored tile can show it)."""
    t = tuple(corners)
    if max(t) == 0:
        return LIGHT_EMPTY_WORD
    return LIGHT_WORDS[(kind, t)]


def light_colour(i: int) -> int:
    """BGR555 word of colour i (1..15) of BG row LIGHT_ROW."""
    r, g, b = (LIGHT_AMBER + LIGHT_VIOLET)[i - 1]
    return r | (g << 5) | (b << 10)


def light_chr() -> bytes:
    """Raw 4bpp character data of the light tiles, tile id order from LIGHT_TILE_BASE (32 bytes per tile)."""
    out = bytearray()
    for t in LIGHT_TILES:
        off = 0 if t["kind"] != "violet" else LIGHT_K - 1      # violet ramp v1.. -> colours 13..
        px = [[(v + off) if v else 0 for v in row] for row in t["px"]]
        lo, hi = bytearray(), bytearray()
        for row in px:
            bp = [sum(((row[x] >> p) & 1) << (7 - x) for x in range(8)) for p in range(4)]
            lo += bytes((bp[0], bp[1]))
            hi += bytes((bp[2], bp[3]))
        out += lo + hi
    return bytes(out)


def light_lut(kind: str) -> list:
    """BG1 word per corner tuple, index ((a * n + b) * n + c) * n + d; unreachable tuples -> the empty tile."""
    n = LIGHT_N if kind == "amber" else LIGHT_NV
    import itertools
    return [LIGHT_WORDS.get((kind, t), LIGHT_EMPTY_WORD) if max(t) else LIGHT_EMPTY_WORD for t in itertools.product(range(n), repeat=4)]


def tile_types() -> list:
    """UnderworldTileTypes[0..255] replacement: collision type per tile id ($00 walk / $01 solid). Unused ids walk ($00)."""
    t = [0] * 256
    for cell, _, _, _, sol in CHARS:
        t[tile_id(cell)] = max(t[tile_id(cell)], sol)
    # a cell shared by a solid and a walkable char would break collision: refuse (the key includes solidity, so pixels may repeat across surfaces)
    for cell, _, _, _, sol in CHARS:
        assert t[tile_id(cell)] == sol, f"cell {cell} used by both solid and walkable chars"
    return t


def sheet_cells() -> dict:
    """{sheet name: {(col, row): 8x8 pixels}} for gfx/src/bg_tileset (every other cell of the three sheets is cleared)."""
    out = {n: {} for n, _ in SHEET_ORDER}
    for i, px in enumerate(CELLS):
        s, m = divmod(i, 64)
        out[SHEET_ORDER[s][0]][(m % 16, m // 16)] = [list(r) for r in px]
    return out


def char_of(q: Q) -> int:
    return CHAR_OF[(tuple(map(tuple, q.px)), q.row, q.prio, _solid(q))]


def place(rid: str, grid, lit: bool):
    """-> (chars, plan): chars = 28 rows x 32 char indices (the 256x224 window in 8x8 tiles), plan = {(c, r): decoration name}."""
    base = autotile_px(grid)
    plan = decor_plan(rid, grid, lit, base)
    rows = [[0] * (W * 2) for _ in range(H * 2)]
    for (c, r, qx, qy), q in base.items():
        dec = plan.get((c, r))
        if dec:
            q = DECOR[dec][1][qy * 2 + qx]
        rows[r * 2 + qy][c * 2 + qx] = char_of(with_prio(q, depth_prio(grid, c, r, qx, qy)))
    return rows, plan


def rle(chars) -> bytes:
    """Row-major RLE of the 32x28 chars: pairs (count 1..255, char). Decoder: src/hooks/roomload.asm Hush_Blit."""
    flat = [c for row in chars for c in row]
    out, i = bytearray(), 0
    while i < len(flat):
        j = i
        while j < len(flat) and flat[j] == flat[i] and j - i < 255:
            j += 1
        out += bytes([j - i, flat[i]])
        i = j
    return bytes(out)


if __name__ == "__main__":
    print(len(CHARS), "chars,", len(CELLS), "cells")
