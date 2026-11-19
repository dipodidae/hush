#!/usr/bin/env python3
"""Write the cast palettes (tools/art/cast_pal.py) into gfx/src/palettes/{sprites,sword,link,cut_unused}.yaml (text edit, keeps the layout)."""
from __future__ import annotations

import re
from pathlib import Path

import cast_pal as P
from cast_link import LINK_PAL

PAL = Path(__file__).resolve().parents[2] / "gfx" / "src" / "palettes"


def fmt(cols):
    return "[" + ", ".join(c if not c.isdigit() else f"'{c}'" for c in cols) + "]"


def set_group(text: str, group: str, rows: list[list[str]]) -> str:
    m = re.search(rf"(  {group}:\n(?:    .*\n)*?    colours:\n)((?:    - \[.*\]\n)+)", text)
    assert m, group
    n = m.group(2).count("\n")
    assert n == len(rows), (group, n, len(rows))
    return text[:m.start(2)] + "".join(f"    - {fmt(r)}\n" for r in rows) + text[m.end(2):]


def right(cols):          # row of 8: colour 8 (never drawn) + indices 1-7
    return ["E0F8F8"] + cols


def main():
    p = PAL / "sprites.yaml"
    t = p.read_text()
    t = set_group(t, "pal_sprite_00", [P.INK])
    t = set_group(t, "pal_sprite_00_right", [right(P.FX)])
    t = set_group(t, "pal_sprite_01", [P.FX])
    t = set_group(t, "pal_sprite_01_right", [right(P.FX)])
    t = set_group(t, "pal_sprite_02", [P.FX, right(P.FX)])
    t = set_group(t, "pal_sprite_03", [P.GUARD, right(P.ICON)])
    p.write_text(t)
    p = PAL / "sword.yaml"
    t = p.read_text()
    for g in ("pal_sword_00", "pal_sword_01", "pal_sword_02", "pal_sword_03"):
        t = set_group(t, g, [P.BLADE])
    t = set_group(t, "pal_sword_04", [P.BLADE, P.BLADE + [P.FX[5]]])
    p.write_text(t)
    p = PAL / "link.yaml"
    t = p.read_text()
    for g in ("pal_Palettes_GreenMail", "pal_Palettes_BlueMail", "pal_Palettes_RedMail", "pal_Palettes_Bunny", "pal_Palettes_Zap"):
        t = set_group(t, g, [LINK_PAL[:7], LINK_PAL[7:]])
    p.write_text(t)
    p = PAL / "cut_unused.yaml"
    t = p.read_text()
    for g in ("pal_shield_00", "pal_shield_01", "pal_shield_02"):
        t = set_group(t, g, [P.FX[3:]])
    p.write_text(t)
    print("palette yaml updated")


if __name__ == "__main__":
    main()
