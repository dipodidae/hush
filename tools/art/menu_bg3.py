#!/usr/bin/env python3
"""menu_bg3.py: render the whole 64x64 BG3 map (2bpp chr at $E000, CGRAM groups 0-7) of a gfx snapshot to a PNG.
  .venv/bin/python tools/art/menu_bg3.py build/art_research/menu/menu_snap/menu_open out.png [--zoom 2]
"""
import sys
from PIL import Image


def rgb(cg, i):
    w = cg[2 * i] | (cg[2 * i + 1] << 8)
    return ((w & 31) * 255 // 31, ((w >> 5) & 31) * 255 // 31, ((w >> 10) & 31) * 255 // 31)


def main():
    base, out = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 1
    v = open(base + ".vram", "rb").read()
    cg = open(base + ".cgram", "rb").read()
    img = Image.new("RGB", (512, 512), (255, 0, 255))
    px = img.load()
    for scr, addr in enumerate((0xC000, 0xC800, 0xD000, 0xD800)):
        ox, oy = (scr % 2) * 256, (scr // 2) * 256
        for r in range(32):
            for c in range(32):
                w = v[addr + (r * 32 + c) * 2] | (v[addr + (r * 32 + c) * 2 + 1] << 8)
                t, pal, hf, vf = w & 0x3FF, (w >> 10) & 7, (w >> 14) & 1, (w >> 15) & 1
                o = 0xE000 + t * 16
                for y in range(8):
                    a, b = v[(o + 2 * y) & 0xFFFF], v[(o + 2 * y + 1) & 0xFFFF]
                    for x in range(8):
                        k = ((a >> (7 - x)) & 1) | (((b >> (7 - x)) & 1) << 1)
                        col = rgb(cg, pal * 4 + k) if k else (0, 0, 0)
                        px[ox + (c * 8 + (7 - x if hf else x)), oy + r * 8 + (7 - y if vf else y)] = col
    if zoom != 1:
        img = img.resize((512 * zoom, 512 * zoom), Image.NEAREST)
    img.save(out)


main()
