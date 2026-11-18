#!/usr/bin/env python3
"""Validate design/rooms/*.yaml against the HUSH room-spec schema.

Rules:
  * required fields present, correct types, no unknown keys;
  * id == file stem and unique; lighting in {lit, dark}; guard facing valid;
  * status in {draft, specified, built};
  * status == built  =>  solution_inputs must point to an existing file;
  * design/rooms/_template.yaml must itself contain every field (so the
    template cannot drift from the schema).

Exit 0 = ok, 1 = problems.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "design" / "rooms"

STATUSES = {"draft", "specified", "built"}
LIGHTING = {"lit", "dark"}
FACING = {"up", "down", "left", "right"}
TOOLS = {"shade_knife", "hush_darts", "ink_pots"}
ID_RE = re.compile(r"^[a-z0-9_]+$")

# field -> (python type(s), required)
FIELDS = {
    "id": (str, True),
    "status": (str, True),
    "floor": (int, True),
    "teaches": (str, True),
    "layout": (str, True),
    "lighting": (str, True),
    "guards": (list, True),
    "tools_given": (list, True),
    "intended_solution": (str, True),
    "solution_inputs": (str, True),
    "par_time_sec": ((int, float), True),
    "ghost_possible": (bool, True),
    "must_not": (list, True),
}


def check_room(path: Path, data: object, errors: list[str]) -> None:
    rel = path.relative_to(ROOT)

    local: list[str] = []

    def err(msg: str) -> None:
        local.append(f"{rel}: {msg}")

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
        for k in ("type", "patrol", "facing"):
            if k not in g:
                err(f"guards[{i}] missing '{k}'")
        extra = set(g) - {"type", "patrol", "facing"}
        if extra:
            err(f"guards[{i}] unknown field(s): {sorted(extra)}")
        if "type" in g and not (isinstance(g["type"], str) and g["type"].strip()):
            err(f"guards[{i}].type must be a non-empty string")
        if "patrol" in g and not isinstance(g["patrol"], (str, list)):
            err(f"guards[{i}].patrol must be prose or a list of waypoints")
        if "facing" in g and g["facing"] not in FACING:
            err(f"guards[{i}].facing must be one of {sorted(FACING)}")

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
    template = ROOMS / "_template.yaml"
    if not template.exists():
        errors.append("design/rooms/_template.yaml is missing")
    else:
        t = yaml.safe_load(template.read_text())
        if not isinstance(t, dict) or set(t) != set(FIELDS):
            missing = sorted(set(FIELDS) - set(t or {}))
            extra = sorted(set(t or {}) - set(FIELDS))
            errors.append(f"_template.yaml out of sync with schema (missing {missing}, extra {extra})")

    ids: dict[str, Path] = {}
    rooms = sorted(p for p in ROOMS.glob("*.yaml") if not p.name.startswith("_"))
    for p in rooms:
        try:
            data = yaml.safe_load(p.read_text())
        except yaml.YAMLError as ex:
            errors.append(f"{p.relative_to(ROOT)}: invalid YAML: {ex}")
            continue
        check_room(p, data, errors)
        if isinstance(data, dict) and "id" in data:
            if data["id"] in ids:
                errors.append(f"{p.relative_to(ROOT)}: duplicate id '{data['id']}' (also {ids[data['id']].name})")
            ids[data["id"]] = p

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
