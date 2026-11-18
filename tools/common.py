"""Shared helpers for HUSH tools. Stdlib only."""
from __future__ import annotations

import os
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VANILLA = ROOT / "rom" / "vanilla.sfc"
BUILD_DIR = ROOT / "build"
BUILT_ROM = BUILD_DIR / "hush.sfc"
DIST_DIR = ROOT / "dist"
SRC_DIR = ROOT / "src"
FREESPACE_MD = SRC_DIR / "FREESPACE.md"

# US 1.0 ROM facts. Source of truth for the whole project.
VANILLA_SIZE = 1024 * 1024
VANILLA_CRC32 = 0x777AAC2F
COPIER_HEADER = 512


def die(msg: str, code: int = 1) -> "NoReturn":  # noqa: F821
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def tool_path(env_var: str, local_name: str, system_name: str | None = None) -> str:
    """Resolve an external tool: env override, then .tools/bin, then PATH."""
    override = os.environ.get(env_var)
    if override:
        return override
    local = ROOT / ".tools" / "bin" / local_name
    if local.exists():
        return str(local)
    from shutil import which

    found = which(system_name or local_name)
    if found:
        return found
    die(f"{local_name} not found. Run `make setup` (or set {env_var}).")


def crc32_of(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def verify_vanilla(path: Path = VANILLA) -> bytes:
    """Return the ROM bytes if it is the headerless US 1.0 ROM; else die.

    A copier header is reported, never silently stripped.
    """
    if not path.exists():
        die(
            f"{path.relative_to(ROOT)} not found. Place your own US 1.0 ROM there "
            "(see README: 'What you must do manually')."
        )
    data = path.read_bytes()
    if len(data) == VANILLA_SIZE + COPIER_HEADER:
        die(
            f"{path.relative_to(ROOT)} has a {COPIER_HEADER}-byte copier header "
            f"(size {len(data)}). I will not strip it for you. Remove the header "
            "yourself (e.g. `tail -c +513 in.smc > rom/vanilla.sfc`), then retry."
        )
    if len(data) != VANILLA_SIZE:
        die(f"{path.relative_to(ROOT)} is {len(data)} bytes; expected exactly {VANILLA_SIZE} (1 MiB).")
    crc = crc32_of(data)
    if crc != VANILLA_CRC32:
        die(
            f"{path.relative_to(ROOT)} CRC32 is {crc:08X}; expected {VANILLA_CRC32:08X} "
            "(The Legend of Zelda: A Link to the Past, US 1.0)."
        )
    return data


def snes_to_pc(addr: int) -> int:
    """LoROM SNES address -> file offset. Raises ValueError for non-ROM addresses."""
    bank, off = (addr >> 16) & 0xFF, addr & 0xFFFF
    if off < 0x8000:
        raise ValueError(f"${addr:06X} is not a LoROM ROM address (offset < $8000)")
    if bank in range(0x40, 0x70) or bank in range(0x7E, 0x80) or bank >= 0xFE:
        raise ValueError(f"${addr:06X} is outside LoROM ROM banks")
    return ((bank & 0x7F) * 0x8000) + (off - 0x8000)


def pc_to_snes(pc: int) -> int:
    return (((pc // 0x8000) & 0x7F) << 16) | (0x8000 + pc % 0x8000)
