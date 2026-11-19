#!/usr/bin/env python3
"""Link's frames in a frames.txt dump -> exact LINK.png blocks (from the NMI DMA source words $0ACC.., bank_00.asm:1742-1900). Research helper.
VRAM tile 0,1 (+16,17) <- $0ACC/$0ACE (head block), 2,3 (+16,17) <- $0AD0/$0AD2 (body block), 4 (+16) <- $0AD4/$0AD6 (extra 8x8).
LINK.png idx = (word - $8000) / 32. 16 tiles per row, so a block at idx n covers n, n+1, n+16, n+17."""
from __future__ import annotations
import sys, collections
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from sprlog import load, visible

DIRS = {0: "up", 2: "down", 4: "left", 6: "right"}

def lk(w):
    return (w - 0x8000) // 32 if 0x8000 <= w < 0x8000 + 0x7000 else None

def poses(path):
    fr = load(path)
    out = collections.OrderedDict()   # (category, dir) -> OrderedDict[(head, body, bflip, extra)] = first frame
    prev = None
    for f in fr:
        if not (f.label.startswith("link") or f.label.startswith("bow") or f.label.startswith("bomb_place")):
            prev = None
            continue
        d = f.dma
        head, body, extra = lk(d[0x0ACC]), lk(d[0x0AD0]), lk(d[0x0AD4])
        moving = prev is not None and (prev.link["x"], prev.link["y"]) != (f.link["x"], f.link["y"])
        prev = f
        lab = f.label
        if lab.startswith("link_walk"):
            cat = "walk" if moving else "walk-blocked (push)"
        elif lab.startswith("link_sword"):
            cat = "sword" if f.link["sword"] or f.link["act"] else "sword-recover"
            cat = "sword swing" if f.link["sword"] else ("sword charge/hold" if lab.endswith("charge") else "after swing")
        elif lab.startswith("bow"):
            cat = "bow"
        elif lab.startswith("bomb"):
            cat = "bomb"
        else:
            cat = "stand"
        # head OAM entry flips
        ents = [e for e in f.entries() if visible(e) and e["nt"] == 0 and e["tile"] in (0, 2)]
        fl = {e["tile"]: ("H" if e["hflip"] else "") + ("V" if e["vflip"] else "") for e in ents}
        key = (cat, f.link["dir"])
        out.setdefault(key, collections.OrderedDict()).setdefault((head, body, fl.get(0, ""), fl.get(2, ""), extra), f.n)
    return out

def blk(i):
    return "%d (col %d,row %d; px %d,%d)" % (i, i % 16, i // 16, (i % 16) * 8, (i // 16) * 8)

if __name__ == "__main__":
    for (cat, d), v in poses(sys.argv[1]).items():
        print(f"{cat:22s} facing {DIRS.get(d, d):5s}: {len(v)} pose(s)")
        for (h, b, hf, bf, x), n in v.items():
            print(f"      head {h} body {b} flips(head='{hf}', body='{bf}') extra {x}  (first frame {n})")
