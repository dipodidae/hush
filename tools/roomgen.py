#!/usr/bin/env python3
"""HUSH room compiler: design/rooms/*.yaml -> build/rooms_gen.asm (+ report, + Lua metadata).

  roomgen.py                       compile design/rooms (or $HUSH_ROOMS_DIR, or --rooms-dir)
  roomgen.py --rooms-dir DIR       compile another directory (tests use tests/dev/rooms)

Every room spec (files not starting with '_') is sorted by `seq`; room k (0-based) becomes
underworld room id $128+k and EntranceData row k. See docs/engine_notes.md for the geometry:

  * a HUSH room is the VISIBLE 256x224 window of a 512x512 vanilla room (layout 7: one big open room);
    the window is 16x14 cells of 16x16 px, its top-left is at room-local pixel (WIN_X, WIN_Y);
  * `#`/`p`/`X` cells become 2x2-tile objects (one cell each) merged into runs; the object id picks the art: wall top `$00`/`$60`, wall face
    `$07` (a `#` with floor below it), pillar `$B8`/`$92`, exit marker `$B9`/`$93` (tile data rewritten in src/hooks/room_visuals.asm);
  * E5 variants: deterministic decoration of the same cells (floor cracks/moss/runes, wall-top chips, banners, wall torches + light pools in lit rooms)
    drawn by ONE hijacked vanilla object routine (`$09`/`$0A`, src/hooks/room_visuals.asm: size field = variant index) after the plain objects;
    collision is a property of the tile ids and is identical (docs/engine_notes.md section 13);
  * the header's palette-set byte = floor 1-3 / lit-dark (UnderworldPaletteSets rows 0-5 -> pal_dungeon_00..05);
  * guard letters become sprite-list entries (soldier sprite $41), one per guard; `move: still` sets sub-type bit 3 (value 8) which the
    E2 AI (src/hooks/guard_ai.asm) reads as `$0E30 & 8`.

Outputs
  build/rooms_gen.asm    included by src/main.asm: object streams, door pointers, headers, sprite lists,
                         ROOM TABLE (engine runtime data), pointer-table rewrites, EntranceData rows.
                         Every `org` is checked against src/FREESPACE.md by tools/check_freespace.py.
  build/rooms_report.txt human-readable ASCII of each compiled room + byte sizes
  build/rooms_gen.lua    metadata for the Lua tests (start/exit positions in Link coordinates)

Fails loudly (non-zero exit) if a spec is invalid or any generated region overflows its ledger budget.
"""
from __future__ import annotations

import argparse
import os
import sys
import hashlib
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import BUILD_DIR, ROOT, die  # noqa: E402

# ---------------------------------------------------------------------------------------------
# Geometry (single source of truth; the generated asm exports these as `!HUSH_*` defines)
# ---------------------------------------------------------------------------------------------
GRID_W, GRID_H, CELL = 16, 14, 16
WIN_X, WIN_Y = 128, 144           # room-local pixel of the window's top-left (centres 256x224 in 512x512)
WIN_TX, WIN_TY = WIN_X // 8, WIN_Y // 8   # same, in 8x8 tiles
ROOM_FIRST = 0x128                # first HUSH room id
MAX_ROOMS = 24                    # ids $128..$13F
# Link's tile-collision box is x..x+15, y+8..y+23 (measured, docs/engine_notes.md)
LINK_START_DX, LINK_START_DY = 0, -8        # Link coordinate = cell top-left + (dx, dy)
LINK_FEET_DX, LINK_FEET_DY = 8, 16          # exit test point = centre of Link's collision box = (x,y) + (dx, dy)
MAX_EXITS = 4

LAYOUT = 7                        # RoomLayout_07: one big open room (bank_04.asm:5144-5199)
FLOOR_BYTE = 0x22                 # b0 of the object stream: floor nibbles (BG2 hi, BG1 lo)
SOLDIER_SPRITE = 0x41             # green soldier: Guard_Main (docs/engine_notes.md)
FACING_SUBTYPE = {"left": 1, "right": 2, "up": 3, "down": 4}   # sub-type n -> $0DE0 = (n-1)^1 (bank_06.asm:3445-3459); guard dir: 0 right, 1 left, 2 down, 3 up
STILL_SUBTYPE = 8                 # E2: sub-type bit 3 (ss = 1) = `move: still`; vanilla only looks at the low 3 bits (SpritePrep_StandardGuard,
                                  # `AND #$07`), the E2 guard AI (src/hooks/guard_ai.asm) reads `$0E30 & 8`: the guard never walks
TOOL_BITS = {"shade_knife": 1, "hush_darts": 2, "ink_pots": 4}

# Visual variety (docs/gfx/art_map.md section 3, docs/engine_notes.md section 12). Collision is a property of the tile ids (UnderworldTileTypes,
# `$7EFE00 + id`), not of the object, so the tile data of vanilla objects that HUSH never otherwise uses is rewritten (src/hooks/room_visuals.asm)
# and roomgen picks the object id per cell kind. Cell kind -> (object id when run rightwards / downwards or None, size semantics):
#   "1to15or32": size field n (1..15; 0 would mean 32)      "1to16": size field n-1
OBJ_KINDS = {
    "ceil":   (0x00, 0x60, "1to15or32"),   # wall top surface: GFX_00 (5,1)  (vanilla data obj03D8, untouched)
    "face":   (0x07, None, "1to16"),       # wall face: top row = ceiling tiles, bottom row = face tiles (obj0388 rewritten)
    "pillar": (0xB8, 0x92, "1to15or32"),   # pillar block (obj1F52 rewritten; $B8 right, $92 down share it)
    "exit":   (0xB9, 0x93, "1to15or32"),   # exit marker block (obj1F5A rewritten; $B9 right, $93 down share it)
}
# header byte 1 = UnderworldPaletteSets row (4 bytes: BG palette id = 2 x pal_dungeon_NN, then 3 sprite palette bytes). Rows 0..5 all carry
# the sprite bytes 00 03 01 (src/hooks/room_visuals.asm), so only the BG palette differs. Row = LIT_ROWS/DARK_ROWS[floor - 1].
DARK_PAL_ROWS = (0, 1, 2)
LIT_PAL_ROWS = (3, 4, 5)

