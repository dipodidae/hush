#!/usr/bin/env python3
"""Validate design/rooms/*.yaml against the HUSH room-spec schema.

Rules:
  * required fields present, correct types, no unknown keys;
  * id == file stem and unique; lighting in {lit, dark}; guard facing valid;
  * status in {draft, specified, built};
  * status == built  =>  solution_inputs must point to an existing file;
  * design/rooms/_template.yaml must itself contain every field (so the
    template cannot drift from the schema);
  * E1 additions (consumed by tools/roomgen.py): `seq` (1..N unique, contiguous across
    all rooms) and `grid` (14 strings x 16 chars, see GRID_SYMBOLS); every guard carries
    `id` (a-h, matches one grid letter) and `move` (patrol|still).

Exit 0 = ok, 1 = problems.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE_DIR = ROOT / "design" / "rooms"
# HUSH_ROOMS_DIR (also read by tools/roomgen.py) validates another directory, e.g. tests/dev/rooms
ROOMS = Path(os.environ["HUSH_ROOMS_DIR"]).resolve() if os.environ.get("HUSH_ROOMS_DIR") else TEMPLATE_DIR

STATUSES = {"draft", "specified", "built"}
LIGHTING = {"lit", "dark"}
FACING = {"up", "down", "left", "right"}
TOOLS = {"shade_knife", "hush_darts", "ink_pots"}
ID_RE = re.compile(r"^[a-z0-9_]+$")
MOVES = {"patrol", "still"}
GUARD_IDS = "abcdefgh"
GRID_ROWS, GRID_COLS = 14, 16
# one char = one 16x16 px cell of the visible 256x224 window
GRID_SYMBOLS = "#.SXp" + GUARD_IDS

# field -> (python type(s), required)
FIELDS = {
    "id": (str, True),
    "status": (str, True),
    "seq": (int, True),
    "floor": (int, True),
    "teaches": (str, True),
    "layout": (str, True),
    "grid": (list, True),
    "lighting": (str, True),
    "guards": (list, True),
    "tools_given": (list, True),
    "intended_solution": (str, True),
    "solution_inputs": (str, True),
    "par_time_sec": ((int, float), True),
    "ghost_possible": (bool, True),
    "must_not": (list, True),
}


def rel(path: Path) -> Path:
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def check_grid(data: dict, gids: list, err) -> None:
    grid = data["grid"]
    if len(grid) != GRID_ROWS:
        err(f"grid must have exactly {GRID_ROWS} rows (has {len(grid)})")
        return
    ok = True
    for r, row in enumerate(grid):
        if not isinstance(row, str) or len(row) != GRID_COLS:
            err(f"grid row {r} must be a string of exactly {GRID_COLS} chars "
                f"(quote it in YAML: a bare '#' starts a comment)")
            ok = False
        elif set(row) - set(GRID_SYMBOLS):
            err(f"grid row {r}: illegal symbol(s) {sorted(set(row) - set(GRID_SYMBOLS))} (allowed: {GRID_SYMBOLS})")
            ok = False
    if not ok:
        return
    for r in (0, 1, GRID_ROWS - 1):
        if set(grid[r]) != {"#"}:
            err(f"grid row {r} must be all '#' (rows 0-1 are under the HUD, row {GRID_ROWS - 1} is the bottom wall)")
    for r in range(GRID_ROWS):
        if grid[r][0] != "#" or grid[r][GRID_COLS - 1] != "#":
            err(f"grid row {r}: columns 0 and {GRID_COLS - 1} must be '#'")
    flat = "".join(grid)
    if flat.count("S") != 1:
        err(f"grid needs exactly one 'S' (player start), found {flat.count('S')}")
    if flat.count("X") < 1:
        err("grid needs at least one 'X' (exit cell)")
    letters = [c for c in flat if c in GUARD_IDS]
    if len(set(letters)) != len(letters):
        err("each guard letter may appear in the grid at most once")
    if set(letters) != {g for g in gids if g}:
        err(f"grid guard letters {sorted(set(letters))} must match guards[].id {sorted(g for g in gids if g)}")
    # reachability is advisory (guards stand on floor; Link needs a 4-connected path S -> every X)
    solid = {"#", "p"}
    start = next(((r, c) for r in range(GRID_ROWS) for c in range(GRID_COLS) if grid[r][c] == "S"), None)
    if start:
        seen, todo = {start}, [start]
        while todo:
            r, c = todo.pop()
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (r + dr, c + dc)
                if 0 <= n[0] < GRID_ROWS and 0 <= n[1] < GRID_COLS and n not in seen and grid[n[0]][n[1]] not in solid:
                    seen.add(n)
                    todo.append(n)
        lost = [(r, c) for r in range(GRID_ROWS) for c in range(GRID_COLS) if grid[r][c] == "X" and (r, c) not in seen]
        if lost:
            err(f"grid: exit cell(s) (row,col) {lost} are not reachable from S through floor cells")


def check_room(path: Path, data: object, errors: list[str]) -> None:
    relp = rel(path)

    local: list[str] = []

    def err(msg: str) -> None:
        local.append(f"{relp}: {msg}")

    if not isinstance(data, dict):
        err("top level must be a mapping")
        errors.extend(local)
        return
    for key in data:
        if key not in FIELDS:
            err(f"unknown field '{key}' (allowed: {', '.join(FIELDS)})")
    for key, (typ, required) in FIELDS.items():
        if key not in data:
            if required:
                err(f"missing required field '{key}'")
            continue
        val = data[key]
        if typ is int and isinstance(val, bool):
            err(f"'{key}' must be an integer")
        elif not isinstance(val, typ):
            tn = typ.__name__ if isinstance(typ, type) else "/".join(t.__name__ for t in typ)
            err(f"'{key}' must be {tn}, got {type(val).__name__}")
    if local:
        # structural problems make the semantic checks below unreliable
        errors.extend(local)
        return

    if not ID_RE.match(data["id"]):
        err(f"id '{data['id']}' must match [a-z0-9_]+")
    if data["id"] != path.stem:
        err(f"id '{data['id']}' must equal the file name '{path.stem}'")
    if data["status"] not in STATUSES:
        err(f"status must be one of {sorted(STATUSES)}")
    if not 1 <= data["floor"] <= 3:
        err("floor must be 1..3")
    if data["lighting"] not in LIGHTING:
        err(f"lighting must be one of {sorted(LIGHTING)}")
    for k in ("teaches", "layout", "intended_solution", "solution_inputs"):
        if not data[k].strip():
            err(f"'{k}' must not be empty")
    if data["par_time_sec"] <= 0:
        err("par_time_sec must be > 0")

    for i, g in enumerate(data["guards"]):
        if not isinstance(g, dict):
            err(f"guards[{i}] must be a mapping with type/patrol/facing")
            continue
        for k in ("type", "patrol", "facing", "id", "move"):
            if k not in g:
                err(f"guards[{i}] missing '{k}'")
        extra = set(g) - {"type", "patrol", "facing", "id", "move"}
        if extra:
            err(f"guards[{i}] unknown field(s): {sorted(extra)}")
        if "type" in g and not (isinstance(g["type"], str) and g["type"].strip()):
            err(f"guards[{i}].type must be a non-empty string")
        if "patrol" in g and not isinstance(g["patrol"], (str, list)):
            err(f"guards[{i}].patrol must be prose or a list of waypoints")
        if "facing" in g and g["facing"] not in FACING:
            err(f"guards[{i}].facing must be one of {sorted(FACING)}")
        if "id" in g and not (isinstance(g["id"], str) and len(g["id"]) == 1 and g["id"] in GUARD_IDS):
            err(f"guards[{i}].id must be one letter a-h")
        if "move" in g and g["move"] not in MOVES:
            err(f"guards[{i}].move must be one of {sorted(MOVES)}")
    gids = [g.get("id") for g in data["guards"] if isinstance(g, dict)]
    if len(set(gids)) != len(gids):
        err("guards[].id values must be unique")
    if data["seq"] < 1:
        err("seq must be >= 1")
    check_grid(data, gids, err)

    for t in data["tools_given"]:
        if t not in TOOLS:
            err(f"tools_given: unknown tool '{t}' (allowed: {sorted(TOOLS)})")
    for i, m in enumerate(data["must_not"]):
        if not (isinstance(m, str) and m.strip()):
            err(f"must_not[{i}] must be a non-empty string")

    if data["status"] == "built":
        sol = ROOT / data["solution_inputs"]
        if not sol.is_file():
            err(f"status is 'built' but solution_inputs '{data['solution_inputs']}' does not exist")
    errors.extend(local)


def main() -> int:
    errors: list[str] = []
    template = TEMPLATE_DIR / "_template.yaml"
    if not template.exists():
        errors.append("design/rooms/_template.yaml is missing")
    else:
        t = yaml.safe_load(template.read_text())
        if not isinstance(t, dict) or set(t) != set(FIELDS):
            missing = sorted(set(FIELDS) - set(t or {}))
            extra = sorted(set(t or {}) - set(FIELDS))
            errors.append(f"_template.yaml out of sync with schema (missing {missing}, extra {extra})")

    ids: dict[str, Path] = {}
    seqs: dict[int, Path] = {}
    rooms = sorted(p for p in ROOMS.glob("*.yaml") if not p.name.startswith("_"))
    for p in rooms:
        try:
            data = yaml.safe_load(p.read_text())
        except yaml.YAMLError as ex:
            errors.append(f"{rel(p)}: invalid YAML: {ex}")
            continue
        check_room(p, data, errors)
        if isinstance(data, dict) and "id" in data:
            if data["id"] in ids:
                errors.append(f"{rel(p)}: duplicate id '{data['id']}' (also {ids[data['id']].name})")
            ids[data["id"]] = p
        if isinstance(data, dict) and isinstance(data.get("seq"), int) and not isinstance(data["seq"], bool):
            if data["seq"] in seqs:
                errors.append(f"{rel(p)}: duplicate seq {data['seq']} (also {seqs[data['seq']].name})")
            seqs[data["seq"]] = p

    if seqs and sorted(seqs) != list(range(1, len(seqs) + 1)):
        errors.append(f"seq values must be contiguous 1..{len(seqs)}, found {sorted(seqs)}")

    if errors:
        print("SPEC VALIDATION FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    built = 0
    for p in rooms:
        built += yaml.safe_load(p.read_text()).get("status") == "built"
    print(f"specs: template ok, {len(rooms)} room(s) validated ({built} built)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
