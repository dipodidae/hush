#!/usr/bin/env python3
"""ALttP graphics compression: compressor matching the game's own decompressor.

  gfx_compress.py --selftest [--full]   round-trip tests (synthetic + sampled vanilla sheets; --full = all, ~2 min)

Format (verified in vendor/usdasm/bank_00.asm:12857-13030, `Decompress`, see docs/gfx/formats.md):
  header byte  CCCLLLLL            cmd = CCC, length = LLLLL + 1 (1..32)
  header       111CCCLL + LLLLLLLL  expanded: cmd = CCC, length = (LL<<8 | next) + 1 (1..1024)
  cmd 0 raw copy (n bytes follow)         cmd 1 repeat one byte n times (1 byte follows)
  cmd 2 repeat a 2-byte pair, alternating (2 bytes follow)
  cmd 3 incrementing bytes: v, v+1, ...  (1 byte follows)
  cmd 4 copy n bytes from earlier OUTPUT offset (2 bytes follow, little endian, absolute)
  $FF terminates the stream.
The compressor is an optimal-parse (shortest output) DP over these commands.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def _hdr(cmd: int, n: int) -> bytes:
    """Header bytes for command `cmd` (0..4) and length n (1..1024)."""
    if n <= 32:
        return bytes([(cmd << 5) | (n - 1)])
    v = n - 1
    return bytes([0xE0 | (cmd << 2) | (v >> 8), v & 0xFF])


def _hlen(n: int) -> int:
    return 1 if n <= 32 else 2


def compress(data: bytes) -> bytes:
    n = len(data)
    INF = 1 << 30
    cost = [INF] * (n + 1)
    choice: list[tuple | None] = [None] * (n + 1)
    cost[0] = 0
    # index for copy candidates: 3-byte prefix -> earlier positions
    index: dict[bytes, list[int]] = {}
    for i in range(n):
        if cost[i] >= INF:
            continue
        c0 = cost[i]
        # raw: extend lazily: cost of raw run of k bytes = hlen(k) + k
        for k in (1, 2, 3, 4, 5, 6, 8, 12, 16, 24, 32, 48, 64, 128, 256, 512, 1024):
            if i + k > n:
                break
            c = c0 + _hlen(k) + k
            if c < cost[i + k]:
                cost[i + k] = c; choice[i + k] = (0, i, k, None)
        # repeat byte
        b = data[i]
        run = 1
        while i + run < n and data[i + run] == b and run < 1024:
            run += 1
        for k in sorted({run, *(x for x in (2, 3, 4, 8, 16, 32, 64, 128, 256, 512) if x <= run)}):
            c = c0 + _hlen(k) + 1
            if c < cost[i + k]:
                cost[i + k] = c; choice[i + k] = (1, i, k, b)
        # repeat word (alternating pair)
        if i + 1 < n:
            a, b2 = data[i], data[i + 1]
            run = 2
            while i + run < n and data[i + run] == (a if run % 2 == 0 else b2) and run < 1024:
                run += 1
            for k in sorted({run, *(x for x in (4, 6, 8, 16, 32, 64, 128, 256, 512) if x <= run)}):
                if k < 3:
                    continue
                c = c0 + _hlen(k) + 2
                if c < cost[i + k]:
                    cost[i + k] = c; choice[i + k] = (2, i, k, (a, b2))
        # incrementing
        run = 1
        while i + run < n and data[i + run] == ((data[i] + run) & 0xFF) and run < 1024:
            run += 1
        for k in sorted({run, *(x for x in (3, 4, 8, 16, 32, 64, 128, 256) if x <= run)}):
            if k < 3:
                continue
            c = c0 + _hlen(k) + 1
            if c < cost[i + k]:
                cost[i + k] = c; choice[i + k] = (3, i, k, data[i])
        # copy from earlier output (non-overlapping or overlapping both fine in this decoder)
        if i + 3 <= n:
            for j in index.get(data[i:i + 3], [])[-48:]:
                m = 3
                while i + m < n and data[j + m] == data[i + m] and m < 1024:
                    m += 1
                for k in sorted({m, *(x for x in (3, 4, 5, 6, 8, 12, 16, 24, 32, 64, 128, 256, 512) if x <= m)}):
                    c = c0 + _hlen(k) + 2
                    if c < cost[i + k]:
                        cost[i + k] = c; choice[i + k] = (4, i, k, j)
        index.setdefault(data[i:i + 3], []).append(i)
    # reconstruct
    cmds = []
    p = n
    while p > 0:
        ch = choice[p]
        assert ch is not None
        cmds.append(ch)
        p = ch[1]
    out = bytearray()
    for cmd, start, k, arg in reversed(cmds):
        out += _hdr(cmd, k)
        if cmd == 0:
            out += data[start:start + k]
        elif cmd == 1:
            out.append(arg)
        elif cmd == 2:
            out += bytes(arg)
        elif cmd == 3:
            out.append(arg)
        else:
            out += bytes((arg & 0xFF, arg >> 8))
    out.append(0xFF)
    return bytes(out)


def decompress_bytes(blob: bytes) -> bytes:
    """Pure-Python port of the game's decompressor operating on a byte string."""
    p, out = 0, bytearray()
    while True:
        c = blob[p]; p += 1
        if c == 0xFF:
            return bytes(out)
        cmd = c & 0xE0
        if cmd == 0xE0:
            cmd = (c << 3) & 0xE0
            n = (((c & 3) << 8) | blob[p]) + 1; p += 1
        else:
            n = (c & 0x1F) + 1
        if cmd == 0x00:
            out += blob[p:p + n]; p += n
        elif cmd == 0x20:
            out += bytes([blob[p]]) * n; p += 1
        elif cmd == 0x40:
            a, b = blob[p], blob[p + 1]; p += 2
            out += bytes(a if k % 2 == 0 else b for k in range(n))
        elif cmd == 0x60:
            v = blob[p]; p += 1
            out += bytes((v + k) & 0xFF for k in range(n))
        elif cmd == 0x80:
            off = blob[p] | (blob[p + 1] << 8); p += 2
            for k in range(n):
                out.append(out[off + k])
        else:
            raise ValueError(f"bad command byte {c:02X}")