# ---- E5 visual variants (docs/engine_notes.md section 13, docs/gfx/art_map.md section 3.5) ---------------------------------------
# Tile words `vhoppp cc cccccccc` (v/h flip, o priority, ppp palette row, c tile id). The 16x16 art lives in gfx/src/bg_tileset (tools/art/env_art.py).
# Each variant draws ONE cell (2x2 tiles) through the hijacked object ids VARIANT_OBJ_IDS (16 variants each: the object's size field is the index).
# Order inside VARIANTS = index; (name, base kind it may replace, tile words TL, TR, BL, BR). Tile TYPES (collision) are vanilla ones checked in
# UnderworldTileTypes: floor blocks use only type $00 ids ($C4-$DD, $E9 $EA $F9 $FA, $EE $EF $FE $FF, $2E $2F $3E $3F), wall variants only type $01 ids ($00-$02, $15, $80-$95, $A0 $A1 $B0 $B1).
VARIANT_OBJ_IDS = (0x09, 0x0A)
VARIANT_DATA_ROM = 0x009F72       # RoomDrawObjectData + $0420 (obj0420, vanilla data of the unused diagonal objects $09-$20): 8 bytes per variant (TL, BL, TR, BR)
VARIANT_PER_ID = 16
VARIANT_DATA_OFFSET_B = VARIANT_PER_ID * 8       # id $0A's data offset = id $09's + 128 (src/hooks/room_visuals.asm rewrites type1_data_offset[$0A])
H_FLIP = 0x4000


def _w(pal: int, prio: int, tid: int, hflip: bool = False) -> int:
    return tid | (pal << 10) | (prio << 13) | (H_FLIP if hflip else 0)


def _floor_block(a: int, b: int, c: int, d: int, hflip: bool = False) -> tuple[int, int, int, int]:
    # a b / c d = TL TR / BL BR of the unflipped art; a horizontal flip swaps the columns and sets the flip bit on all four
    if hflip:
        return (_w(3, 0, b, True), _w(3, 0, a, True), _w(3, 0, d, True), _w(3, 0, c, True))
    return (_w(3, 0, a), _w(3, 0, b), _w(3, 0, c), _w(3, 0, d))


CEIL_W = _w(7, 1, 0x15)           # the plain wall-top tile (GFX_00 (5,1))
VARIANTS: list[tuple[str, str, tuple[int, int, int, int]]] = [
    # floor (base kind "floor" = a '.' cell), BG row 3, priority 0
    ("f_crack", "floor", _floor_block(0xC4, 0xC5, 0xD4, 0xD5)),
    ("f_crack_h", "floor", _floor_block(0xC4, 0xC5, 0xD4, 0xD5, True)),
    ("f_crack2", "floor", _floor_block(0xE9, 0xEA, 0xF9, 0xFA)),
    ("f_crack2_h", "floor", _floor_block(0xE9, 0xEA, 0xF9, 0xFA, True)),
    ("f_shadow", "floor", _floor_block(0xEE, 0xEF, 0xFE, 0xFF)),
    ("f_worn", "floor", _floor_block(0xC6, 0xC7, 0xD6, 0xD7)),
    ("f_worn_h", "floor", _floor_block(0xC6, 0xC7, 0xD6, 0xD7, True)),
    ("f_rune", "floor", _floor_block(0xC8, 0xC9, 0xD8, 0xD9)),
    ("f_moss", "floor", _floor_block(0xCA, 0xCB, 0xDA, 0xDB)),
    ("f_moss_h", "floor", _floor_block(0xCA, 0xCB, 0xDA, 0xDB, True)),
    ("f_glow", "floor", _floor_block(0xCC, 0xCD, 0xDC, 0xDD)),
    ("f_glow_h", "floor", _floor_block(0xCC, 0xCD, 0xDC, 0xDD, True)),
    ("f_glow2", "floor", _floor_block(0x2E, 0x2F, 0x3E, 0x3F)),
    ("f_glow2_h", "floor", _floor_block(0x2E, 0x2F, 0x3E, 0x3F, True)),
    # wall top (base kind "ceil"), BG row 7, priority 1: chips / speckle variants mixed from the tiles $15 (plain), $00 $01 $02, and a 16x16 crack block $80 $81 / $90 $91
    ("ct_a", "ceil", (_w(7, 1, 0x00), CEIL_W, CEIL_W, _w(7, 1, 0x01))),
    ("ct_b", "ceil", (CEIL_W, _w(7, 1, 0x01), _w(7, 1, 0x02), CEIL_W)),
    ("ct_c", "ceil", (_w(7, 1, 0x01), _w(7, 1, 0x00), CEIL_W, _w(7, 1, 0x02))),
    ("ct_d", "ceil", (_w(7, 1, 0x02), CEIL_W, _w(7, 1, 0x00), CEIL_W)),
    ("ct_crack", "ceil", (_w(7, 1, 0x80), _w(7, 1, 0x81), _w(7, 1, 0x90), _w(7, 1, 0x91))),
    ("ct_crack_h", "ceil", (_w(7, 1, 0x81, True), _w(7, 1, 0x80, True), _w(7, 1, 0x91, True), _w(7, 1, 0x90, True))),
    ("ct_seam", "ceil", (_w(7, 1, 0xA0), _w(7, 1, 0xA1), _w(7, 1, 0xB0), _w(7, 1, 0xB1))),
    ("ct_seam_h", "ceil", (_w(7, 1, 0xA1, True), _w(7, 1, 0xA0, True), _w(7, 1, 0xB1, True), _w(7, 1, 0xB0, True))),
    # wall face (base kind "face"): top row = plain wall-top tile, bottom row = face strip A/B in BG row 6 (priority 1); torch/sconce are whole 16x16 cells
    ("fc_crack", "face", (CEIL_W, CEIL_W, _w(6, 1, 0x8A), _w(6, 1, 0x8B))),
    ("fc_banner", "face", (CEIL_W, CEIL_W, _w(6, 1, 0x86), _w(6, 1, 0x87))),
    ("fc_sigil", "face", (CEIL_W, CEIL_W, _w(6, 1, 0x88), _w(6, 1, 0x89))),
    ("fc_warm", "face", (CEIL_W, CEIL_W, _w(6, 1, 0x8C), _w(6, 1, 0x8D))),
    ("fc_torch", "face", (_w(6, 1, 0x82), _w(6, 1, 0x83), _w(6, 1, 0x92), _w(6, 1, 0x93))),
    ("fc_sconce", "face", (CEIL_W, CEIL_W, _w(6, 1, 0x84), _w(6, 1, 0x85))),
]
VARIANT_INDEX = {name: i for i, (name, _, _) in enumerate(VARIANTS)}
assert len(VARIANTS) <= VARIANT_PER_ID * len(VARIANT_OBJ_IDS)

