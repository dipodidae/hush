#!/usr/bin/env python3
"""Debug helper (QA): why was Link noticed in a recording? Prints the frames around the first awareness change of
build/rec/<id>/dev_record_room/rec.csv and what the planner's vision model says for the same positions."""
import csv, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import solve_rooms as sr

rid = sys.argv[1]
before = int(sys.argv[2]) if len(sys.argv) > 2 else 12
rooms = {r.id: r for r in sr.load_rooms()}
room = rooms[rid]
rows = list(csv.reader(open(sr.ROOT / f"build/rec/{rid}/dev_record_room/rec.csv")))
rows = [[int(v) for v in r] for r in rows]
ng = len(room.guards)
first = next((i for i, r in enumerate(rows) if any(r[8 + 5 * k] in (1, 2) for k in range(ng))), None)
if first is None:
    print("no awareness change"); sys.exit()
for r in rows[max(0, first - before):first + 3]:
    f, g, lx, ly, ld = r[:5]
    out = [f"f{f} g{g} link({lx},{ly})"]
    for k in range(ng):
        gx, gy, gd, aw, st = r[5 + 5 * k:10 + 5 * k]
        model = sr.sees(room, gx, gy, gd, lx, ly, None)
        out.append(f"G{k}({gx},{gy} d{gd} a{aw}{' MODEL-SEES' if model else ''} dx{(lx+8)-(gx+8)} dy{(ly+16)-(gy+8)})")
    print(" ".join(out))
