#!/usr/bin/env python3
"""Build the HUSH graphics inventory: docs/gfx/inventory.yaml + docs/gfx/INVENTORY.md.

  gfx_inventory.py            (needs vendor/usdasm and build/ref/meta from gfx_refdump.py)

One entry per graphics asset (sheet slot, Link, font, world map) and per palette group.
Facts come from vendor/usdasm (usage tables and call sites, cited by file:line in
`evidence`) and ROM-derived metadata in build/ref/meta (sizes, tile counts, capacity).
No vanilla pixels are read here. HUSH decisions are rule-based; rules are listed in
RULES below and in INVENTORY.md so the human can overrule any entry via
docs/gfx/decisions_override.yaml (id -> decision/priority/notes).
"""
from __future__ import annotations

import collections
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
VENDOR = ROOT / "vendor" / "usdasm"
META = ROOT / "build" / "ref" / "meta"
OUT = ROOT / "docs" / "gfx"

SPR_OFFSET = 0x73
BG_UW_SETS = range(0x00, 0x18)     # SheetsTable_AA1 comment "; Underworld" (bank_00.asm:11563) rows 0x00-0x17
BG_OW_SETS = range(0x18, 0x25)     # "; Overworld" rows 0x18-0x24
SPR_UW_SETS = range(0x40, 0x90)    # SheetsTable_AA3 comments "for underworld" (bank_00.asm:11067+)

RULES = """\
Decision rules (applied in order; first match wins; overridable in docs/gfx/decisions_override.yaml):
 1. Blank in vanilla (7-byte empty stream)                      -> unused  (left untouched; no pixels to replace)
 2. Equipment / item sheets decoded by DecompressSword/Shield/LoadItemGFX -> reuse-as (Shade Knife / Hush Dart / Ink Pot / props)
 3. Link, font, HUD sheets                                       -> redraw  (P0)
 4. Referenced by an underworld tileset or underworld sprite set -> redraw  (P0 if used by >=10 underworld sets, else P1)
 5. Referenced only by routines/tables of the overworld, world map, intro, ending, mirror warp, followers -> cut (engine task)
 6. Referenced by an AA2 override row only (overworld/underworld unknown) -> redraw P1 (safe default)
 7. Not referenced anywhere                                      -> unused
Priority: P0 needed for the M1 test room (core dungeon tileset + sprites, Link, HUD, font), P1 MVP, P2 polish.
"""

CALLS = re.compile(r"(Decompress_sprite_low|Decompress_sprite_high|Decompress_sprite_arbitrary|"
                   r"Decompress_background_low|Decompress_background_arbitrary)")

SCENE_BY_ROUTINE = [  # routine-name substring -> (scene, scope)  scope: ow | uw | any | screen
    ("Overworld", "overworld", "ow"), ("AnimateMirrorWarp", "mirror warp (overworld)", "ow"),
    ("FileSelect", "file select", "screen"), ("Intro", "intro / title", "screen"),
    ("Attract", "attract / ending scenes", "screen"), ("Credits", "credits", "screen"),
    ("Follower", "followers", "ow"), ("AnimatedUnderworld", "underworld animated tiles", "uw"),
    ("AnimatedOverworld", "overworld animated tiles", "ow"),
    ("Sword", "sword gfx (all scenes)", "any"), ("Shield", "shield gfx (all scenes)", "any"),
    ("LoadItemGFX", "item gfx (all scenes)", "any"), ("item_gfx", "item gfx (all scenes)", "any"),
    ("LoadAuxiliaryWRAM", "aux WRAM gfx", "any"), ("TransAux", "screen transitions", "any"),
    ("ReloadPreviouslyLoaded", "screen transitions", "any"), ("InitializeTilesets", "tileset init (all rooms)", "any"),
    ("LoadCommonSprites", "common sprites", "any"), ("LoadDefaultGraphics", "default gfx", "any"),
    ("DecompressAndCopyManually", "misc", "any"),
]


def read(path: str) -> list[str]:
    return (VENDOR / path).read_text().splitlines()