# ROM budgets: must be inside the rows in src/FREESPACE.md (checked by tools/check_freespace.py)
OBJ_PTR = 0x1F8000                # 3-byte entries, room*3   (RoomData_ObjectDataPointers)
DOOR_PTR = 0x1F83C0               # 3-byte entries           (RoomData_DoorDataPointers)
HDR_PTR = 0x04F502                # 2-byte entries, bank 04  (RoomHeaderPointers)
SPR_PTR = 0x09D62E                # 2-byte entries, bank 09  (RoomData_SpritePointers)
STREAM_BASE = 0x1F8780            # room table, then object streams + door lists
STREAM_END = 0x1FB77F             # inclusive; ledger row
HDR_BASE = 0x04F782               # 14-byte headers
HDR_END = 0x04F8D1
SPR_BASE = 0x09D92E               # sprite lists
SPR_END = 0x09DBCD
ROOM_REC = 32                     # bytes per ROOM TABLE record

# EntranceData tables (bank_02.asm:13125-15440): name -> (base, bytes per row)
ENT = {
    "room_id": (0x02C813, 2), "camera_scroll_boundaries": (0x02C91D, 8), "horizontal_scroll": (0x02CD45, 2),
    "vertical_scroll": (0x02CE4F, 2), "y_coordinate": (0x02CF59, 2), "x_coordinate": (0x02D063, 2),
    "camera_trigger_y": (0x02D16D, 2), "camera_trigger_x": (0x02D277, 2), "main_GFX": (0x02D381, 1),
    "floor": (0x02D406, 1), "dungeon_id": (0x02D48B, 1), "in_door": (0x02D510, 1), "layer": (0x02D595, 1),
    "camera_scroll_controller": (0x02D61A, 1), "quadrant": (0x02D69F, 1),
    "overworld_door_tilemap": (0x02D724, 2), "song": (0x02D82E, 1),
}


class RoomError(Exception):
    pass


def rooms_dir(arg: str | None) -> Path:
    if arg:
        return Path(arg).resolve()
    env = os.environ.get("HUSH_ROOMS_DIR")
    return Path(env).resolve() if env else ROOT / "design" / "rooms"


def load_specs(d: Path) -> list[dict]:
    specs = []
    for p in sorted(d.glob("*.yaml")):
        if p.name.startswith("_"):
            continue
        data = yaml.safe_load(p.read_text())
        if not isinstance(data, dict):
            raise RoomError(f"{p}: not a mapping")
        data["_path"] = p
        specs.append(data)
    return specs


# ---------------------------------------------------------------------------------------------
# One room
# ---------------------------------------------------------------------------------------------
def check_spec(s: dict) -> None:
    name = s["_path"].name
    for k in ("id", "seq", "grid", "guards", "lighting", "tools_given"):
        if k not in s:
            raise RoomError(f"{name}: missing '{k}' (run `make validate`)")
    g = s["grid"]
    if len(g) != GRID_H or any((not isinstance(r, str)) or len(r) != GRID_W for r in g):
        raise RoomError(f"{name}: grid must be {GRID_H} strings of {GRID_W} chars (run `make validate`)")


def cell_kinds(grid: list[str]) -> dict[str, set[tuple[int, int]]]:
    """Split the grid cells that HUSH draws as objects into kinds (see OBJ_KINDS). Never changes which cells are solid:
    `#` and `p` are solid, `X` and everything else are floor.
      ceil   `#` whose cell below is solid or outside the grid (top surface)
      face   `#` whose cell below is a floor cell (S . X guards): the wall's front face
      pillar `p`
      exit   `X`"""
    kinds: dict[str, set[tuple[int, int]]] = {k: set() for k in OBJ_KINDS}
    for r in range(GRID_H):
        for c in range(GRID_W):
            ch = grid[r][c]
            if ch == "#":
                below_floor = r + 1 < GRID_H and grid[r + 1][c] not in "#p"
                kinds["face" if below_floor else "ceil"].add((c, r))
            elif ch == "p":
                kinds["pillar"].add((c, r))
            elif ch == "X":
                kinds["exit"].add((c, r))
    return kinds


def _h(rid: str, cx: int, cy: int, salt: str) -> float:
    """Deterministic pseudo-random number in [0, 1) from the room id, the cell and a salt (stable across runs, platforms and Python versions)."""
    d = hashlib.sha256(f"{rid}/{cx}/{cy}/{salt}".encode()).digest()   # (not CRC32: it is affine, equal-length salts would correlate)
    return int.from_bytes(d[:4], "big") / 0x100000000


