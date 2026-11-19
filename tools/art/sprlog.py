"""Parser for the frames.txt written by tools/art/dump_sprites.lua (research helper)."""
from __future__ import annotations
import sys
from dataclasses import dataclass, field

@dataclass
class Frame:
    label: str
    n: int
    link: dict
    slots: list
    oam: bytes
    vram: bytes  # 0x8000..0xA000 (name table 0) only
    dma: dict = field(default_factory=dict)   # word at WRAM $0AC0+2*i
    anc: list = field(default_factory=list)   # ancilla types $0C4A..

    def entries(self):
        out = []
        for i in range(128):
            x, y, tile, attr = self.oam[i*4:i*4+4]
            hi = (self.oam[512 + i // 4] >> ((i % 4) * 2)) & 3
            x9 = hi & 1
            big = (hi >> 1) & 1
            xx = x - 256 if x9 else x
            yy = y if y < 224 else y - 256
            out.append(dict(i=i, x=xx, y=yy, tile=tile, attr=attr, big=big, nt=attr & 1, pal=(attr >> 1) & 7,
                            prio=(attr >> 4) & 3, hflip=bool(attr & 0x40), vflip=bool(attr & 0x80)))
        return out

def visible(e):
    # y is the line above the first drawn line; 8x8/16x16 sprite is visible if some part overlaps 0..223 and x in -16..255
    sz = 16 if e['big'] else 8
    return e['y'] + sz > 0 and e['y'] < 224 and e['x'] + sz > 0 and e['x'] < 256

def load(path):
    frames = []
    last = b''
    for line in open(path):
        p = line.rstrip('\n').split('|')
        if p[0] != 'F':
            continue
        lab, n, l, slots, oam, v = p[1], int(p[2]), p[3], p[4], p[5], p[6]
        dma = {0x0AC0 + 2 * i: int(w, 16) for i, w in enumerate(p[7].split(','))} if len(p) > 7 else {}
        anc = [int(a, 16) for a in p[8].split(',')] if len(p) > 8 else []
        lv = [int(a) for a in l[2:].split(',')]
        link = dict(x=lv[0], y=lv[1], dir=lv[2], sword=lv[3], act=lv[4], dash=lv[5])
        sl = []
        for s in slots.split(';'):
            a, b = s.split(':')
            f = b.split(',')
            sl.append(dict(slot=int(a), type=int(f[0], 16), state=int(f[1], 16), x=int(f[2]), y=int(f[3]), dir=int(f[4]),
                           aware=int(f[5]), body=int(f[6]), head=int(f[7]), pal=int(f[8], 16), walk=int(f[9])))
        if v != '=':
            last = bytes.fromhex(v)
        frames.append(Frame(lab, n, link, sl, bytes.fromhex(oam), last, dma, anc))
    return frames
