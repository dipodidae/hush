"""The cast palettes (single source of truth for the painters; the same colours are in gfx/src/palettes/*.yaml).

Colour rules: amber = danger (guards, lantern, alert icons), violet = you (Link, Shade Knife, darts, ink pots).
Hex are BGR555-exact (low 3 bits clear).  Index 1 = outline ... 7 = accent; colours[8..15] of a row are indices 1..7 again.
"""
from cast_common import snap

# OBJ row 4 left (guards, calm / asleep): steel-blue uniform, darker slate helmet, amber lantern.
GUARD = [snap(h) for h in ("081018", "284868", "102038", "4C88A8", "F0A838", "D8E8F8", "40C8B8")]
# OBJ row 4 right (awareness icons + shadow): 1 outline/shadow core, 2 soft shadow, 3 dark amber, 4 pale gold '?', 5 amber '!', 6/7 teal 'Z'
ICON = [snap(h) for h in ("081018", "16143A", "8A5A14", "F6D878", "F0A838", "90ECE0", "38A898")]
# OBJ row 2 left+right, row 1 right, row 3 (player FX: dart, ink pot, poof, sparkles): monotone violet ramp, cyan-white glint, teal.
FX = [snap(h) for h in ("080818", "40307C", "181050", "6A48C8", "A884F8", "E0F8F8", "38E0D0")]
# OBJ row 1 left = runtime asm constant Hush_PalInk (src/hooks/guard_runtime.asm), BGR555 words -> hex; do not edit here.
def _bgr(w):
    return "%02X%02X%02X" % ((w & 31) << 3, ((w >> 5) & 31) << 3, ((w >> 10) & 31) << 3)
INK = [_bgr(w) for w in (0x0C21, 0x2043, 0x1822, 0x30A5, 0x4CE9, 0x7211, 0x79F5)]
ALERT = [_bgr(w) for w in (0x0C21, 0x0DD9, 0x090F, 0x331E, 0x2F5F, 0x6BDF, 0x79F5)]
# Shade Knife blade (OBJ row 5 right, indices 1-3): violet, cyan-white glint, deep violet.
BLADE = [snap(h) for h in ("8A5CE8", "D6FFF8", "30206C")]