def variant_plan(rid: str, grid: list[str], lit: bool) -> dict[tuple[int, int], str]:
    """E5: which cells get which decoration variant (VARIANTS), cell -> name. Never changes solidity: a variant replaces a cell of the SAME base
    kind (floor/ceil/face) with tile ids of the same vanilla tile type. Rules (all deterministic, seeded by room id + cell):
      * torches (lit rooms) / unlit sconces (dark rooms) on wall-face cells, ~every 5th (torch) / 6th (sconce) cell of a face run, never within one
        column of an exit cell below, never above a guard; lit rooms also get a light pool on the floor below each torch (strong below, weak beside
        and one further down; never on S/X/guard cells - static glow near a patrolling guard would give its position away);
      * banners / sigils / cracks on other face cells (at least 3 cells from a torch or another banner); face cells next to a torch are warmed;
      * a contact shadow on the floor cell below every wall face (also S/guard cells, so the line has no gaps; never X), light pools replace it under torches;
      * floor variants on ~21% of the plain floor cells ('.' only: never S, X, guard cells), never directly below a wall cell, never next to another variant;
      * wall-top variants on ~half of the plain wall-top cells."""
    plan: dict[tuple[int, int], str] = {}
    kinds = cell_kinds(grid)
    face, ceil = kinds["face"], kinds["ceil"]

    def ch(c: int, r: int) -> str:
        return grid[r][c] if 0 <= c < GRID_W and 0 <= r < GRID_H else "#"

    # ---- torches / sconces ---------------------------------------------------------------------------------------------
    torch_name = "fc_torch" if lit else "fc_sconce"
    spacing, first = (5, 2) if lit else (6, 3)
    torches: list[tuple[int, int]] = []
    for r in range(GRID_H):
        c = 0
        while c < GRID_W:
            if (c, r) not in face:
                c += 1
                continue
            e = c
            while e < GRID_W and (e, r) in face:
                e += 1
            # run [c, e): candidate offsets first + k*spacing (+ a deterministic 0/1 jitter)
            k = 0
            while True:
                x = c + first + k * spacing + (1 if _h(rid, c, r, "tj%d" % k) < 0.4 else 0)
                if x >= e - 1:
                    break
                k += 1
                if any(ch(x + dx, r + 1) == "X" for dx in (-1, 0, 1)) or ch(x, r + 1) in "abcdefgh":
                    continue
                torches.append((x, r))
                plan[(x, r)] = torch_name
            c = e
    # lit rooms: warm faces beside a torch + the floor light pool (cells that are still plain)
    if lit:
        for (x, r) in torches:
            for dx in (-1, 1):
                if (x + dx, r) in face and (x + dx, r) not in plan:
                    plan[(x + dx, r)] = "fc_warm"
            for dx, dy, name in ((0, 1, "f_glow"), (-1, 1, "f_glow2"), (1, 1, "f_glow2")):
                c2, r2 = x + dx, r + dy
                if ch(c2, r2) == "." and (c2, r2) not in plan:
                    flip = _h(rid, c2, r2, "gf") < 0.5
                    plan[(c2, r2)] = name + ("_h" if flip else "")
    # ---- other face decoration -------------------------------------------------------------------------------------------
    deco: list[tuple[int, int]] = list(torches)
    for r in range(GRID_H):
        for c in range(GRID_W):
            if (c, r) not in face or (c, r) in plan:
                continue
            if any(abs(c - x) < 3 and r == y for x, y in deco):
                continue
            v = _h(rid, c, r, "fd")
            name = "fc_banner" if v < 0.09 else "fc_sigil" if v < 0.15 else "fc_crack" if v < 0.24 else None
            if name:
                plan[(c, r)] = name
                deco.append((c, r))
    # ---- floor variants ----------------------------------------------------------------------------------------------------
    for (c, r) in sorted(face):
        if ch(c, r + 1) in ".Sabcdefgh" and (c, r + 1) not in plan:
            # contact shadow below every face (light pools replace it under torches). S and guard cells get it too (a gap in the shadow line
            # would be a visible mark); the exit marker cell keeps its own tile
            plan[(c, r + 1)] = "f_shadow"
    runes: list[tuple[int, int]] = []
    for r in range(GRID_H):
        for c in range(GRID_W):
            if grid[r][c] != "." or (c, r) in plan:
                continue
            if ch(c, r - 1) in "#p":
                continue
            if _h(rid, c, r, "fv") >= 0.21:
                continue
            if any(plan.get((c + dx, r + dy), "f_shadow") != "f_shadow" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            t = _h(rid, c, r, "ft")
            if t < 0.12 and len(runes) < 2 and all(abs(c - x) + abs(r - y) > 5 for x, y in runes):
                name = "f_rune"
                runes.append((c, r))
            elif t < 0.37:
                name = "f_crack" if _h(rid, c, r, "fs") < 0.5 else "f_crack2"
            elif t < 0.68:
                name = "f_worn"
            else:
                name = "f_moss"
            if name != "f_rune" and _h(rid, c, r, "ff") < 0.5:
                name += "_h"
            plan[(c, r)] = name
    # ---- wall top variants ---------------------------------------------------------------------------------------------------
    for (c, r) in sorted(ceil, key=lambda q: (q[1], q[0])):
        if _h(rid, c, r, "cv") >= 0.55:
            continue
        t = _h(rid, c, r, "ct")
        flip = _h(rid, c, r, "cf") < 0.5
        if t < 0.10:
            name = "ct_crack_h" if flip else "ct_crack"
        elif t < 0.30:
            name = "ct_seam_h" if flip else "ct_seam"
        else:
            name = ("ct_a", "ct_b", "ct_c", "ct_d")[int(t * 100) % 4]
        # the crack / seam art is a 16x16 block of the dark mass: keep it off cells right above a face (the rim there must stay calm)
        if name in ("ct_crack", "ct_crack_h", "ct_seam", "ct_seam_h") and (c, r + 1) in face:
            name = "ct_a"
        plan[(c, r)] = name
    return plan


def cover_runs(cells: set[tuple[int, int]], allow_v: bool = True) -> list[tuple[str, int, int, int]]:
    """Cover `cells` with runs: [(dir, cx, cy, length)], dir in {'h','v'}; length 1..15 (a size field of 0 would mean 32).
    Uses the smaller of a horizontal-run and a vertical-run decomposition (vertical only if allow_v)."""
    def split(n: int) -> list[int]:
        out = []
        while n > 0:
            take = min(n, 15)
            out.append(take)
            n -= take
        return out

    horiz = []
    for r in range(GRID_H):
        c = 0
        while c < GRID_W:
            if (c, r) in cells:
                e = c
                while e < GRID_W and (e, r) in cells:
                    e += 1
                x = c
                for n in split(e - c):
                    horiz.append(("h", x, r, n))
                    x += n
                c = e
            else:
                c += 1
    if not allow_v:
        return horiz
    vert = []
    for c in range(GRID_W):
        r = 0
        while r < GRID_H:
            if (c, r) in cells:
                e = r
                while e < GRID_H and (c, e) in cells:
                    e += 1
                y = r
                for n in split(e - r):
                    vert.append(("v", c, y, n))
                    y += n
                r = e
            else:
                r += 1
    return horiz if len(horiz) <= len(vert) else vert


def solid_runs(grid: list[str]) -> list[tuple[str, str, int, int, int]]:
    """All objects of a room: [(kind, dir, cx, cy, length)] in a fixed kind order."""
    kinds = cell_kinds(grid)
    out = []
    for kind, (_, vid, _) in OBJ_KINDS.items():
        for d, cx, cy, n in cover_runs(kinds[kind], allow_v=vid is not None):
            out.append((kind, d, cx, cy, n))
    return out


def object_bytes(kind: str, d: str, cx: int, cy: int, n: int) -> bytes:
    """Type-1 object: b0 = XXXXXXss, b1 = YYYYYYss, b2 = id; size = (b0&3)<<2 | (b1&3). n = repeats, 1..15
    (field n for the 1to15or32 routines, n-1 for the 1to16 routines)."""
    if kind == "var":                        # E5 variant: n = index into VARIANTS; object id + size field select the table entry
        oid = VARIANT_OBJ_IDS[n // VARIANT_PER_ID]
        size = n % VARIANT_PER_ID
        tx, ty = WIN_TX + cx * 2, WIN_TY + cy * 2
        return bytes([(tx << 2) | ((size >> 2) & 3), (ty << 2) | (size & 3), oid])
    assert 1 <= n <= 15
    hid, vid, sem = OBJ_KINDS[kind]
    oid = hid if d == "h" else vid
    assert oid is not None, f"{kind} has no vertical object"
    size = n if sem == "1to15or32" else n - 1
    tx, ty = WIN_TX + cx * 2, WIN_TY + cy * 2
    b0 = (tx << 2) | ((size >> 2) & 3)
    b1 = (ty << 2) | (size & 3)
    return bytes([b0, b1, oid])


def exit_rects(grid: list[str]) -> list[tuple[int, int, int, int]]:
    """Merge 'X' cells into <= MAX_EXITS pixel rectangles (window-relative, inclusive)."""
    runs = []  # (r, c0, c1)
    for r, row in enumerate(grid):
        c = 0
        while c < GRID_W:
            if row[c] == "X":
                e = c
                while e < GRID_W and row[e] == "X":
                    e += 1
                runs.append([r, c, e - 1, r])  # row0,c0,c1,row1
                c = e
            else:
                c += 1
    merged = []
    for run in runs:
        for m in merged:
            if m[1] == run[1] and m[2] == run[2] and m[3] + 1 == run[0]:
                m[3] = run[0]
                break
        else:
            merged.append(run)
    return [(c0 * CELL, r0 * CELL, c1 * CELL + CELL - 1, r1 * CELL + CELL - 1) for r0, c0, c1, r1 in merged]


def compile_room(s: dict, index: int, cumulative_tools: int) -> dict:
    check_spec(s)
    grid = s["grid"]
    flat = "".join(grid)
    ys, xs = next((r, c) for r in range(GRID_H) for c in range(GRID_W) if grid[r][c] == "S")
    objs = solid_runs(grid)
    lit = s["lighting"] == "lit"
    variants = variant_plan(s["id"], grid, lit)
    for (cx, cy), name in sorted(variants.items(), key=lambda q: (q[0][1], q[0][0])):
        objs.append(("var", "h", cx, cy, VARIANT_INDEX[name]))
    stream = bytearray([FLOOR_BYTE, LAYOUT << 2])
    for kind, d, cx, cy, n in objs:
        stream += object_bytes(kind, d, cx, cy, n)
    stream += b"\xFF\xFF"                    # end of list 1
    stream += b"\xFF\xFF"                    # end of list 2
    stream += b"\xF0\xFF"                    # list 3: door section marker (no doors)
    door_off = len(stream)                   # door pointer points at the door list = the final terminator
    stream += b"\xFF\xFF"

    exits = exit_rects(grid)
    if len(exits) > MAX_EXITS:
        raise RoomError(f"{s['_path'].name}: exit cells form {len(exits)} rectangles, max {MAX_EXITS}")

    guards = {g["id"]: g for g in s["guards"]}
    sprites = bytearray([0x00])              # first byte: 0 (loader copies it to $0FB3)
    glist = []
    for r in range(GRID_H):
        for c in range(GRID_W):
            ch = grid[r][c]
            if ch in "abcdefgh":
                g = guards[ch]
                sub = FACING_SUBTYPE[g["facing"]] | (STILL_SUBTYPE if g["move"] == "still" else 0)
                ux, uy = WIN_X // 16 + c, WIN_Y // 16 + r
                sprites += bytes([(uy & 0x1F) | (((sub >> 3) & 3) << 5), (ux & 0x1F) | ((sub & 7) << 5), SOLDIER_SPRITE])
                glist.append({"id": ch, "cx": c, "cy": r, "facing": g["facing"], "move": g["move"], "type": g["type"]})
    sprites += b"\xFF"

    tools = 0
    for t in s["tools_given"]:
        tools |= TOOL_BITS[t]
    flags = (1 if s["lighting"] == "lit" else 0)
    floor = s["floor"]
    if floor not in (1, 2, 3):
        raise RoomError(f"{name}: floor must be 1, 2 or 3 (picks the palette set), found {floor!r}")
    pal_row = (LIT_PAL_ROWS if flags else DARK_PAL_ROWS)[floor - 1]
    return dict(
        pal_row=pal_row,
        spec=s, index=index, room_id=ROOM_FIRST + index, stream=bytes(stream), door_off=door_off,
        sprites=bytes(sprites), variants=variants, exits=exits, start=(xs, ys), tools=tools, cum_tools=cumulative_tools | tools,
        flags=flags, guards=glist, objs=objs, solid_cells=sum(r.count("#") + r.count("p") for r in grid),
        walkable=sum(1 for ch in flat if ch not in "#p"),
    )


# ---------------------------------------------------------------------------------------------
# Whole set
# ---------------------------------------------------------------------------------------------
def link_pos(room_id: int, cx: int, cy: int, dx: int, dy: int) -> tuple[int, int]:
    """Absolute Link (x, y) for the top-left of cell (cx, cy) + (dx, dy)."""
    base_x, base_y = (room_id & 15) * 512, (room_id >> 4) * 512
    return base_x + WIN_X + cx * CELL + dx, base_y + WIN_Y + cy * CELL + dy


def build_asm(rooms: list[dict]) -> tuple[str, dict]:
    n = len(rooms)
    out: list[str] = []
    w = out.append
    w("; =============================================================================")
    w("; GENERATED by tools/roomgen.py -- DO NOT EDIT. Regenerate with `make rooms`.")
    w(f"; {n} room(s): " + ", ".join(f"{r['spec']['id']}(seq {r['spec']['seq']})" for r in rooms))
    w("; Every org below lies inside a src/FREESPACE.md row (tools/check_freespace.py checks build/rooms_gen.asm).")
    w("; =============================================================================")
    w("")
    w(f"!HUSH_ROOM_COUNT = {n}")
    w(f"!HUSH_ROOM_FIRST = ${ROOM_FIRST:04X}")
    w(f"!HUSH_WIN_X = {WIN_X}")
    w(f"!HUSH_WIN_Y = {WIN_Y}")
    w(f"!HUSH_FEET_DX = {LINK_FEET_DX}")
    w(f"!HUSH_FEET_DY = {LINK_FEET_DY}")
    w(f"!HUSH_ROOM_REC = {ROOM_REC}")
    w("")

    # ---- allocate -------------------------------------------------------------------------
    table_addr = STREAM_BASE
    cur = table_addr + ROOM_REC * n
    obj_addr, hdr_addr, spr_addr = [], [], []
    for r in rooms:
        obj_addr.append(cur)
        cur += len(r["stream"])
    if cur - 1 > STREAM_END:
        raise RoomError(f"object streams + room table need ${cur - STREAM_BASE:X} bytes, budget ${STREAM_END - STREAM_BASE + 1:X} "
                        f"(ledger row ${STREAM_BASE:06X}-${STREAM_END:06X}); enlarge the ledger row or simplify rooms")
    stream_used = cur - STREAM_BASE
    hcur = HDR_BASE
    for _ in rooms:
        hdr_addr.append(hcur)
        hcur += 14
    if hcur - 1 > HDR_END:
        raise RoomError(f"room headers need {hcur - HDR_BASE} bytes, budget {HDR_END - HDR_BASE + 1}")
    scur = SPR_BASE
    for r in rooms:
        spr_addr.append(scur)
        scur += len(r["sprites"])
    if scur - 1 > SPR_END:
        raise RoomError(f"sprite lists need {scur - SPR_BASE} bytes, budget {SPR_END - SPR_BASE + 1}")

    def hexlist(bs: bytes) -> str:
        return ", ".join(f"${b:02X}" for b in bs)

    # ---- ROOM TABLE ----------------------------------------------------------------------
    w("; ---- ROOM TABLE (engine runtime data, ROOM_REC bytes per room) ----")
    w("; +0..15 exit rects x4 [x0,y0,x1,y1] window px inclusive (unused: $FF,$FF,$00,$00)  +16 start x  +17 start y")
    w("; +18 cumulative tools mask (1 knife, 2 darts, 4 ink)  +19 flags (bit0 lit, bit7 last room)  +20 guard count")
    w("; +21 this room's own tools mask  +22 floor (1..3)  +23 seq")
    w(f"org ${table_addr:06X}")
    w("Hush_RoomTable:")
    for r in rooms:
        rec = bytearray()
        ex = list(r["exits"]) + [(0xFF, 0xFF, 0x00, 0x00)] * (MAX_EXITS - len(r["exits"]))
        for e in ex:
            rec += bytes(e)
        sx, sy = r["start"]
        rec += bytes([sx * CELL, sy * CELL])
        last = 0x80 if r["index"] == n - 1 else 0
        rec += bytes([r["cum_tools"], r["flags"] | last, len(r["guards"]), r["tools"], r["spec"]["floor"] & 0xFF, r["spec"]["seq"] & 0xFF])
        rec += bytes(ROOM_REC - len(rec))
        w(f"    db {hexlist(rec[:16])}")
        w(f"    db {hexlist(rec[16:])}    ; room {r['index']} {r['spec']['id']} (id ${r['room_id']:03X})")
    w("")

    # ---- object streams ------------------------------------------------------------------
    w("; ---- object streams + door lists (vanilla room data of unreachable rooms, in place) ----")
    for r, a in zip(rooms, obj_addr):
        w(f"org ${a:06X}")
        w(f"Hush_Room{r['index']}_Objects:    ; {r['spec']['id']}: {len(r['objs'])} object(s), {len(r['stream'])} bytes")
        s = r["stream"]
        for i in range(0, len(s), 16):
            w(f"    db {hexlist(s[i:i + 16])}")
    w("")

    # ---- pointer tables ------------------------------------------------------------------
    def ptr_rows(title: str, base: int, size: int, vals: list[int]) -> None:
        start = base + size * ROOM_FIRST
        w(f"; ---- {title}: rooms ${ROOM_FIRST:03X}..${ROOM_FIRST + n - 1:03X} ----")
        w(f"org ${start:06X}")
        d = "dl" if size == 3 else "dw"
        w(f"    {d} " + ", ".join(f"${v:06X}" if size == 3 else f"${v & 0xFFFF:04X}" for v in vals))
        w("")

    ptr_rows("RoomData_ObjectDataPointers ($1F8000, 3 bytes)", OBJ_PTR, 3, obj_addr)
    ptr_rows("RoomData_DoorDataPointers ($1F83C0, 3 bytes)", DOOR_PTR, 3, [a + r["door_off"] for r, a in zip(rooms, obj_addr)])
    ptr_rows("RoomHeaderPointers ($04F502, 2 bytes, bank 04)", HDR_PTR, 2, hdr_addr)
    ptr_rows("RoomData_SpritePointers ($09D62E, 2 bytes, bank 09)", SPR_PTR, 2, spr_addr)

    # ---- headers -------------------------------------------------------------------------
    w("; ---- room headers (14 bytes; vanilla header region of bank 04) ----")
    w("; b0 = bg2mode<<5 | collision<<2 | dark(bit0)  b1 = palette set (UnderworldPaletteSets row: floor 1-3 dark = 0-2, lit = 3-5)  b2 = blockset  b3 = sprite gfx set  b4..b13 = 0")
    for r, a in zip(rooms, hdr_addr):
        w(f"org ${a:06X}")
        w(f"    db $00, ${r['pal_row']:02X}, $00, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00    ; room {r['index']} {r['spec']['id']} (floor {r['spec']['floor']}, {r['spec']['lighting']}: pal_dungeon_{r['pal_row']:02d})")
    w("")

    # ---- sprite lists --------------------------------------------------------------------
    w("; ---- sprite lists (vanilla sprite-list region of bank 09) ----")
    for r, a in zip(rooms, spr_addr):
        w(f"org ${a:06X}")
        w(f"    db {hexlist(r['sprites'])}    ; room {r['index']} {r['spec']['id']}: {len(r['guards'])} guard(s)")
    w("")

    # ---- E5 variant tile table (RoomDrawObjectData of the unused diagonal objects $09/$0A, see src/hooks/room_visuals.asm) ------------
    w("; ---- E5 variant tile words: 8 bytes per variant = TL, BL, TR, BR (RoomDraw_Rightwards2x2 order); object $09 = variants 0-15, $0A = 16-31 ----")
    w(f"org ${VARIANT_DATA_ROM:06X}")
    for i, (name, kind, (tl, tr, bl, br)) in enumerate(VARIANTS):
        w(f"    dw ${tl:04X}, ${bl:04X}, ${tr:04X}, ${br:04X}    ; {i:2d} ${VARIANT_OBJ_IDS[i // VARIANT_PER_ID]:02X}/{i % VARIANT_PER_ID:<2d} {name} (replaces a '{kind}' cell)")
    w("")

    # ---- EntranceData rows ---------------------------------------------------------------
    w("; ---- EntranceData rows 0..N-1 (entrance k loads room k; LoadUnderworldEntrance, bank_02.asm:15456) ----")
    rows: dict[str, list[bytes]] = {k: [] for k in ENT}
    for r in rooms:
        rid = r["room_id"]
        base_x, base_y = (rid & 15) * 512, (rid >> 4) * 512
        sx, sy = r["start"]
        lx, ly = link_pos(rid, sx, sy, LINK_START_DX, LINK_START_DY)
        ry2, rx2 = (rid >> 4) * 2, (rid & 15) * 2
        le = lambda v: (v & 0xFFFF).to_bytes(2, "little")  # noqa: E731
        rows["room_id"].append(le(rid))
        rows["camera_scroll_boundaries"].append(bytes([ry2 + 1, ry2, ry2 + 1, ry2 + 1, rx2 + 1, rx2 + 1, rx2 + 1, rx2 + 2]))
        rows["horizontal_scroll"].append(le(base_x + WIN_X))
        rows["vertical_scroll"].append(le(base_y + WIN_Y))
        rows["y_coordinate"].append(le(ly))
        rows["x_coordinate"].append(le(lx))
        rows["camera_trigger_y"].append(le(0x0187))
        rows["camera_trigger_x"].append(le(0x017F))
        rows["main_GFX"].append(bytes([0x04]))
        rows["floor"].append(bytes([0x00]))
        rows["dungeon_id"].append(bytes([0xFF]))
        rows["in_door"].append(bytes([0x00]))
        rows["layer"].append(bytes([0x00]))
        rows["camera_scroll_controller"].append(bytes([0x00]))
        rows["quadrant"].append(bytes([0x02]))
        rows["overworld_door_tilemap"].append(le(0x0000))
        rows["song"].append(bytes([0xFF]))
    for name, (base, size) in ENT.items():
        w(f"org ${base:06X}    ; EntranceData.{name}")
        data = b"".join(rows[name])
        for i in range(0, len(data), size * 8):
            w(f"    db {hexlist(data[i:i + size * 8])}")
    w("")
    stats = dict(stream_used=stream_used, stream_budget=STREAM_END - STREAM_BASE + 1, hdr_used=hcur - HDR_BASE,
                 hdr_budget=HDR_END - HDR_BASE + 1, spr_used=scur - SPR_BASE, spr_budget=SPR_END - SPR_BASE + 1,
                 table_bytes=ROOM_REC * n)
    return "\n".join(out) + "\n", stats


def build_report(rooms: list[dict], stats: dict, src: Path) -> str:
    out = [f"HUSH rooms report  (source: {src})", f"{len(rooms)} room(s)", ""]
    for r in rooms:
        s = r["spec"]
        kind_counts = ", ".join("%s %d" % (k, sum(1 for o in r["objs"] if o[0] == k)) for k in (*OBJ_KINDS, "var"))
        out.append(f"== room {r['index']}  {s['id']}  seq {s['seq']}  id ${r['room_id']:03X}  floor {s['floor']}  {s['lighting']}  "
                   f"tools(cum) {r['cum_tools']:03b}")
        for row in s["grid"]:
            out.append("   " + row)
        out.append(f"   solid cells {r['solid_cells']}, walkable cells {r['walkable']} (of {GRID_W * GRID_H}); "
                   f"{len(r['objs'])} tile object(s) ({kind_counts}); palette set {r['pal_row']}; stream {len(r['stream'])} B, sprites {len(r['sprites'])} B")
        out.append(f"   start cell {r['start']}, exit rect(s) px {r['exits']}, guards {[(g['id'], g['cx'], g['cy'], g['facing'], g['move']) for g in r['guards']]}")
        out.append("")
    out.append(f"object streams + room table: {stats['stream_used']} / {stats['stream_budget']} bytes (room table {stats['table_bytes']})")
    out.append(f"headers: {stats['hdr_used']} / {stats['hdr_budget']} bytes")
    out.append(f"sprite lists: {stats['spr_used']} / {stats['spr_budget']} bytes")
    return "\n".join(out) + "\n"


def build_lua(rooms: list[dict]) -> str:
    out = ["-- GENERATED by tools/roomgen.py (make rooms). Link coordinates are absolute, like $7E0020/$7E0022.",
           f"return {{ first_id = 0x{ROOM_FIRST:X}, count = {len(rooms)}, win_x = {WIN_X}, win_y = {WIN_Y},",
           f"  feet_dx = {LINK_FEET_DX}, feet_dy = {LINK_FEET_DY},",
           "  variant_words = {" + ", ".join("%s = {0x%04X, 0x%04X, 0x%04X, 0x%04X}" % ((name,) + tuple(words)) for name, _, words in VARIANTS) + "},",
           "  variant_kind = {" + ", ".join("%s = '%s'" % (name, kind) for name, kind, _ in VARIANTS) + "},",
           "  rooms = {"]
    for r in rooms:
        rid = r["room_id"]
        sx, sy = r["start"]
        lx, ly = link_pos(rid, sx, sy, LINK_START_DX, LINK_START_DY)
        base_x, base_y = (rid & 15) * 512, (rid >> 4) * 512
        ex = ", ".join(f"{{{base_x + WIN_X + a}, {base_y + WIN_Y + b}, {base_x + WIN_X + c}, {base_y + WIN_Y + d}}}" for a, b, c, d in r["exits"])
        grid = ", ".join('"%s"' % row for row in r["spec"]["grid"])
        gs = ", ".join(
            "{id='%s', x=%d, y=%d, facing='%s', move='%s'}" % ((g["id"],) + link_pos(rid, g["cx"], g["cy"], 0, 0) + (g["facing"], g["move"]))
            for g in r["guards"])
        var = ", ".join("{%d, %d, '%s'}" % (cx, cy, nm) for (cx, cy), nm in sorted(r["variants"].items(), key=lambda q: (q[0][1], q[0][0])))
        out.append(f"  {{ id='{r['spec']['id']}', variants={{{var}}}, seq={r['spec']['seq']}, room_id=0x{rid:X}, start_x={lx}, start_y={ly}, "
                   f"tools=0x{r['cum_tools']:X}, own_tools=0x{r['tools']:X}, floor={r['spec']['floor']}, pal_set={r['pal_row']}, lit={'true' if r['flags'] & 1 else 'false'}, "
                   f"base_x={base_x}, base_y={base_y},\n    exits={{{ex}}}, guards={{{gs}}},\n    grid={{{grid}}} }},")
    out.append("} }")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rooms-dir", help="directory of room specs (default $HUSH_ROOMS_DIR or design/rooms)")
    ap.add_argument("--out-dir", default=str(BUILD_DIR))
    args = ap.parse_args()

    d = rooms_dir(args.rooms_dir)
    specs = load_specs(d)
    if not specs and not args.rooms_dir and not os.environ.get("HUSH_ROOMS_DIR"):
        fb = ROOT / "tests" / "dev" / "rooms"
        print(f"roomgen: NOTE no room specs in {d.relative_to(ROOT)}; using the dev rooms in {fb.relative_to(ROOT)}")
        d = fb
        specs = load_specs(d)
    if not specs:
        die(f"roomgen: no room specs in {d}")
    try:
        specs.sort(key=lambda s: s["seq"])
        seqs = [s["seq"] for s in specs]
        if seqs != list(range(1, len(specs) + 1)):
            raise RoomError(f"seq must be contiguous 1..{len(specs)}, found {seqs}")
        if len(specs) > MAX_ROOMS:
            raise RoomError(f"{len(specs)} rooms; at most {MAX_ROOMS} fit room ids ${ROOM_FIRST:03X}..$13F")
        rooms, cum = [], 0
        for i, s in enumerate(specs):
            r = compile_room(s, i, cum)
            cum = r["cum_tools"]
            rooms.append(r)
        asm, stats = build_asm(rooms)
    except (RoomError, KeyError) as ex:
        die(f"roomgen: {ex}")

    out = Path(args.out_dir)
    out.mkdir(exist_ok=True)
    (out / "rooms_gen.asm").write_text(asm)
    (out / "rooms_report.txt").write_text(build_report(rooms, stats, d))
    (out / "rooms_gen.lua").write_text(build_lua(rooms))
    print(f"roomgen: {len(rooms)} room(s) from {d.relative_to(ROOT) if d.is_relative_to(ROOT) else d}: "
          f"streams {stats['stream_used']}/{stats['stream_budget']} B, headers {stats['hdr_used']}/{stats['hdr_budget']} B, "
          f"sprites {stats['spr_used']}/{stats['spr_budget']} B")
    return 0


if __name__ == "__main__":
    sys.exit(main())
