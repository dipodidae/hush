"""Shared graphics helpers for HUSH tools (stdlib only).

Format facts are cited in docs/gfx/formats.md. Everything here is derived from
the vendor/ disassembly and verified against the vanilla ROM.
"""
from __future__ import annotations

from common import snes_to_pc

# --- sheet pointer table: bank_00.asm GFXSheetPointers, $00CF80 -------------------
# 6 consecutive tables (usdasm bank_00.asm:8383-8999 region):
#   bg_bank[0x73] bg... see docs/gfx/formats.md
BG_COUNT = 0x73            # background table entries: GFX_00..GFX_72  (CF80.. CFF2)
SPR_COUNT = 0x6C           # sprite table entries:     GFX_73..GFX_DE  (CFF3.. D05E)
PTR_BASE = 0x00CF80
BG_BANK = PTR_BASE
SPR_BANK = PTR_BASE + BG_COUNT
BG_HIGH = SPR_BANK + SPR_COUNT
SPR_HIGH = BG_HIGH + BG_COUNT
BG_LOW = SPR_HIGH + SPR_COUNT
SPR_LOW = BG_LOW + BG_COUNT
SPR_OFFSET = 0x73          # sprite table index i -> sheet id 0x73 + i
LAST_SHEET = 0xDE

LINK_ADDR = 0x108000       # graphics.asm:6 (LinkGraphics, uncompressed 4bpp)
LINK_SIZE = 0x7000         # 896 tiles * 32 bytes; verified in formats.md
FONT_ADDR = 0x0E8000       # bank_0E.asm:6  TheFont (uncompressed 2bpp)
FONT_SIZE = 0x1000         # TheFont.size, verified in formats.md
WORLDMAP_ADDR = 0x18C000   # graphics.asm:281 (mode 7, 8bpp, 0x4000 bytes)

BPP_BY_RANGE = [(0x00, 0xD9, 3), (0xDA, 0xDE, 2)]   # sheets 00-D9 3bpp, DA-DE 2bpp (graphics.asm)
UNCOMPRESSED = range(0x73, 0x7F)                    # GFX_73..GFX_7E, 0x600 bytes each (graphics.asm:9-23)
BLANK = list(range(0x61, 0x71)) + [0x9E]            # 7-byte "blank" streams (graphics.asm)


def pc(addr: int) -> int:
    return snes_to_pc(addr)


def sheet_bpp(i: int) -> int:
    return 2 if i >= 0xDA else 3


def sheet_pointer(rom: bytes, i: int) -> int:
    """SNES address of sheet i's data, read from the ROM's own pointer table."""
    if i < BG_COUNT:
        b, h, l = (rom[pc(t + i)] for t in (BG_BANK, BG_HIGH, BG_LOW))
    else:
        j = i - SPR_OFFSET
        b, h, l = (rom[pc(t + j)] for t in (SPR_BANK, SPR_HIGH, SPR_LOW))
    return (b << 16) | (h << 8) | l


def decompress(rom: bytes, addr: int) -> tuple[bytes, int]:
    """ALttP decompression (bank_00.asm:12857 Decompress). Returns (data, compressed_len)."""
    p = pc(addr)
    start = p
    out = bytearray()
    while True:
        c = rom[p]; p += 1
        if c == 0xFF:
            break
        cmd = c & 0xE0
        if cmd == 0xE0:
            cmd = (c << 3) & 0xE0
            n = (((c & 3) << 8) | rom[p]) + 1; p += 1
        else:
            n = (c & 0x1F) + 1
        if cmd == 0x00:
            out += rom[p:p + n]; p += n
        elif cmd == 0x20:
            out += bytes([rom[p]]) * n; p += 1
        elif cmd == 0x40:
            a, b = rom[p], rom[p + 1]; p += 2
            for k in range(n):
                out.append(a if k % 2 == 0 else b)
        elif cmd == 0x60:
            v = rom[p]; p += 1
            for k in range(n):
                out.append((v + k) & 0xFF)
        elif cmd == 0x80:
            off = rom[p] | (rom[p + 1] << 8); p += 2
            for k in range(n):
                out.append(out[off + k])
        else:
            raise ValueError(f"bad command {c:02X} at ${addr:06X}+{p - start - 1:X}")
    return bytes(out), p - start


# --- planar tile codecs ------------------------------------------------------------

def tile_bytes(bpp: int) -> int:
    return {2: 16, 3: 24, 4: 32, 8: 64}[bpp]


def decode_tile(data: bytes, bpp: int) -> list[list[int]]:
    """One 8x8 tile -> rows of pixel values (SNES planar; 3bpp = ALttP layout: planes 0/1
    interleaved by row, then plane 2 as 8 bytes)."""
    rows = [[0] * 8 for _ in range(8)]
    for y in range(8):
        planes = [data[2 * y], data[2 * y + 1]]
        if bpp >= 3:
            planes.append(data[16 + y] if bpp == 3 else data[16 + 2 * y])
        if bpp == 4:
            planes.append(data[17 + 2 * y])
        for x in range(8):
            v = 0
            for p, b in enumerate(planes):
                v |= ((b >> (7 - x)) & 1) << p
            rows[y][x] = v
    return rows


def encode_tile(rows: list[list[int]], bpp: int) -> bytes:
    out = bytearray()
    if bpp not in (2, 3, 4):
        raise ValueError(bpp)
    pl = [[0] * 8 for _ in range(bpp)]
    for y in range(8):
        for x in range(8):
            v = rows[y][x]
            for p in range(bpp):
                pl[p][y] |= ((v >> p) & 1) << (7 - x)
    for y in range(8):
        out += bytes((pl[0][y], pl[1][y]))
    if bpp == 3:
        out += bytes(pl[2])
    elif bpp == 4:
        for y in range(8):
            out += bytes((pl[2][y], pl[3][y]))
    return bytes(out)


def tiles_of(data: bytes, bpp: int) -> list[bytes]:
    n = tile_bytes(bpp)
    return [data[i:i + n] for i in range(0, len(data) - n + 1, n)]