def selftest(full: bool = False) -> int:
    import random
    from common import verify_vanilla
    from gfxlib import LAST_SHEET, UNCOMPRESSED, decompress, sheet_pointer

    rng = random.Random(1234)
    cases = [b"", b"\x00", b"\x00" * 3000, bytes(range(256)) * 3, bytes(rng.randrange(256) for _ in range(1536)),
             b"AB" * 700, (b"\x12\x34\x56" * 50) + bytes(rng.randrange(4) for _ in range(500))]
    for k in range(40):
        cases.append(bytes(rng.choice([0, 0, 0, 0xFF, 0x55, rng.randrange(256)]) for _ in range(rng.randrange(1, 2000))))
    for c in cases:
        z = compress(c)
        assert decompress_bytes(z) == c, "synthetic round trip failed"
    print(f"gfx_compress selftest: {len(cases)} synthetic cases round-trip OK")

    rom = verify_vanilla()
    ok = total_vanilla = total_ours = 0
    seen = set()
    for i in range(LAST_SHEET + 1):
        if i in UNCOMPRESSED:
            continue
        if not full and i % 9 != 0 and i not in (0x00, 0x07, 0xDB):   # sample; --full does all (~2 min)
            continue
        a = sheet_pointer(rom, i)
        if a in seen:
            continue
        seen.add(a)
        raw, clen = decompress(rom, a)
        # (a) our decoder agrees with the ROM-reading decoder on the vanilla stream
        from gfxlib import pc
        assert decompress_bytes(rom[pc(a):pc(a) + clen]) == raw, f"decoder mismatch GFX_{i:02X}"
        # (b) recompress -> decompress gives the same bytes
        z = compress(raw)
        assert decompress_bytes(z) == raw, f"round trip failed GFX_{i:02X}"
        ok += 1; total_vanilla += clen; total_ours += len(z)
    print(f"gfx_compress selftest: {ok} vanilla sheets round-trip OK "
          f"(vanilla {total_vanilla} B, ours {total_ours} B)")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest("--full" in sys.argv))
    print(__doc__)
    sys.exit(2)
