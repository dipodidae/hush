#!/usr/bin/env python3
"""HUSH solution planner (QA): finds timing for hand-written route skeletons and records real input scripts.

  tools/solve_rooms.py traces [--rooms r01 r02]   record unperturbed guard traces (build/traces/ghost_<idx>.csv) in MesenCE
  tools/solve_rooms.py plan r02                   plan only: print the schedule found by the model
  tools/solve_rooms.py solve r02 [r03 ...|all]    plan, record in MesenCE (tests/dev/record_room.lua), write tests/solutions/<id>.inputs

The route skeletons are in tools/room_plans.py (one per room, derived from design/rooms/<id>.yaml intended_solution). This tool
only searches WHEN to go (waiting at safe cells); the model is the vision/AI rules of docs/engine_notes.md section 11, ported from
src/hooks/guard_vision.asm, driven by recorded guard traces. The recorder is the ground truth: a plan counts only when the real
ROM runs it without any guard noticing (max awareness 0) and the exit is reached.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

TRACE_DIR = ROOT / "build" / "traces"
PLAN_DIR = ROOT / "build" / "plans"
SOL_DIR = ROOT / "tests" / "solutions"
LINK_SPEED = 1.5          # px per frame, measured (positive: floor(1.5 n), negative: ceil(1.5 n)) per run of held frames
SEG_OVERHEAD = 2          # frames per walked segment for the recorder's exact alignment taps (model margin)
SLEEP_FRAMES = 479        # dart sleep, measured by smoke/ai_darts
CLOUD_DELAY = 157         # pot placed -> cloud appears (measured by smoke/ai_ink)
CLOUD_FRAMES = 300
POT_OFFSET = {"right": (22, 12), "left": (0, 12), "down": (8, 24), "up": (8, 4)}   # cloud centre minus Link's (x, y), measured
DART_DELAY = 13           # press -> hit = t + 13 + dist / 3 (measured: 112 px 51 frames, 192 px 78 frames)
DART_SPEED = 3.0          # px per frame


# ---------------------------------------------------------------------------------------------------------------------
# rooms from build/rooms_gen.lua (tools/roomgen.py output; absolute Link coordinates)
# ---------------------------------------------------------------------------------------------------------------------
def _parse_lua(src: str):
    pos = 0
    tok = re.compile(r"\s*(?:(0x[0-9A-Fa-f]+|-?\d+)|'([^']*)'|\"([^\"]*)\"|(true|false)|([A-Za-z_]\w*)|([{}=,]))")

    def nxt():
        nonlocal pos
        m = tok.match(src, pos)
        if not m:
            return None
        pos = m.end()
        return m

    def value():
        m = nxt()
        if m is None:
            raise ValueError("lua parse error at %d" % pos)
        if m.group(1) is not None:
            return int(m.group(1), 0)
        if m.group(2) is not None:
            return m.group(2)
        if m.group(3) is not None:
            return m.group(3)
        if m.group(4) is not None:
            return m.group(4) == "true"
        if m.group(6) == "{":
            return table()
        raise ValueError("unexpected token %r" % m.group(0))

    def table():
        arr, rec = [], {}
        while True:
            save = pos
            m = nxt()
            if m.group(6) == "}":
                break
            if m.group(6) == ",":
                continue
            nonlocal_pos = pos
            if m.group(5) is not None:
                m2 = nxt()
                if m2 and m2.group(6) == "=":
                    rec[m.group(5)] = value()
                    continue
            # plain value: re-parse from the saved position
            reset(save)
            arr.append(value())
        return rec if rec and not arr else (arr if not rec else {**rec, "_": arr})

    def reset(p):
        nonlocal pos
        pos = p

    m = re.search(r"return\s*", src)
    pos = m.end()
    return value()


class Room:
    def __init__(self, d: dict, idx: int, meta: dict):
        self.d = d
        self.idx = idx
        self.id = d["id"]
        self.lit = d["lit"]
        self.base_x, self.base_y = d["base_x"], d["base_y"]
        self.start = (d["start_x"], d["start_y"])
        self.grid = d["grid"]
        self.guards = d["guards"] if isinstance(d["guards"], list) else [d["guards"]]
        self.exits = d["exits"]
        self.range = 128 if self.lit else 80
        self.tools = d["tools"]
        self.solid = [[False] * 64 for _ in range(64)]
        for cy, row in enumerate(self.grid):
            for cx, ch in enumerate(row):
                if ch in "#pOW":
                    for ty in (18 + 2 * cy, 19 + 2 * cy):
                        for tx in (16 + 2 * cx, 17 + 2 * cx):
                            self.solid[ty][tx] = True

    def cell(self, cx: int, cy: int, dx: int = 0, dy: int = 0):
        """Link position (x, y) that stands exactly in cell (cx, cy), plus an optional pixel offset (dx, dy)."""
        return (self.base_x + 128 + 16 * cx + dx, self.base_y + 144 + 16 * cy - 8 + dy)

    def is_solid_px(self, x: int, y: int) -> bool:
        return self.solid[(y & 0x1FF) >> 3][(x & 0x1FF) >> 3]


def load_rooms() -> list[Room]:
    src = (ROOT / "build" / "rooms_gen.lua").read_text()
    meta = _parse_lua(src)
    rooms = meta["rooms"]
    return [Room(r, i, meta) for i, r in enumerate(rooms)]


# ---------------------------------------------------------------------------------------------------------------------
# guard traces
# ---------------------------------------------------------------------------------------------------------------------
class Trace:
    """Guard positions per GAME frame (one tick of $1A), from build/traces/ghost_<idx>.csv (tests/dev/trace_room.lua)."""

    def __init__(self, room: Room):
        p = TRACE_DIR / f"ghost_{room.idx}.csv"
        if not p.exists():
            raise SystemExit(f"{p} missing: run `tools/solve_rooms.py traces`")
        ng = len(room.guards)
        self.g = [[] for _ in room.guards]
        self.lag = 0
        gt, last = 0, None
        with open(p) as f:
            for row in csv.reader(f):
                r = [int(v) for v in row]
                fc = r[9 + 5 * ng]
                if last is not None:
                    d = (fc - last) & 0xFF
                    gt += d
                    if d == 0:
                        self.lag += 1
                        continue
                last = fc
                for k in range(ng):
                    b = 9 + 5 * k
                    arr = self.g[k]
                    while len(arr) <= gt:
                        arr.append((r[b], r[b + 1], r[b + 2]))
                    arr[gt] = (r[b], r[b + 1], r[b + 2])
        self.n = len(self.g[0])

    def at(self, k: int, f: int):
        a = self.g[k]
        return a[min(max(f, 0), self.n - 1)]


# ---------------------------------------------------------------------------------------------------------------------
# vision (ported from src/hooks/guard_vision.asm Hush_Vision, mode 0)
# ---------------------------------------------------------------------------------------------------------------------
def sees(room: Room, gx: int, gy: int, gdir: int, lx: int, ly: int, cloud, mode: int = 0) -> bool:
    Gx, Gy = gx + 8, gy + 8
    dx = (lx + 8) - Gx
    dy = (ly + 16) - Gy
    adx, ady = abs(dx), abs(dy)
    major = max(adx, ady)
    if major > room.range:
        return False
    if mode == 0:
        if gdir < 2:
            if adx < ady:
                return False
            if gdir == 0:
                if dx < 0:
                    return False
            elif dx >= 0:
                return False
        else:
            if ady < adx:
                return False
            if gdir == 2:
                if dy < 0:
                    return False
            elif dy >= 0:
                return False
    px, py = Gx, Gy
    if major:
        rx = ((adx << 8) // (major & 0xFF)) << 3 if major < 256 else 0
        ry = ((ady << 8) // (major & 0xFF)) << 3 if major < 256 else 0
        rx &= 0xFFFF
        ry &= 0xFFFF
    else:
        rx = ry = 0
    fx, fy = rx & 0xFF, ry & 0xFF
    wx, wy = rx >> 8, ry >> 8
    steps = major >> 3
    ax = ay = 0
    i = 0
    while True:
        if cloud is not None and abs(px - cloud[0]) <= 24 and abs(py - cloud[1]) <= 24:
            return False
        if room.solid[(py & 0x1FF) >> 3][(px & 0x1FF) >> 3]:
            return False
        if i == steps:
            return True
        i += 1
        ax += fx
        cx = ax >> 8
        ax &= 0xFF
        px += (wx + cx) if dx >= 0 else -(wx + cx)
        ay += fy
        cy = ay >> 8
        ay &= 0xFF
        py += (wy + cy) if dy >= 0 else -(wy + cy)


TOUCH_MARGIN = 3          # px added to the 16 px contact box (the model is a little off in position)


def touching(gx, gy, lx, ly, margin=0) -> bool:
    return abs((lx + 8) - (gx + 8)) < 16 + margin and abs((ly + 16) - (gy + 8)) < 16 + margin


# ---------------------------------------------------------------------------------------------------------------------
# world model: guard timelines under effects, cloud
# ---------------------------------------------------------------------------------------------------------------------
_UNSAFE_CACHE: dict = {}


class World:
    """Immutable effect state: kills {slot: t}, sleeps {slot: t}, cloud (cx, cy, t_on)."""

    def __init__(self, room: Room, trace: Trace, kills=(), sleeps=(), cloud=None):
        self.room, self.trace = room, trace
        self.kills = tuple(sorted(kills))
        self.sleeps = tuple(sorted(sleeps))
        self.cloud = cloud
        self.key = (self.kills, self.sleeps, self.cloud)
        self._cache = _UNSAFE_CACHE.setdefault((room.id, self.key), {})

    def with_(self, kill=None, sleep=None, cloud=None):
        k, s, c = dict(self.kills), dict(self.sleeps), self.cloud
        if kill:
            k[kill[0]] = kill[1]
        if sleep:
            s[sleep[0]] = sleep[1]
        if cloud:
            c = cloud
        return World(self.room, self.trace, k.items(), s.items(), c)

    def guard(self, k: int, f: int):
        """(x, y, dir, asleep) or None when dead."""
        kt = dict(self.kills).get(k)
        if kt is not None and f >= kt:
            return None
        st = dict(self.sleeps).get(k)
        if st is not None:
            if st <= f < st + SLEEP_FRAMES:
                x, y, d = self.trace.at(k, st)
                return (x, y, d, True)
            if f >= st + SLEEP_FRAMES:
                x, y, d = self.trace.at(k, f - SLEEP_FRAMES)
                return (x, y, d, False)
        x, y, d = self.trace.at(k, f)
        return (x, y, d, False)

    def normalized(self, t: int) -> "World":
        """Same world for every frame >= t, with effects that already happened collapsed (a kill before t is `dead from 0`;
        a cloud that has ended becomes none): equal futures share one memo key."""
        kills = {k: (0 if kt <= t else kt) for k, kt in self.kills}
        sleeps = {k: st for k, st in self.sleeps if st + SLEEP_FRAMES + 2 > t}
        # a sleep that ended: the guard is back on its (shifted) patrol: keep it, the shift matters
        sleeps.update({k: st for k, st in self.sleeps if st + SLEEP_FRAMES + 2 <= t})
        cloud = self.cloud
        if cloud and cloud[2] + CLOUD_FRAMES < t:
            cloud = None
        if kills == dict(self.kills) and sleeps == dict(self.sleeps) and cloud == self.cloud:
            return self
        return World(self.room, self.trace, kills.items(), sleeps.items(), cloud)

    def cloud_at(self, f: int):
        c = self.cloud
        if c and c[2] <= f < c[2] + CLOUD_FRAMES:
            return (c[0], c[1])
        return None

    def unsafe(self, f: int, lx: int, ly: int) -> str | None:
        k = (f, lx, ly)
        c = self._cache
        if k in c:
            return c[k]
        r = c[k] = self._unsafe(f, lx, ly)
        return r

    def _unsafe(self, f: int, lx: int, ly: int) -> str | None:
        """Would a guard notice / touch Link standing at (lx, ly) in frame f? A guard decides with its position from the
        end of the previous frame (it moves after looking), so both f - 1 and f are checked (conservative)."""
        cl = self.cloud_at(f)
        for k in range(len(self.room.guards)):
            for gf in (f - 1, f):
                g = self.guard(k, gf)
                if g is None:
                    continue
                gx, gy, gd, asleep = g
                if touching(gx, gy, lx, ly, 0 if asleep else TOUCH_MARGIN):
                    return f"touch guard {k}"
                if asleep:
                    continue
                if sees(self.room, gx, gy, gd, lx, ly, cl):
                    return f"guard {k} sees Link"
        return None


# ---------------------------------------------------------------------------------------------------------------------
# stages (the route skeleton) and the search
# ---------------------------------------------------------------------------------------------------------------------
class Stage:
    pass


class Move(Stage):
    """Walk through the cells in order (axis-aligned steps); departs at a searched time."""

    def __init__(self, *cells, order=None, unchecked=False):
        self.cells = cells
        self.order = order  # optional list of 'xy'/'yx' per cell
        self.unchecked = unchecked  # route knowingly passes through a guard's view (r05): not safety-checked


class Act(Stage):
    """Fixed action at the current cell: face / item / shoot / pot / knife / stab."""

    def __init__(self, kind, *a):
        self.kind, self.a = kind, a


class Ctx:
    def __init__(self, room, trace, margin):
        self.room, self.trace, self.margin = room, trace, margin
        self.pos = room.start


def seg_frames(d: int) -> int:
    return 0 if d == 0 else int(d / LINK_SPEED + 0.999) + SEG_OVERHEAD


def move_path(ctx: Ctx, pos, cells, order):
    """List of (x0, y0, x1, y1, frames) segments from pos through cells (x first unless order says otherwise)."""
    segs = []
    x, y = pos
    for i, c in enumerate(cells):
        tx, ty = ctx.room.cell(*c)
        o = (order[i] if order else None) or "xy"
        pts = [(tx, y), (tx, ty)] if o == "xy" else [(x, ty), (tx, ty)]
        for (px, py) in pts:
            d = abs(px - x) + abs(py - y)
            if d:
                segs.append((x, y, px, py, seg_frames(d)))
            x, y = px, py
    return segs


def pos_at(segs, tau):
    """Link position tau frames after leaving the first cell: 1.5 px/frame from the first frame, then SEG_OVERHEAD frames of
    alignment taps per segment (the recorder walks closed-loop)."""
    for (x0, y0, x1, y1, n) in segs:
        if tau < n:
            d = abs(x1 - x0) + abs(y1 - y0)
            m = min(d, LINK_SPEED * tau)
            if d:
                return (round(x0 + (x1 - x0) * m / d), round(y0 + (y1 - y0) * m / d))
            return (x0, y0)
        tau -= n
    x0, y0, x1, y1, n = segs[-1]
    return (x1, y1)


class Planner:
    def __init__(self, room: Room, stages: list[Stage], margin: int = 3, max_wait: int = 900, step: int = 2):
        self.room, self.stages = room, stages
        self.trace = Trace(room)
        self.margin = margin
        self.max_wait = max_wait
        self.step = step
        self.fail_memo = set()
        self.evals = 0
        self._paths = {}
        self.reach = {}   # stage -> [earliest, latest] start time the search got to (diagnostics)

    # -- helpers ---------------------------------------------------------------------------------------------------
    def static_safe(self, w: World, pos, t0, t1):
        m = self.margin
        for f in range(t0, t1):
            if w.unsafe(f, *pos):
                return False
        return True

    def try_stage(self, i, t_dep, w: World, pos):
        """Run stage i departing at t_dep. Returns (t_end, w2, pos2, info) or None."""
        st = self.stages[i]
        room = self.room
        m = self.margin
        self.evals += 1
        if isinstance(st, Move):
            key = (pos, st.cells, tuple(st.order or ()))
            ent = self._paths.get(key)
            if ent is None:
                segs = move_path(self, pos, st.cells, st.order)
                total = sum(s[4] for s in segs)
                P = [pos_at(segs, max(tau, 0)) for tau in range(-m, total + m + 1)]   # P[tau + m]
                ent = self._paths[key] = (total, P, segs[-1][2:4])
            total, P, end = ent
            if not st.unchecked:
                unsafe = w.unsafe
                for i in range(total):
                    f = t_dep + i
                    # Link position at i - m, i, i + m (timing margin, both directions)
                    p0 = P[i]
                    p1 = P[i + m]
                    p2 = P[i + 2 * m]
                    if unsafe(f, *p1) or (p0 != p1 and unsafe(f, *p0)) or (p2 != p1 and unsafe(f, *p2)):
                        return None
            return (t_dep + total, w, end, None)
        k = st.kind
        a = st.a
        if k == "item":
            # the menu pauses the game; ~3 game frames run while it opens / closes (measured in the recorder)
            if not self.static_safe(w, pos, t_dep, t_dep + 3):
                return None
            return (t_dep + 3, w, pos, None)
        if k == "face":
            n = 3
            if not self.static_safe(w, pos, t_dep, t_dep + n):
                return None
            return (t_dep + n, w, pos, None)
        if k == "shoot":      # dart: a = (slot,) ; the guard sleeps when the arrow lands; another guard in the path stops it
            slot = a[0]
            g0 = w.guard(slot, t_dep + 20)
            if g0 is None or g0[3]:
                return None
            lx, ly = pos[0] + 8, pos[1] + 16
            dxs, dys = (g0[0] + 8) - lx, (g0[1] + 8) - ly
            dist = max(abs(dxs), abs(dys))
            hit = t_dep + DART_DELAY + int(dist / DART_SPEED)
            if not self.static_safe(w, pos, t_dep, hit + 4):
                return None
            g = w.guard(slot, hit)
            if g is None or g[3]:
                return None
            perp = abs((g[1] + 8) - ly) if abs(dxs) >= abs(dys) else abs((g[0] + 8) - lx)
            if perp > 8:
                return None   # the arrow flies along Link's row / column: the guard must stand in it
            for j in range(len(self.room.guards)):
                if j == slot:
                    continue
                for f in range(t_dep + DART_DELAY, hit + 1):
                    gj = w.guard(j, f)
                    if gj is None:
                        continue
                    jx, jy = gj[0] + 8, gj[1] + 8
                    if abs(dxs) >= abs(dys):
                        ahead = (jx - lx) * (1 if dxs > 0 else -1)
                        lat = abs(jy - ly)
                        tot = abs(dxs)
                    else:
                        ahead = (jy - ly) * (1 if dys > 0 else -1)
                        lat = abs(jx - lx)
                        tot = abs(dys)
                    if 0 < ahead < tot + 4 and lat <= 14:
                        return None   # his body would stop the dart
            return (hit + 4, w.with_(sleep=(slot, hit)), pos, ("shoot", hit))
        if k == "pot":       # a = (facing,): cloud centre = Link origin + POT_OFFSET[facing] (measured)
            off = POT_OFFSET[a[0]]
            cx = pos[0] + off[0]
            cy = pos[1] + off[1]
            on = t_dep + CLOUD_DELAY + 3
            if not self.static_safe(w, pos, t_dep, t_dep + 6):
                return None
            return (t_dep + 6, w.with_(cloud=(cx, cy, on)), pos, ("pot", on))
        if k == "stab":     # a = (slot, dir, dist, maxwait): wait for the guard to come within dist in front of Link
            slot, d, dist, maxw = a
            f = t_dep
            while f < t_dep + maxw:
                g = w.guard(slot, f)
                if g is None:
                    return None
                gx, gy, gd, asleep = g
                lx, ly = pos[0] + 8, pos[1] + 16
                cxg, cyg = gx + 8, gy + 8
                fwd = {"right": cxg - lx, "left": lx - cxg, "down": cyg - ly, "up": ly - cyg}[d]
                lat = abs((cyg - ly) if d in ("left", "right") else (cxg - lx))
                if 0 <= fwd <= dist and lat <= 8:
                    break
                if w.unsafe(f, *pos):
                    return None
                f += 1
            else:
                return None
            if fwd < 16 and not asleep:
                return None
            if not self.static_safe(w, pos, t_dep, f):
                return None
            return (f + 14, w.with_(kill=(slot, f + 4)), pos, ("stab", f))
        raise ValueError(k)

    # -- search ----------------------------------------------------------------------------------------------------
    def search(self, i, t, w: World, pos):
        if i == len(self.stages):
            return []
        w = w.normalized(t)
        self.reach.setdefault(i, [t, t])
        self.reach[i][0] = min(self.reach[i][0], t)
        self.reach[i][1] = max(self.reach[i][1], t)
        key = (i, t // self.step, w.key)
        if key in self.fail_memo:
            return None
        checked = t
        for t_dep in range(t, min(t + self.max_wait, self.trace.n - 700), self.step):
            # waiting at pos until t_dep must be safe (every frame, not only the sampled ones)
            bad = False
            for f in range(checked, t_dep + 1):
                if f > t and w.unsafe(f, *pos):
                    bad = True
                    break
            checked = t_dep + 1
            if bad:
                break
            r = self.try_stage(i, t_dep, w, pos)
            if r is None:
                continue
            t_end, w2, pos2, info = r
            sub = self.search(i + 1, t_end, w2, pos2)
            if sub is not None:
                return [(i, t_dep, info)] + sub
        self.fail_memo.add(key)
        return None

    def run(self):
        w = World(self.room, self.trace)
        sys.setrecursionlimit(10000)
        return self.search(0, 0, w, self.room.start)


# ---------------------------------------------------------------------------------------------------------------------
# plan emission, recording, CLI
# ---------------------------------------------------------------------------------------------------------------------
def emit_plan(room: Room, stages, sched) -> str:
    lines = [f"room {room.idx}   # {room.id}"]
    pos = room.start
    for (i, t_dep, info) in sched:
        st = stages[i]
        if isinstance(st, Move):
            lines.append(f"until {t_dep}")
            x, y = pos
            for j, c in enumerate(st.cells):
                tx, ty = room.cell(*c)
                o = (st.order[j] if st.order else None) or "xy"
                lines.append(f"goto {tx} {ty} {o}   # cell {c}")
                x, y = tx, ty
            pos = (x, y)
        else:
            k, a = st.kind, st.a
            if k == "item":
                lines.append(f"item {a[0]}")
            elif k == "face":
                lines.append(f"until {t_dep}")
                lines.append(f"face {a[0]}")
            elif k == "shoot":
                lines.append(f"until {t_dep}")
                lines.append("shoot")
            elif k == "pot":
                lines.append(f"until {t_dep}")
                lines.append("shoot")
            elif k == "stab":
                lines.append(f"until {t_dep}")
                lines.append(f"stab {a[0]} {a[2]} {a[3]} {a[1]}")
    return "\n".join(lines) + "\n"


def run_mesen(script: str, env_extra: dict, results: str, timeout: int = 240):
    env = os.environ.copy()
    env.update(env_extra)
    env["HUSH_RESULTS"] = str(ROOT / results)
    cmd = [str(ROOT / ".venv" / "bin" / "python"), str(ROOT / "tools" / "run_test.py"), script, "--timeout", str(timeout)]
    return subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)


def record(room: Room, plan_text: str):
    PLAN_DIR.mkdir(parents=True, exist_ok=True)
    plan = PLAN_DIR / f"{room.id}.plan"
    plan.write_text(plan_text)
    out = PLAN_DIR / f"{room.id}.inputs"
    if out.exists():
        out.unlink()
    r = run_mesen("tests/dev/record_room.lua", {"HUSH_PLAN": str(plan), "HUSH_REC_OUT": str(out)}, f"build/rec/{room.id}")
    text = r.stdout
    m = re.search(r"REC: .*", text)
    res = "PASS" if "HUSH_RESULT: PASS" in text else "FAIL"
    detail = m.group(0) if m else ""
    fail = re.search(r"HUSH_RESULT: FAIL - (.*)", text)
    if fail:
        detail += " " + fail.group(1)
    return res, detail, out


def cmd_traces(rooms, names):
    from concurrent.futures import ThreadPoolExecutor
    TRACE_DIR.mkdir(parents=True, exist_ok=True)

    def one(r):
        env = {"HUSH_TRACE_ROOM": str(r.idx), "HUSH_TRACE_FRAMES": "2400", "HUSH_TRACE_GHOST": "1"}
        run_mesen("tests/dev/trace_room.lua", env, f"build/tr_g{r.idx}")
        src = ROOT / f"build/tr_g{r.idx}/dev_trace_room/trace.csv"
        (TRACE_DIR / f"ghost_{r.idx}.csv").write_bytes(src.read_bytes())
        return r.id

    sel = [r for r in rooms if not names or r.id in names]
    with ThreadPoolExecutor(8) as ex:
        for rid in ex.map(one, sel):
            print("trace", rid)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["traces", "plan", "solve", "record"])
    ap.add_argument("rooms", nargs="*")
    ap.add_argument("--margin", type=int, default=3)
    ap.add_argument("--step", type=int, default=2)
    ap.add_argument("--max-wait", type=int, default=900)
    ap.add_argument("--no-install", action="store_true", help="do not copy the recorded inputs into tests/solutions/")
    a = ap.parse_args()
    rooms = load_rooms()
    names = [] if a.rooms in ([], ["all"]) else a.rooms
    if a.cmd == "traces":
        cmd_traces(rooms, names)
        return 0
    import room_plans
    sel = [r for r in rooms if not names or r.id in names]
    rc = 0
    if a.cmd == "record":     # re-record the plans saved in build/plans/ (after the recorder or the engine changed)
        for r in sel:
            res, detail, out = record(r, (PLAN_DIR / f"{r.id}.plan").read_text())
            print(f"{r.id}: record {res} {detail}")
            if res == "PASS" and not a.no_install:
                (SOL_DIR / f"{r.id}.inputs").write_text(out.read_text())
            else:
                rc = 1
        return rc
    for r in sel:
        stages = room_plans.PLANS[r.id](r)
        pl = Planner(r, stages, margin=a.margin, max_wait=a.max_wait, step=a.step)
        sched = pl.run()
        if sched is None:
            print(f"{r.id}: NO SCHEDULE ({pl.evals} evals); stages reached (first, last start time): " + str(dict(sorted(pl.reach.items()))))
            rc = 1
            continue
        text = emit_plan(r, stages, sched)
        print(f"{r.id}: schedule found ({pl.evals} evals): " + ", ".join(f"{i}@{t}" for i, t, _ in sched))
        if a.cmd == "plan":
            print(text)
            continue
        res, detail, out = record(r, text)
        print(f"{r.id}: record {res} {detail}")
        if res == "PASS" and not a.no_install:
            SOL_DIR.mkdir(parents=True, exist_ok=True)
            (SOL_DIR / f"{r.id}.inputs").write_text(out.read_text())
        else:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.modules.setdefault("solve_rooms", sys.modules["__main__"])
    sys.exit(main())
