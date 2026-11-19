#!/usr/bin/env python3
"""Update the drawing briefs (gfx/src/**/GFX_*.yaml, LINK.yaml): role, decision, palette indices of the painted cast sheets."""
from __future__ import annotations

import re
from pathlib import Path

import cast_pal as P
from cast_link import LINK_PAL

SRC = Path(__file__).resolve().parents[2] / "gfx" / "src"


def pal_block(family, note, names, cols):
    import json
    s = f"palette:\n  family: {family}\n  note: {json.dumps(note)}\n  indices:\n"
    for i, (n, c) in enumerate(zip(names, cols), start=1):
        s += f"    {i}: {json.dumps('#' + c + ' ' + n)}\n"
    return s


def patch(path, role=None, decision=None, palette=None, what=None, where=None):
    p = SRC / path
    t = p.read_text()
    if role:
        t = re.sub(r"^role: .*$", f"role: {role}", t, count=1, flags=re.M)
    if decision:
        t = re.sub(r"^decision: .*$", f"decision: {decision}", t, count=1, flags=re.M)
    if what:
        t = re.sub(r"^what_it_is: .*?(?=^\S)", f"what_it_is: {what!r}\n", t, count=1, flags=re.M | re.S)
    if where is not None:
        t = re.sub(r"^where_it_appears:.*?(?=^\S)", ("where_it_appears:\n" + "".join(f"- {w}\n" for w in where)) if where else "where_it_appears: []\n",
                   t, count=1, flags=re.M | re.S)
    if palette:
        t = re.sub(r"^palette:\n(?:  .*\n)+", palette, t, count=1, flags=re.M)
    p.write_text(t)


FX_NAMES = ["outline", "shade", "deepest shade", "mid violet", "light violet", "cyan-white glint", "teal sparkle"]
FX_PAL = pal_block("fx", "player tool/effect sheets: violet ramp + cyan-white glint + teal (OBJ rows 1/2); identical indices in every row they are drawn with",
                   FX_NAMES, P.FX)

patch("sprite/GFX_BC.yaml", role="danger", palette=pal_block(
    "guard", "OBJ row 4 left (calm/asleep); the alert row 6 recolours the same indices amber (Hush_PalAlert). NEVER use index 7 (violet in the alert row).",
    ["outline", "helmet / pauldrons / boots (dark slate)", "deep shade", "uniform (steel blue)", "AMBER = danger: lantern, helmet badge, belt buckle",
     "highlights / eyes", "unused (never paint)"], P.GUARD),
    what="the lantern guard: 14 blocks (docs/gfx/art_map.md section 5), steel-blue uniform + amber lantern")
patch("sprite/GFX_C5.yaml", role="env", decision="redraw", palette=pal_block(
    "icons", "OBJ row 4 RIGHT half (sprites.yaml pal_sprite_03 row 2): awareness icons",
    ["outline", "soft shadow", "dark amber", "pale gold '?' (suspicious)", "AMBER '!' (alert)", "pale teal 'Z' (asleep, harmless)", "teal shade"], P.ICON))
for gid, what, where in (
        ("73", "Hush Dart (arrow) in flight: cells (10..13, 2..3), 8x8 each", ["underworld rooms (Hush Darts)"]),
        ("79", "ink cloud (bomb explosion), guard-death poof, sparkles", ["underworld rooms (Ink Pot, takedown poof, hit sparkles)"]),
        ("7A", "sparkle stars (cells (6,1) (7,1))", ["underworld rooms (sparkles)"]),
        ("7D", "shadow under guards/Link (block (12,2)) + Ink Pot (block (14,2))", ["underworld rooms (every guard, Link, Ink Pot)"])):
    patch(f"sprite/GFX_{gid}.yaml", role="player", decision="redraw", palette=FX_PAL, what=what, where=where)
patch("item/GFX_D1.yaml", role="player", decision="reuse-as", palette=pal_block(
    "blade", "Shade Knife: OBJ row 5 RIGHT half; the game shows ONLY indices 1-3 (sword.yaml pal_sword_00); 4-7 = pal_shield_00 (violet/teal, unused)",
    ["violet blade", "cyan-white glint along the edge", "deep violet edge / guard / grip", "(shield colours, unused) mid violet",
     "(shield colours, unused) light violet", "(shield colours, unused) glint", "(shield colours, unused) teal"], P.BLADE + P.FX[3:]))
patch("player/LINK.yaml", palette=pal_block(
    "link", "4bpp player sheet, OBJ row 7: violet hooded cloak, pale-cyan eyes, teal scarf (no amber)",
    ["outline", "cloak dark", "cloak", "cloak light / hood highlight", "violet bright", "eye glint (pale cyan)", "boots / deep shade",
     "scarf teal", "scarf shade", "hood inner", "violet mid", "violet bright 2", "deepest (face hollow)", "pale violet", "near white"], LINK_PAL))
print("briefs updated")
