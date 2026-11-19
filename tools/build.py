#!/usr/bin/env python3
"""HUSH build pipeline.

  build.py build         verify ROM -> roomgen (design/rooms -> build/rooms_gen.asm) -> copy to build/hush.sfc -> asar src/main.asm -> insert gfx/src (A0)
  build.py build --dev   the TEST ROM: same code and graphics, but the rooms of tests/dev/rooms (build/dev/rooms_gen.*)
                         -> build/hush_dev.sfc. Tests tagged `-- @rom dev` run on it (tools/run_test.py), so they do not
                         depend on whatever design/rooms contains.
  build.py patch         build, then flips -> dist/hush.bps (vanilla -> build)

Fails loudly on any asar warning or error. Never writes the ROM anywhere
except build/ (gitignored). The only distributable output is dist/hush.bps.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from common import (  # noqa: E402
    BUILD_DIR, BUILT_ROM, DEV_BUILD_DIR, DEV_BUILT_ROM, DEV_ROOMS_DIR, DIST_DIR, ROOT, SRC_DIR, VANILLA, die, tool_path,
    verify_vanilla,
)

MAIN_ASM = SRC_DIR / "main.asm"


def run_freespace_check(rom_check: bool, rom: Path | None = None) -> None:
    cmd = [sys.executable, str(ROOT / "tools" / "check_freespace.py")]
    if rom_check:
        cmd.append("--rom")
        if rom is not None:
            cmd += ["--rom-file", str(rom)]
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die("freespace check failed (see above).")


def run_roomgen(dev: bool = False) -> None:
    """E1: design/rooms/*.yaml -> build/rooms_gen.asm (+ report, + Lua metadata), included by src/main.asm.
    dev: tests/dev/rooms -> build/dev/rooms_gen.* (the test ROM)."""
    BUILD_DIR.mkdir(exist_ok=True)
    cmd = [sys.executable, str(ROOT / "tools" / "roomgen.py")]
    if dev:
        DEV_BUILD_DIR.mkdir(exist_ok=True)
        cmd += ["--rooms-dir", str(DEV_ROOMS_DIR), "--out-dir", str(DEV_BUILD_DIR)]
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die("room compilation failed (see above).")


def insert_graphics(rom: Path) -> None:
    """A0: PNG/palette sources in gfx/src/ -> ROM (tools/gfx_insert.py). Fails the build on any problem."""
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "gfx_insert.py"), "apply", str(rom)], cwd=ROOT)
    if r.returncode != 0:
        rom.unlink(missing_ok=True)
        die(f"graphics insertion failed (see above). Build failed; {rom.relative_to(ROOT)} removed.")


def build(dev: bool = False) -> None:
    verify_vanilla()
    print("ROM ok: headerless, 1 MiB, CRC32 777AAC2F")

    if not MAIN_ASM.exists():
        die("src/main.asm missing.")
    out_rom = DEV_BUILT_ROM if dev else BUILT_ROM
    gen_dir = DEV_BUILD_DIR if dev else BUILD_DIR
    run_roomgen(dev)
    run_freespace_check(rom_check=False)  # static: every `org` must be in the ledger

    BUILD_DIR.mkdir(exist_ok=True)
    shutil.copyfile(VANILLA, out_rom)

    asar = tool_path("HUSH_ASAR", "asar")
    gen_asm = (gen_dir / "rooms_gen.asm").relative_to(ROOT)
    cmd = [
        asar, "-werror", "--fix-checksum=off",
        f"-DHUSH_ROOMS_GEN=../{gen_asm}",   # src/main.asm: incsrc "!HUSH_ROOMS_GEN" (relative to src/)
        "--symbols=wla", f"--symbols-path={BUILD_DIR / ('hush_dev.sym' if dev else 'hush.sym')}",
        str(MAIN_ASM.relative_to(ROOT)), str(out_rom.relative_to(ROOT)),
    ]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    if out.strip():
        print(out.rstrip())
    # Belt and braces: -werror should already fail, but never trust exit codes alone.
    if r.returncode != 0 or re.search(r"\b(warning|error)\b", out, re.I):
        out_rom.unlink(missing_ok=True)
        die(f"asar reported problems (exit {r.returncode}). Build failed; {out_rom.relative_to(ROOT)} removed.")

    insert_graphics(out_rom)
    run_freespace_check(rom_check=True, rom=out_rom)  # actual bytes written (asar + graphics) must be in the ledger
    print(f"built {out_rom.relative_to(ROOT)}")


def patch() -> None:
    build()
    if BUILT_ROM.read_bytes() == VANILLA.read_bytes():
        print(
            "WARNING: build is byte-identical to vanilla (no hooks yet), so there is "
            "nothing to patch. dist/hush.bps not written."
        )
        return
    DIST_DIR.mkdir(exist_ok=True)
    out = DIST_DIR / "hush.bps"
    out.unlink(missing_ok=True)
    flips = tool_path("HUSH_FLIPS", "flips")
    r = subprocess.run(
        [flips, "--create", "--bps", str(VANILLA), str(BUILT_ROM), str(out)],
        capture_output=True, text=True,
    )
    if r.returncode != 0 or not out.exists():
        die(f"flips failed (exit {r.returncode}): {r.stdout}{r.stderr}")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size} bytes)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["build", "patch"])
    ap.add_argument("--dev", action="store_true", help="build the test ROM build/hush_dev.sfc from tests/dev/rooms")
    args = ap.parse_args()
    if args.dev and args.command == "patch":
        die("--dev ROMs are test builds; they are never patched/distributed.")
    if args.command == "patch":
        patch()
    else:
        build(args.dev)


if __name__ == "__main__":
    main()
