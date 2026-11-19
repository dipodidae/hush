#!/usr/bin/env python3
"""Research tool: turn the dumps of tools/art/dump_rooms.lua + tools/art/dump_sprites.lua (taken on the TRACE ROM built by
tools/art/make_trace_rom.py, plus the normal ROM's CGRAM) into tools/art/game_map.json, which tools/art_preview.py reads
(which tiles of a sheet the game really draws, and the in-game palette rows). Also prints the numbers quoted in docs/gfx/art_map.md.

  HUSH_ROM=build/art_research/trace/build/hush.sfc HUSH_RESULTS=build/art_research/tr \\
      .venv/bin/python tools/run_test.py tools/art/dump_rooms.lua      (and dump_sprites.lua)
  .venv/bin/python tools/art/build_game_map.py [tr_dir] [cgram_file]
"""
from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sprlog import load, visible  # noqa: E402
from tilelib import ROOT, cg, hexrgb, trace_decode, vram_tile, decode_tile  # noqa: E402
from linkposes import lk  # noqa: E402

TR = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "art_research" / "tr"
CGRAM = Path(sys.argv[2]) if len(sys.argv) > 2 else TR / "dump_rooms" / "room_05.cgram"
OUT = Path(__file__).parent / "game_map.json"

used: dict = collections.defaultdict(lambda: collections.defaultdict(set))     # sheet name -> idx -> {labels}
rows_used: dict = collections.defaultdict(lambda: collections.defaultdict(set))  # sheet name -> idx -> {(kind,row)}
expansion: dict = {}                                                             # sheet -> 'left'|'right'


def sname(code: int) -> str:
    return f"GFX_{code:02X}"


def expansion_of(t) -> str | None:
    if any(p >= 9 for p in t):
        return "right"
    if any(p for p in t):
        return "left"
    return None


# ---------------- BG2 (rooms) -------------------------------------------------------------------------------------
bg_entries = collections.Counter()
for r in range(21):
    v = (TR / "dump_rooms" / f"room_{r:02d}.vram").read_bytes()
    for ty in range(18, 46):
        for tx in range(16, 48):
            scr = (1 if tx >= 32 else 0) + (2 if ty >= 32 else 0)
            a = 0x0000 + scr * 0x800 + ((ty & 31) * 32 + (tx & 31)) * 2
            e = v[a] | v[a + 1] << 8
            bg_entries[e] += 1
v = (TR / "dump_rooms" / "room_00.vram").read_bytes()
bg_rows = []
for e, n in sorted(bg_entries.items()):
    tid = e & 0x3FF
    t = vram_tile(v, 0x4000 + tid * 32)
    d = trace_decode(t, 3)
    pal = (e >> 10) & 7
    bg_rows.append(dict(entry=e, tile=tid, pal=pal, prio=(e >> 13) & 1, hflip=(e >> 14) & 1, vflip=(e >> 15) & 1, count=n,
                        sheet=sname(d[0]), idx=d[1], expansion=expansion_of(t)))
    used[sname(d[0])][d[1]].add(f"BG2 tile ${tid:03X} palette row {pal}")
    rows_used[sname(d[0])][d[1]].add(("BG palette row ", pal))
    expansion[sname(d[0])] = expansion_of(t)

# ---------------- BG3 (HUD) ---------------------------------------------------------------------------------------
hud = collections.defaultdict(set)
for r in range(21):
    v = (TR / "dump_rooms" / f"room_{r:02d}.vram").read_bytes()
    for ty in range(32):
        for tx in range(32):
            a = 0xC000 + (ty * 32 + tx) * 2
            e = v[a] | v[a + 1] << 8
            if (e & 0x3FF) != 0x7F:
                hud[e & 0x3FF].add((e >> 10) & 7)
for tid, pals in sorted(hud.items()):
    sheet, idx = (0xDD, tid) if tid < 128 else (0xDE, tid - 128)
    used[sname(sheet)][idx].add(f"BG3 HUD tile ${tid:03X} palette row {sorted(pals)}")
    for p in pals:
        rows_used[sname(sheet)][idx].add(("BG3 palette row ", p))
    expansion[sname(sheet)] = "2bpp"

