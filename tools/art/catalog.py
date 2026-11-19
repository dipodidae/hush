#!/usr/bin/env python3
"""Catalogue every distinct OAM entry (name table, tile, size, palette row) seen in a frames.txt dump taken on the TRACE ROM
(tools/art/make_trace_rom.py + tools/art/dump_sprites.lua) and resolve its 8x8 cells to (sheet, tile index). Research helper."""
from __future__ import annotations
import sys, collections
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from sprlog import load, visible
from tilelib import *

def catalog(frames_path, room_vram_path):
    fr = load(frames_path)
    rv = open(room_vram_path, 'rb').read()
    cat = collections.OrderedDict()
    for f in fr:
        for e in f.entries():
            if not visible(e) or e['i'] >= 128:
                continue
            if e['y'] >= 224 or e['y'] + (16 if e['big'] else 8) <= 0:
                continue
            key = (e['nt'], e['tile'], e['big'], e['pal'])
            c = cat.setdefault(key, dict(n=0, labels=collections.Counter(), cells=None, flips=set(), first=f.n))
            c['n'] += 1
            c['labels'][f.label.split('_')[0] + '_' + (f.label.split('_')[1] if '_' in f.label else '')] += 1
            c['flips'].add((e['hflip'], e['vflip']))
            if c['cells'] is None:
                subs = [e['tile'], e['tile'] + 1, e['tile'] + 16, e['tile'] + 17] if e['big'] else [e['tile']]
                cells = []
                for s in subs:
                    s &= 0xFF
                    if e['nt'] == 0:
                        t = vram_tile(f.vram, s * 32)
                    else:
                        t = vram_tile(rv, 0xA000 + s * 32)
                    d = trace_decode(t, 3) if any(t) else 'blank'
                    cells.append(d)
                c['cells'] = cells
    return cat

if __name__ == '__main__':
    cat = catalog(sys.argv[1], sys.argv[2])
    for (nt, tile, big, pal), c in sorted(cat.items()):
        cells = ' '.join(('blank' if d == 'blank' else ('?' if d is None else ('%02X:%s' % (d[0], '--' if d[1] is None else '%02X' % d[1])))) for d in c['cells'])
        print('nt%d tile %02X big%d pal%d n=%-5d flips=%s  %s   [%s]' % (nt, tile, big, pal, c['n'], sorted(c['flips']), cells, ','.join(sorted(c['labels']))[:60]))
