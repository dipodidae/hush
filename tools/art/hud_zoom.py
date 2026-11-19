#!/usr/bin/env python3
"""hud_zoom.py: crop the HUD area (top-left 256x72) of 256x224 emulator screenshots and scale them up (nearest).
  .venv/bin/python tools/art/hud_zoom.py OUT.png IN1.png [IN2.png ...] [--zoom 4] [--full]
Several inputs are stacked vertically (for before/after or stage comparison)."""
import sys
from PIL import Image

args = [a for a in sys.argv[1:]]
zoom = 4
full = False
if "--zoom" in args:
    i = args.index("--zoom"); zoom = int(args[i + 1]); del args[i:i + 2]
if "--full" in args:
    args.remove("--full"); full = True
out, ins = args[0], args[1:]
ims = []
for p in ins:
    im = Image.open(p).convert("RGB")
    if not full:
        im = im.crop((0, 8, 256, 72))
    ims.append(im.resize((im.width * zoom, im.height * zoom), Image.NEAREST))
H = sum(i.height for i in ims) + 4 * (len(ims) - 1)
res = Image.new("RGB", (ims[0].width, H), (90, 90, 90))
y = 0
for i in ims:
    res.paste(i, (0, y)); y += i.height + 4
res.save(out)
print(out, res.size)