# ---------------- sprites -----------------------------------------------------------------------------------------
frames = load(TR / "dump_sprites" / "frames.txt")
room_v = (TR / "dump_rooms" / "room_05.vram").read_bytes()
link_cells = collections.defaultdict(set)
for f in frames:
    d = f.dma
    for top, bot, n_top in ((0x0ACC, 0x0ACE, 2), (0x0AD0, 0x0AD2, 2), (0x0AD4, 0x0AD6, 1)):
        a, b = lk(d[top]), lk(d[bot])
        if a is not None:
            for k in range(n_top):
                link_cells[a + k].add(top)
        if b is not None:
            for k in range(n_top):
                link_cells[b + k].add(bot)
    for e in f.entries():
        if not visible(e) or e["i"] >= 128:
            continue
        sz = 16 if e["big"] else 8
        if e["y"] >= 224:
            continue
        subs = [e["tile"], e["tile"] + 1, e["tile"] + 16, e["tile"] + 17] if e["big"] else [e["tile"]]
        for s in subs:
            s &= 0xFF
            if e["nt"] == 0 and (s < 5 or 16 <= s < 21):     # Link's own DMA'd tiles (LINK.png is not traced; handled through the DMA words)
                continue
            t = vram_tile(f.vram, s * 32) if e["nt"] == 0 else vram_tile(room_v, 0xA000 + s * 32)
            if not any(t):
                continue
            dd = trace_decode(t, 3)
            if dd is None or dd[0] == 0 and dd[1] is None:
                continue
            nm = sname(dd[0])
            if dd[1] is not None:
                used[nm][dd[1]].add(f"OAM name table {e['nt']} tile ${e['tile']:02X} {'16x16' if e['big'] else '8x8'}")
                rows_used[nm][dd[1]].add(("OBJ palette row ", e["pal"]))
            expansion.setdefault(nm, expansion_of(t))

for c in link_cells:
    used["LINK"][c].add("Link frames (NMI DMA)")

# ---------------- palettes ----------------------------------------------------------------------------------------
cgram = CGRAM.read_bytes()
rows = {}
for r in range(16):
    rows[("BG" if r < 8 else "OBJ") + str(r % 8)] = [hexrgb(cg(cgram, r * 16 + i)) for i in range(16)]


def variant(label, row, half):
    cols = rows[row]
    base = 1 if half == "left" else 9
    pal = ["000000"] + [cols[base + i] for i in range(7)]
    return dict(label=label, cgram_row=row, half=half, colours=pal)


V = {
    "GFX_00": [variant("BG palette row 7, colours 9-15 (ceiling/wall tile)", "BG7", "right")],
    "GFX_06": [variant("BG palette row 3, colours 9-15 (floor)", "BG3", "right")],
    "GFX_BC": [variant("OBJ row 4, colours 1-7 (unaware / suspicious / asleep)", "OBJ4", "left"),
               variant("OBJ row 6, colours 1-7 (ALERT: Hush_PalAlert)", "OBJ6", "left")],
    "GFX_C5": [variant("OBJ row 4, colours 9-15 (icons)", "OBJ4", "right")],
    "GFX_7D": [variant("OBJ row 4, colours 9-15 (shadow)", "OBJ4", "right"), variant("OBJ row 2, colours 9-15 (ink pot)", "OBJ2", "right")],
    "GFX_79": [variant("OBJ row 1, colours 1-7 (explosion = ink cloud: Hush_PalInk)", "OBJ1", "left"),
               variant("OBJ row 2, colours 1-7 (poof, sparkles)", "OBJ2", "left")],
    "GFX_7A": [variant("OBJ row 1, colours 1-7 (ink)", "OBJ1", "left"), variant("OBJ row 2, colours 1-7", "OBJ2", "left")],
    "GFX_73": [variant("OBJ row 2, colours 1-7 (arrow)", "OBJ2", "left"), variant("OBJ row 1, colours 1-7 (bow)", "OBJ1", "left")],
    "GFX_D1": [variant("OBJ row 5, colours 9-15 (sword: only 1-3 are sword colours; 4-7 are the unused shield colours)", "OBJ5", "right")],
    "LINK": [dict(label="OBJ row 7, colours 1-15", cgram_row="OBJ7", half="full", colours=["000000"] + rows["OBJ7"][1:16])],
    "GFX_DD": [dict(label="BG3 row 2 (colours 0-3)", cgram_row="BG2", half="2bpp", colours=rows["BG0"][0:4])],
    "GFX_DE": [dict(label="BG3 row 1 (colours 0-3)", cgram_row="BG1", half="2bpp", colours=rows["BG0"][0:4])],
}

game_map = dict(
    note="generated by tools/art/build_game_map.py from MesenCE dumps; used by tools/art_preview.py. Do not edit by hand.",
    cgram_rows=rows,
    sheets={nm: dict(expansion=expansion.get(nm), used={str(i): sorted(lbls) for i, lbls in sorted(d.items())},
                     rows={str(i): sorted(f"{k}{r}" for k, r in sorted(rows_used[nm].get(i, ()))) for i in d},
                     variants=V.get(nm, [])) for nm, d in sorted(used.items())},
    bg=bg_rows,
)
OUT.write_text(json.dumps(game_map, indent=1))
print(f"wrote {OUT.relative_to(ROOT)}: {len(game_map['sheets'])} sheets")
for nm, s in game_map["sheets"].items():
    print(f"  {nm:7s} exp={s['expansion']!s:6s} used cells {len(s['used']):3d}: " + " ".join(f"{int(i):02X}" for i in s["used"])[:150])
print("BG2 entries over 21 rooms:")
for b in bg_rows:
    print("   ", b)