def parse_db_table(lines: list[str], label: str):
    i = next(k for k, l in enumerate(lines) if l.startswith(label + ":"))
    rows = []
    for k in range(i + 1, len(lines)):
        l = lines[k]
        m = re.match(r"^\|[0-9A-F]{6}\|\s+db\s+(.*?)\s*(;.*)?$", l)
        if m:
            rows.append(dict(vals=[int(x, 16) for x in re.findall(r"\$([0-9A-Fa-f]{2})", m.group(1))], line=k + 1))
        elif l.startswith(";====") and rows:
            break
    return rows


def scan_call_sites(banks_glob: str = "bank_*.asm"):
    """(space, sheet idx, routine, file:line) for LDY.b #$xx directly before a Decompress_* call."""
    sites = []
    for f in sorted(VENDOR.glob(banks_glob)):
        L = f.read_text().splitlines()
        routine = None
        for i, l in enumerate(L):
            m = re.match(r"^#?([A-Za-z_][A-Za-z_0-9]*):", l)
            if m:
                routine = m.group(1)
            if re.match(r"^\|[0-9A-F]{6}\|\s+(JSR|JSL|JMP)", l):
                c = CALLS.search(l)
                if not c:
                    continue
                y = None
                for k in range(max(0, i - 6), i):
                    mm = re.search(r"LDY\.b #\$([0-9A-F]{2})\b", L[k])
                    if mm:
                        y = int(mm.group(1), 16)
                if y is not None:
                    space = "sprite" if "sprite" in c.group(1) else "bg"
                    sites.append(dict(space=space, idx=y, routine=routine, at=f"{f.name}:{i + 1}"))
    return sites


def scene_of(routine: str):
    for sub, scene, scope in SCENE_BY_ROUTINE:
        if sub in routine:
            return scene, scope
    return routine, "any"


