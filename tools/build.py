#!/usr/bin/env python3
"""HUSH build pipeline.

  build.py build   verify ROM -> copy to build/hush.sfc -> asar src/main.asm -> insert gfx/src (A0)
  build.py patch   build, then flips -> dist/hush.bps (vanilla -> build)

Fails loudly on any asar warning or error. Never writes the ROM anywhere
except build/ (gitignored). The only distributable output is dist/hush.bps.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from common import (  # noqa: E402
    BUILD_DIR, BUILT_ROM, DIST_DIR, ROOT, SRC_DIR, VANILLA, die, tool_path, verify_vanilla,
)

MAIN_ASM = SRC_DIR / "main.asm"


def run_freespace_check(rom_check: bool) -> None:
    cmd = [sys.executable, str(ROOT / "tools" / "check_freespace.py")]
    if rom_check:
        cmd.append("--rom")
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die("freespace check failed (see above).")


def insert_graphics() -> None:
    """A0: PNG/palette sources in gfx/src/ -> ROM (tools/gfx_insert.py). Fails the build on any problem."""
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "gfx_insert.py"), "apply", str(BUILT_ROM)], cwd=ROOT)
    if r.returncode != 0:
        BUILT_ROM.unlink(missing_ok=True)
        die("graphics insertion failed (see above). Build failed; build/hush.sfc removed.")


def build() -> None:
    verify_vanilla()
    print("ROM ok: headerless, 1 MiB, CRC32 777AAC2F")

    if not MAIN_ASM.exists():
        die("src/main.asm missing.")
    run_freespace_check(rom_check=False)  # static: every `org` must be in the ledger

    BUILD_DIR.mkdir(exist_ok=True)
    shutil.copyfile(VANILLA, BUILT_ROM)

    asar = tool_path("HUSH_ASAR", "asar")
    cmd = [
        asar, "-werror", "--fix-checksum=off",
        "--symbols=wla", f"--symbols-path={BUILD_DIR / 'hush.sym'}",
        str(MAIN_ASM.relative_to(ROOT)), str(BUILT_ROM.relative_to(ROOT)),
    ]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    if out.strip():
        print(out.rstrip())
    # Belt and braces: -werror should already fail, but never trust exit codes alone.
    if r.returncode != 0 or re.search(r"\b(warning|error)\b", out, re.I):
        BUILT_ROM.unlink(missing_ok=True)
        die(f"asar reported problems (exit {r.returncode}). Build failed; build/hush.sfc removed.")

    insert_graphics()
    run_freespace_check(rom_check=True)  # actual bytes written (asar + graphics) must be in the ledger
    print(f"built {BUILT_ROM.relative_to(ROOT)}")


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
    args = ap.parse_args()
    {"build": build, "patch": patch}[args.command]()


if __name__ == "__main__":
    main()