def link_frames():
    L = read("bank_00.asm")
    out = collections.defaultdict(lambda: collections.defaultdict(list))
    table = None
    for l in L:
        m = re.match(r"^(LinkOAM_(Head|Body|Aux)Addresses):", l)
        if m:
            table = m.group(2).lower()
            continue
        if re.match(r"^[A-Za-z_]+:", l) and not l.startswith("LinkOAM"):
            if table and l.startswith("TilemapUpload"):
                table = None
        m = re.match(r"^\|[0-9A-F]{6}\|\s+dw LinkGraphics\+\$([0-9A-F]{4})\s*;\s*0x([0-9A-F]+)", l)
        if m and table:
            out[table][int(m.group(1), 16)].append(int(m.group(2), 16))
    res = []
    for kind in ("head", "body", "aux"):
        for off, anims in sorted(out[kind].items()):
            res.append(dict(part=kind, byte_offset=off, tile=off // 32, anims=anims))
    return res


# ---- tile semantics from the game's own tile-type tables (data, not pixels) -----------------------
CLASS_BY_HANDLER = [   # substring of TileBehavior_* handler name -> class letter
    ("StandardCollision", "w"), ("Pit", "p"), ("ShutterDoor", "d"), ("FlaggableDoor", "d"), ("ManualDoor", "d"),
    ("TileBehavior_Door", "d"), ("DoorOrWall", "d"), ("LightableTorch", "t"), ("Stairs", "s"), ("Entrance", "s"),
    ("Warp", "s"), ("Chest", "c"), ("Liftable", "l"), ("BonkRocks", "l"), ("Spike", "h"), ("DeepWater", "a"),
    ("ShallowWater", "a"), ("WaterLadder", "a"), ("Conveyor", "v"), ("Nothing", "f"),
]


def handler_classes(lines: list[str]) -> list[str]:
    """Underworld tile type (0..255) -> class letter, from ExecuteTileDetection_underworld vectors
    (bank_07.asm:17972+: `dw TileBehavior_X ; 0xNN UW`). Unknown handler -> '?'."""
    out = ["?"] * 256
    for l in lines:
        m = re.match(r"^\|[0-9A-F]{6}\|\s+dw (TileBehavior_\w+)\s*;\s*0x([0-9A-F]{2}) UW", l)
        if m:
            name = m.group(1)
            for sub, cls in CLASS_BY_HANDLER:
                if sub in name:
                    out[int(m.group(2), 16)] = cls
                    break
    return out


def db_bytes(lines: list[str], label: str, stop: str) -> list[int]:
    i = next(k for k, l in enumerate(lines) if l.startswith(label + ":"))
    j = next(k for k, l in enumerate(lines) if k > i and l.startswith(stop))
    vals = []
    for l in lines[i + 1:j]:
        m = re.match(r"^\|[0-9A-F]{6}\|\s+db\s+(.*?)\s*(;.*)?$", l)
        if m:
            vals += [int(x, 16) for x in re.findall(r"\$([0-9A-Fa-f]{2})", m.group(1))]
    return vals


def bg_tile_classes(L00: list[str], aa1, aa2) -> dict[int, str]:
    """sheet id -> 64-char class string (class letter per tile, majority vote over every underworld
    tileset). chr tile n of a tileset = (slot n>>6, tile n&63); slot k's sheet = AA1[set][k], slots 3-6
    may be replaced by AA2 rows. Type of chr n: UnderworldTileTypes (n<0x140, n>=0x1C0) or the custom
    set (n 0x140-0x1BF) (bank_0E.asm:165-205 LoadUnderworldTileTypes, :326 LoadDefaultTileTypes)."""
    E = read("bank_0E.asm")
    V = read("bank_07.asm")
    cls_of = handler_classes(V)
    base = db_bytes(E, "UnderworldTileTypes", "LoadDefaultTileTypes")           # 0x180 bytes
    custom = db_bytes(E, "CustomUnderworldTileTypes", "LoadUnderworldTileTypes")  # sets of 0x80
    offs = []
    i = next(k for k, l in enumerate(E) if l.startswith("CustomTileTypesOffset:"))
    for l in E[i + 1:i + 8]:
        offs += [int(x, 16) for x in re.findall(r"\$([0-9A-Fa-f]{4})", l)]

    def type_of(n: int, custom_set: int | None):
        if n < 0x140:
            return base[n]
        if n >= 0x1C0:
            return base[0x140 + (n - 0x1C0)]
        if custom_set is None or custom_set >= len(offs):
            return 0
        o = offs[custom_set] + (n - 0x140)
        return custom[o] if o < len(custom) else 0

    votes = collections.defaultdict(collections.Counter)

    def vote(sheet, idx, cls):
        votes[sheet][idx, cls] += 1
    for si, row in enumerate(aa1):
        if si not in BG_UW_SETS:
            continue
        vals = row["vals"]
        for k in range(8):
            for t in range(64):
                n = k * 64 + t
                if 0x140 <= n < 0x1C0:
                    for cs in range(len(offs)):           # custom overlay unknown for this set: vote with all
                        vote(vals[k], t, cls_of[type_of(n, cs)])
                else:
                    vote(vals[k], t, cls_of[type_of(n, None)])
    for v, row in enumerate(aa2):
        for p, sh in enumerate(row["vals"]):
            if not sh:
                continue
            k = 3 + p
            for t in range(64):
                n = k * 64 + t
                vote(sh, t, cls_of[type_of(n, v if v < len(offs) else None)])
    res = {}
    for sh, c in votes.items():
        best = {}
        for (t, cl), cnt in c.items():
            if t not in best or cnt > best[t][1]:
                best[t] = (cl, cnt)
        res[sh] = "".join(best.get(t, ("?", 0))[0] for t in range(64))
    return res


def font_widths() -> list[int]:
    """Advance widths per text code 0x00.. from RenderText_PerformVWFing .width (bank_0E.asm:8700+)."""
    E = read("bank_0E.asm")
    i = next(k for k, l in enumerate(E) if l.startswith("pool RenderText_PerformVWFing"))
    w = []
    for l in E[i + 1:i + 40]:
        if l.startswith("endpool") or l.startswith(".masks_on"):
            break
        m = re.match(r"^\|[0-9A-F]{6}\|\s+db\s+([0-9, ]+)\s*$", l)
        if m:
            w += [int(x) for x in re.findall(r"\d+", m.group(1))]
    return w


def main() -> int:
    if not (META / "assets.json").exists():
        print("run tools/gfx_refdump.py first", file=sys.stderr)
        return 1
    assets_meta = {a["id"]: a for a in json.loads((META / "assets.json").read_text())}
    pal_layout = json.loads((META / "palette_layout.json").read_text())
    overrides = {}
    ovp = OUT / "decisions_override.yaml"
    if ovp.exists():
        overrides = yaml.safe_load(ovp.read_text()) or {}

    L = read("bank_00.asm")
    aa1 = parse_db_table(L, "SheetsTable_AA1")
    aa2 = parse_db_table(L, "SheetsTable_AA2")
    aa3 = parse_db_table(L, "SheetsTable_AA3")
    aa4 = parse_db_table(L, "SheetsTable_AA4")
    bg_uw, bg_ow = collections.defaultdict(set), collections.defaultdict(set)
    for n, r in enumerate(aa1):
        for s in r["vals"]:
            (bg_uw if n in BG_UW_SETS else bg_ow)[s].add(n)
    bg_aa2 = collections.defaultdict(set)
    for n, r in enumerate(aa2):
        for s in r["vals"]:
            if s:
                bg_aa2[s].add(n)
    sp_uw, sp_ow = collections.defaultdict(set), collections.defaultdict(set)
    for n, r in enumerate(aa3):
        for s in r["vals"]:
            if s:
                (sp_uw if n in SPR_UW_SETS else sp_ow)[SPR_OFFSET + s].add(n)
    tclasses = bg_tile_classes(L, aa1, aa2)
    sites = scan_call_sites()
    by_sheet = collections.defaultdict(list)
    for s in sites:
        sid = s["idx"] if s["space"] == "bg" else SPR_OFFSET + s["idx"]
        by_sheet[sid].append(s)
    # AA4 is the mirror-warp bg set (bank_00.asm:10549)
    for v in (r["vals"][0] for r in aa4):
        by_sheet[v].append(dict(space="bg", idx=v, routine="AnimateMirrorWarp (SheetsTable_AA4)", at="bank_00.asm:10549"))

    entries = []
    for a in sorted(assets_meta.values(), key=lambda a: (a["id"] not in ("LINK", "FONT"), a["id"])):
        aid = a["id"]
        e = dict(id=aid, bpp=a["bpp"], tiles=a["tiles"], compressed=bool(a.get("compressed")),
                 rom=f"${a['addr']:06X}", comp_bytes=a.get("comp_bytes"), capacity_bytes=a.get("capacity"),
                 nonblank_tiles=len(a["nonblank_tiles"]), nonblank_idx=a["nonblank_tiles"])
        ids = a.get("table_ids") or []
        evid, where, usage = [], [], {}
        if aid.startswith("GFX_"):
            sid = int(aid[4:], 16)
            tbl_ids = ids or [sid]
            e["vanilla_source"] = (f"sheet {aid} ({'sprite' if sid >= 0x73 else 'background'} table index "
                                   f"${(sid - 0x73) if sid >= 0x73 else sid:02X}), ROM {e['rom']}")
            if a.get("aliases"):
                e["aliases"] = a["aliases"]
                e["vanilla_source"] += f"; background-table aliases {a['aliases']} / ids {[hex(i) for i in tbl_ids]}"
            all_ids = set(tbl_ids)
            uwb = set().union(*[bg_uw.get(i, set()) for i in all_ids if i < 0x73] or [set()])
            owb = set().union(*[bg_ow.get(i, set()) for i in all_ids if i < 0x73] or [set()])
            a2 = set().union(*[bg_aa2.get(i, set()) for i in all_ids if i < 0x73] or [set()])
            uws = sp_uw.get(sid, set()); ows = sp_ow.get(sid, set())
            rts = []
            for i in all_ids:                         # by_sheet is keyed by sheet id (sprite idx already + $73)
                rts += by_sheet.get(i, [])
            usage = dict(underworld_bg_tilesets=sorted(uwb), overworld_bg_tilesets=sorted(owb),
                         aa2_override_rows=sorted(a2), underworld_sprite_sets=sorted(uws),
                         overworld_sprite_sets=sorted(ows),
                         routines=sorted({f"{r['routine']} ({r['at']})" for r in rts}))
            scopes = {scene_of(r["routine"])[1] for r in rts}
            for r in rts:
                where.append(scene_of(r["routine"])[0])
            if uwb:
                where.append(f"underworld rooms (BG tilesets {len(uwb)} of 24)")
            if owb:
                where.append(f"overworld areas (BG tilesets {len(owb)})")
            if uws:
                where.append(f"underworld rooms (sprite sets {len(uws)} of 80)")
            if ows:
                where.append(f"overworld areas (sprite sets {len(ows)} of 64)")
            if a2 and not uwb:
                where.append("AA2 override rows (area/room tile variants)")
            evid = ["bank_00.asm:11562 SheetsTable_AA1", "bank_00.asm:11158 SheetsTable_AA2", "bank_00.asm:11010 SheetsTable_AA3"]
            used_uw = len(uwb) + len(uws)
            used_any = bool(uwb or owb or a2 or uws or ows or rts)
            kind = ("bg_tileset" if sid <= 0x72 else "sprite")
            if sid in (0xD7, 0xD8, 0xD9):
                kind = "sprite"
            if sid >= 0xDA:
                kind = "hud"
            decision, prio, note, reuse = None, None, "", None
            if sid in (0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x9E):
                decision, prio, note = "unused", "P2", "blank in vanilla (7-byte empty stream); left untouched, nothing to draw"
            elif sid in (0xD1, 0xD2, 0xC7, 0xD3, 0xCB, 0xCD, 0xCE):
                kind = "item"
                decision, prio = "reuse-as", "P0"
                table = {
                    0xD1: ("Shade Knife frames (sword gfx low sheet: DecompressSwordGraphics reads sprite idx $5E)", "bank_00.asm:9223"),
                    0xD2: ("Shade Knife frames / shield slot (sword gfx high sheet, sprite idx $5F)", "bank_00.asm:9220"),
                    0xC7: ("Hush Darts / bow+arrow item gfx (LoadItemGFXIntoWRAM4BPPBuffer, sprite idx $54)", "bank_00.asm:9147"),
                    0xD3: ("tool item gfx (LoadItemGFXIntoWRAM4BPPBuffer, sprite idx $60)", "bank_00.asm:9172"),
                    0xCB: ("aux item gfx (LoadAuxiliaryWRAMGraphics, sprite idx $58)", "bank_00.asm:9432"),
                    0xCD: ("item pickup gfx (WriteTo4BPPBuffer_item_gfx, sprite idx $5A)", "bank_00.asm:9649"),
                    0xCE: ("item pickup gfx (WriteTo4BPPBuffer_item_gfx, sprite idx $5B)", "bank_00.asm:9646"),
                }[sid]
                reuse = table[0]
                evid.append(table[1])
                note = ("The exact tile -> tool mapping (which tiles are sword vs shield vs bow vs bomb) lives in "
                        "SwordGfxPointers/ShieldGfxPointers/LinkItemGfxPointers (bank_00.asm:899-935) and is "
                        "decided with the engine at M1/M3; the placeholder only marks tiles.")
            elif sid >= 0xDA:
                decision, prio = "redraw", "P0" if sid in (0xDA, 0xDB, 0xDC, 0xDD, 0xDE) else "P1"
                note = "HUD / menu / title graphics (2bpp, BG3). Used in every HUSH scene (hearts, text box, file select)."
            elif uwb or uws:
                decision = "redraw"
                prio = "P0" if used_uw >= 10 else "P1"
                note = f"used by {len(uwb)} underworld tilesets and {len(uws)} underworld sprite sets"
            elif scopes and scopes <= {"ow"} or (not uwb and not uws and (owb or ows) and not a2):
                decision, prio = "cut", "P2"
                note = "only overworld / mirror-warp / follower / world-map code and sets reference this sheet"
            elif a2 and not (uwb or uws):
                decision, prio = "redraw", "P1"
                note = "only referenced by SheetsTable_AA2 override rows (could be overworld or underworld); kept as redraw until the human confirms cut"
            elif rts and scopes <= {"screen"}:
                decision, prio = "cut", "P2"
                note = "only intro/title/credits/attract routines reference this sheet"
            elif rts:
                decision, prio = "redraw", "P1"
                note = "loaded by game-wide code (see routines)"
            else:
                decision, prio, note = "unused", "P2", "no table or call site references this sheet"
            if kind == "hud":
                where.append("HUD / text box / menus / file select (BG3, 2bpp)")
            e.update(kind=kind, decision=decision, priority=prio, notes=note)
            if kind == "bg_tileset" and all_ids & set(tclasses) and decision in ("redraw", "reuse-as"):
                tc = next(tclasses[i] for i in sorted(all_ids) if i in tclasses)
                e["tile_classes"] = tc
                e["tile_class_legend"] = "f floor, w wall/solid, p pit, d door, t unlit torch, s stairs/entrance, c chest, l liftable, h hazard, a water, v conveyor, ? unknown/decor"
            if reuse:
                e["reuse_as"] = reuse
            if decision == "cut":
                e["cut_task"] = ("engine: skip/disable the scenes that load this sheet (overworld / world map / ending / mirror warp); "
                                 "until then the placeholder is magenta CUT")
            grid_w = 16      # all sheets are drawn 16 tiles wide (sprite VRAM row width; 16x16 sprites stay contiguous)
            e["grid_tiles"] = [grid_w, a["tiles"] // grid_w]
        elif aid == "LINK":
            e.update(kind="player", decision="redraw", priority="P0", grid_tiles=[16, 56],
                     vanilla_source="LinkGraphics $108000, link.4bpp (graphics.asm:5-6)",
                     notes="Link's body/head/aux frames; 16 tiles wide. Frames below come from LinkOAM_*Addresses (bank_00.asm:3462-4106). "
                           "HUSH: the player is the shadow thief (violet).",
                     frames=link_frames())
            evid = ["graphics.asm:5", "bank_00.asm:3462", "bank_00.asm:1766"]
            where = ["every scene with the player"]
        elif aid == "FONT":
            e.update(kind="font", decision="redraw", priority="P0", grid_tiles=[16, 16],
                     vanilla_source="TheFont $0E8000, font.2bpp (bank_0E.asm:5-6)",
                     notes="Dialogue/text-box font, uploaded to VRAM $E000 (bank_00.asm:12308-12330). Glyph code -> tile mapping "
                           "follows RenderText (bank_0E.asm:8661+); a new original font replaces it.")
            evid = ["bank_0E.asm:5", "bank_00.asm:12364", "bank_0E.asm:8630-8700 (glyph tile = ((code&$F0)<<1)|(code&$0F), bottom half +$10)"]
            e["glyph_widths"] = font_widths()
            where = ["text boxes", "file select / name entry", "death/save menu"]
        elif aid == "WORLDMAP":
            e.update(kind="special_screen", decision="cut", priority="P2", grid_tiles=[16, 16],
                     vanilla_source="WorldMap_Mode7TileGFX $18C000 (graphics.asm:281), 8bpp Mode 7 (64 B/tile, row-major)",
                     notes="HUSH has no overworld map.",
                     cut_task="engine: disable the map screen (module $0E sub-screens) so it is unreachable; placeholder stays magenta CUT")
            evid = ["graphics.asm:281", "bank_00.asm:11985"]
            where = ["world map screen"]
        e["where_in_vanilla"] = sorted(set(where))
        e["usage"] = usage
        e["evidence"] = evid
        # drawing style
        if e["decision"] == "unused":
            e["style"] = "unused"
        elif e["decision"] == "cut":
            e["style"] = "cut"
        elif aid == "LINK":
            e["style"] = "link"
        elif aid == "FONT":
            e["style"] = "font"
        elif e["kind"] == "bg_tileset":
            e["style"] = "bg"
        elif e["kind"] == "hud":
            e["style"] = "hud"
        elif e["kind"] == "item":
            e["style"] = "item"
        else:
            e["style"] = "sprite"
        if aid in overrides:
            e.update({k: v for k, v in overrides[aid].items()})
            e["override"] = True
        entries.append(e)

    # --- palettes (structure from vendor, decisions by group) -----------------------------
    groups: dict[str, list] = collections.OrderedDict()
    for r in pal_layout["layout"]:
        groups.setdefault(r["label"], []).append(r)

    def pal_decision(label: str):
        if label.startswith("link"):
            return "player", "redraw", "P0", "Link's palettes (green/blue/red mail, bunny, zap): violet player family"
        if label.startswith("sword"):
            return "player", "reuse-as", "P0", "Shade Knife colours (violet)"
        if label.startswith("shield"):
            return "player", "unused", "P2", "HUSH has no shield; magenta so it is obvious if it appears"
        if label.startswith(("sprite_0", "spritepal0", "spriteaux", "environment")):
            return "sprite", "redraw", "P0", "sprite/prop palettes; HUSH sprite family (amber = danger, indigo, violet = you)"
        if label.startswith("hud"):
            return "hud", "redraw", "P0", "HUD / text / menu palettes"
        if label.startswith("dungeonmap"):
            return "special_screen", "cut", "P2", "dungeon map screen is not part of HUSH"
        if label.startswith("dungeon"):
            return "bg", "redraw", "P0", "underworld room palettes (indigo walls/floors, amber light)"
        if label.startswith("ow"):
            return "bg", "cut", "P2", "overworld palettes: HUSH has no overworld"
        if label.startswith("unused"):
            return "sprite", "unused", "P2", "unused in vanilla"
        return "sprite", "redraw", "P1", "other"

    pals = []
    for label, rows in groups.items():
        kind, dec, prio, note = pal_decision(label)
        pals.append(dict(id=f"pal_{label}", kind="palette", family=kind, decision=dec, priority=prio, notes=note,
                         rom=f"${rows[0]['addr']:06X}", rows=[r["n"] for r in rows],
                         row_addrs=[f"${r['addr']:06X}" for r in rows],
                         vanilla_source=f"PaletteData .{label} (bank_1B.asm:4646+)",
                         where_in_vanilla=[note]))
    for x in pal_layout["extra"]:
        pals.append(dict(id=f"pal_{x['label']}", kind="palette", family="special_screen", decision="cut", priority="P2",
                         notes="map / triforce / lightning flash palette: scenes HUSH cuts or never shows",
                         rom=f"${x['addr']:06X}", bytes=x["bytes"],
                         vanilla_source=f"{x['label']} (see docs/gfx/formats.md)", where_in_vanilla=["cut scenes"],
                         cut_task="engine: disable the scene (see its asset entry)"))
    # --- title screen (A0): GFX_39/40/41 are used only by the title/attract tilesets (usage above), so they
    # carry the HUSH title logo laid out by tools/gfx_title.py; the OW palettes the intro loads become title colours.
    for e in entries:
        if e["id"] in ("GFX_39", "GFX_40", "GFX_41"):
            e.update(kind="title", decision="redraw", priority="P0", style="title",
                     notes="TITLE SCREEN logo sheet: holds the HUSH logo and PRESS START cells laid out by tools/gfx_title.py "
                           "(chr tiles $100-$1BF of the title tileset, bank_00.asm:11562/11158). Only used by title/attract tilesets. "
                           "Draw the real logo over these cells; the tilemap (cell layout) is generated, see docs/gfx/formats.md.")
            e.pop("tile_classes", None)
            e.pop("tile_class_legend", None)
    for q in pals:
        if q["id"] in ("pal_owmain_05", "pal_owaux_03", "pal_owanim_00"):
            q.update(family="title", decision="redraw", priority="P0",
                     notes="TITLE SCREEN palettes: the intro loads these overworld palette slots (Intro_LoadAllPalettes, "
                           "bank_02.asm:12739; PaletteLoad_OWBG* bank_1B.asm:6446-6540). All rows are the same title colours.")
            q.pop("cut_task", None)
    doc = dict(version=1, rules=RULES, assets=entries, palettes=pals,
               notes=["Palette colours hard-coded as immediates in code are not tables; found by `make leakcheck`.",
                      "Tilemaps, Map16 definitions and OAM tables are index data, not pixels, and are untouched."])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "inventory.yaml").write_text(yaml.safe_dump(doc, sort_keys=False, width=110))
    write_md(doc)
    cnt = collections.Counter((e["kind"], e["decision"]) for e in entries + pals)
    print(f"inventory: {len(entries)} assets, {len(pals)} palette groups")
    for (k, d), n in sorted(cnt.items()):
        print(f"  {k:15s} {d:9s} {n}")
    return 0


def write_md(doc) -> None:
    a, p = doc["assets"], doc["palettes"]
    c = collections.Counter(e["decision"] for e in a + p)
    out = ["# HUSH graphics inventory (generated by tools/gfx_inventory.py)", "",
           "Source of truth: `docs/gfx/inventory.yaml`. Do not edit by hand; to overrule a decision edit",
           "`docs/gfx/decisions_override.yaml` and re-run `.venv/bin/python tools/gfx_inventory.py`.", "",
           "```", doc["rules"].rstrip(), "```", "",
           f"Totals: {len(a)} graphics assets + {len(p)} palette groups. Decisions: " +
           ", ".join(f"{k} {v}" for k, v in sorted(c.items())), ""]
    tiles = collections.Counter()
    for e in a:
        if e["decision"] in ("redraw", "reuse-as"):
            tiles[e["priority"]] += e["nonblank_tiles"] if e["nonblank_tiles"] else e["tiles"]
    out += ["Tiles to draw (non-blank vanilla tiles per redraw/reuse-as asset): " +
            ", ".join(f"{k}: {v}" for k, v in sorted(tiles.items())), ""]
    for dec in ("redraw", "reuse-as", "cut", "unused"):
        sel = [e for e in a if e["decision"] == dec]
        out += [f"## {dec} ({len(sel)} assets)", "",
                "| id | kind | bpp | tiles | pkd | source | where | prio | notes |", "|---|---|---|---|---|---|---|---|---|"]
        for e in sorted(sel, key=lambda e: (e["priority"], e["id"])):
            wh = "; ".join(e["where_in_vanilla"][:3]) + (" ..." if len(e["where_in_vanilla"]) > 3 else "")
            note = (e.get("reuse_as") or e["notes"]).replace("|", "/")
            out.append(f"| {e['id']} | {e['kind']} | {e['bpp']} | {e['tiles']} | {e['nonblank_tiles']} | {e['rom']} | {wh.replace('|', '/')} | {e['priority']} | {note} |")
        out.append("")
    out += ["## palettes", "", "| id | family | decision | prio | rows (colours) | rom | notes |", "|---|---|---|---|---|---|---|"]
    for e in p:
        rows = ",".join(str(x) for x in e.get("rows", [])) if "rows" in e else f"{e.get('bytes')} bytes"
        out.append(f"| {e['id']} | {e['family']} | {e['decision']} | {e['priority']} | {rows} | {e['rom']} | {e['notes']} |")
    out.append("")
    cuts = [e for e in a + p if e.get("cut_task")]
    out += ["## cut tasks for engine", ""]
    seen = set()
    for e in cuts:
        t = e["cut_task"]
        if t not in seen:
            seen.add(t)
            ids = [x["id"] for x in cuts if x["cut_task"] == t]
            out.append(f"- {t}\n  - assets ({len(ids)}): {', '.join(ids[:12])}{' ...' if len(ids) > 12 else ''}")
    (OUT / "INVENTORY.md").write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    sys.exit(main())
