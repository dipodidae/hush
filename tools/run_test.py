#!/usr/bin/env python3
"""Run HUSH Lua tests headless in MesenCE (--testRunner).

  run_test.py tests/smoke/boot.lua
  run_test.py tests/smoke/read_link.lua --state tests/states/test_room.mss
  run_test.py --suite smoke --suite solutions        # every tests/<suite>/*.lua
  run_test.py --suite chaos

For each test:
  * runs build/hush.sfc (run `make build` first) with a fresh, isolated MesenCE
    settings directory (Lua I/O enabled, settings never saved);
  * the exit code comes from emu.stop(code) in the script; a timeout or crash
    is a failure;
  * stdout, stderr, screenshots and dumps are kept in build/test-results/<test>/.

Script header tags (in Lua comments, first 20 lines):
  -- @requires-state     skip (not fail) if the savestate file does not exist;
                         default state is tests/states/test_room.mss
  -- @timeout <seconds>  override the default timeout (60)

Exit code: 0 if nothing failed. Skips do not fail unless --strict / HUSH_STRICT=1.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import BUILD_DIR, BUILT_ROM, ROOT, die  # noqa: E402

TESTS_DIR = ROOT / "tests"
RESULTS_DIR = Path(os.environ["HUSH_RESULTS"]).resolve() if os.environ.get("HUSH_RESULTS") else BUILD_DIR / "test-results"
DEFAULT_STATE = TESTS_DIR / "states" / "test_room.mss"
DEFAULT_TIMEOUT = 60
SUITES = ("smoke", "solutions", "chaos", "gfx")
# HUSH_ROM overrides the ROM under test (used for the leak detector's vanilla-graphics control build)
ROM_UNDER_TEST = Path(os.environ["HUSH_ROM"]).resolve() if os.environ.get("HUSH_ROM") else BUILT_ROM
NOISE = re.compile(r"^\[(CPU|SA1)\] Uninitialized memory read: \$[0-9A-Fa-f]+$")

# Pre-seeded MesenCE settings. Only what the harness needs: Lua io/os access.
# (Key path verified in MesenCE 2.2.1 UI/Config/Debugger/{DebugConfig,ScriptWindowConfig}.cs;
#  settings.json uses PascalCase property names.)
SETTINGS = {"Debug": {"ScriptWindow": {"AllowIoOsAccess": True}}}


@dataclass
class Result:
    name: str
    status: str  # PASS FAIL TIMEOUT SKIP
    seconds: float = 0.0
    detail: str = ""
    out_dir: Path | None = None
    tags: dict = field(default_factory=dict)


def parse_tags(script: Path) -> dict:
    tags: dict = {}
    for line in script.read_text().splitlines()[:20]:
        m = re.match(r"^\s*--\s*@([\w-]+)\s*(.*?)\s*$", line)
        if m:
            tags[m.group(1)] = m.group(2) or True
    return tags


def test_name(script: Path) -> str:
    try:
        rel = script.resolve().relative_to(TESTS_DIR)
    except ValueError:
        rel = Path(script.name)
    return str(rel.with_suffix("")).replace(os.sep, "_")


def mesen_cmd() -> list[str]:
    mesen = os.environ.get("HUSH_MESEN") or str(ROOT / ".tools" / "mesen" / "Mesen")
    if not Path(mesen).exists():
        die(f"MesenCE not found at {mesen}. Run `make setup` (or set HUSH_MESEN).")
    cmd = [mesen]
    if not os.environ.get("DISPLAY") and not os.environ.get("HUSH_NO_XVFB") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a"] + cmd
    return cmd


def run_one(script: Path, state: Path | None, timeout: int | None, keep_home: bool = False) -> Result:
    name = test_name(script)
    tags = parse_tags(script)
    out_dir = RESULTS_DIR / name
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    if tags.get("requires-state") and state is None:
        state = DEFAULT_STATE
    if state is not None and not state.exists():
        if tags.get("requires-state"):
            shown = state.relative_to(ROOT) if state.is_relative_to(ROOT) else state
            msg = f"missing savestate {shown} (see README: making test_room.mss)"
            return Result(name, "SKIP", 0.0, msg, out_dir, tags)
        return Result(name, "FAIL", 0.0, f"--state file not found: {state}", out_dir, tags)

    if timeout is None:
        try:
            timeout = int(tags.get("timeout", DEFAULT_TIMEOUT))
        except (TypeError, ValueError):
            timeout = DEFAULT_TIMEOUT

    # Fresh isolated settings dir per test: no shared saves/SRAM/settings.
    home = out_dir / "home"
    (home / "MesenCE").mkdir(parents=True)
    (home / "MesenCE" / "settings.json").write_text(json.dumps(SETTINGS))

    env = os.environ.copy()
    env.update(
        HOME=str(home),
        XDG_CONFIG_HOME=str(home),
        XDG_DATA_HOME=str(home / "data"),
        HUSH_ROOT=str(ROOT),
        HUSH_OUT=str(out_dir),
        HUSH_STATE=str(state.resolve()) if state else "",
    )
    cmd = mesen_cmd() + [
        "--testRunner", "--doNotSaveSettings", "--enableStdout", f"--timeout={timeout}",
        "--snes.ramPowerOnState=AllZeros",  # reproducible cold boots (default is Random)
        "--snes.port1.type=SnesController",  # a fresh config has no controller; setInput needs one
        str(script.resolve()), str(ROM_UNDER_TEST),
    ]

    t0 = time.monotonic()
    proc = subprocess.Popen(
        cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, errors="replace", start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout + 15)
        timed_out = False
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        timed_out = True
    secs = time.monotonic() - t0

    # The debugger logs one line per never-written WRAM byte read at boot. Pure noise.
    raw_lines = (stdout or "").splitlines()
    noise = [ln for ln in raw_lines if NOISE.match(ln)]
    stdout = "\n".join(ln for ln in raw_lines if not NOISE.match(ln)) + "\n"
    (out_dir / "stdout.txt").write_text(stdout)
    (out_dir / "stderr.txt").write_text(stderr or "")
    (out_dir / "meta.json").write_text(json.dumps({
        "cmd": cmd, "returncode": proc.returncode, "seconds": round(secs, 2),
        "timeout": timeout, "state": str(state) if state else None,
        "filtered_uninit_read_lines": len(noise),
    }, indent=2))
    if not keep_home:
        shutil.rmtree(home, ignore_errors=True)

    fail_line = next((ln for ln in (stdout or "").splitlines() if ln.startswith("HUSH_RESULT: FAIL")), None)
    rc = proc.returncode
    # Mesen's own timeout returns -1 (exit 255) without an emu.stop().
    if timed_out or (rc == 255 and "HUSH_RESULT:" not in (stdout or "")):
        status, detail = "TIMEOUT", f"no emu.stop() within {timeout}s"
    elif rc == 0 and not fail_line:
        status, detail = "PASS", ""
    else:
        status = "FAIL"
        detail = (fail_line or f"exit code {rc}").replace("HUSH_RESULT: FAIL - ", "")
        if not fail_line and (stderr or "").strip():
            detail += ": " + stderr.strip().splitlines()[-1]
    return Result(name, status, secs, detail, out_dir, tags)


def collect(suites: list[str], scripts: list[str]) -> list[Path]:
    found: list[Path] = [Path(s) for s in scripts]
    for suite in suites:
        d = TESTS_DIR / suite
        found.extend(sorted(d.glob("*.lua")) if d.is_dir() else [])
    return found


def print_table(results: list[Result]) -> None:
    if not results:
        return
    w = max(len(r.name) for r in results)
    print()
    print(f"{'TEST'.ljust(w)}  {'STATUS':8} {'TIME':>6}  DETAIL")
    print(f"{'-' * w}  {'-' * 8} {'-' * 6}  {'-' * 40}")
    for r in results:
        print(f"{r.name.ljust(w)}  {r.status:8} {r.seconds:5.1f}s  {r.detail}")
    counts = {s: sum(1 for r in results if r.status == s) for s in ("PASS", "FAIL", "TIMEOUT", "SKIP")}
    print()
    print("  ".join(f"{k}={v}" for k, v in counts.items()))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scripts", nargs="*", help="Lua test scripts")
    ap.add_argument("--suite", action="append", default=[], choices=SUITES, help="run every tests/<suite>/*.lua")
    ap.add_argument("--state", type=Path, help="savestate to load before the script starts")
    ap.add_argument("--timeout", type=int, help=f"seconds (default {DEFAULT_TIMEOUT}, or the script's @timeout tag)")
    ap.add_argument("--strict", action="store_true", help="treat SKIP as failure")
    ap.add_argument("--keep-home", action="store_true", help="keep the isolated MesenCE home dir")
    args = ap.parse_args()

    if not args.scripts and not args.suite:
        ap.error("give a script or --suite")
    if not ROM_UNDER_TEST.exists():
        die(f"{ROM_UNDER_TEST} not found. Run `make build` first.")

    scripts = collect(args.suite, args.scripts)
    if not scripts:
        print(f"no tests found in suite(s): {', '.join(args.suite)}")
        return 0
    for s in scripts:
        if not Path(s).exists():
            die(f"script not found: {s}")

    results: list[Result] = []
    for s in scripts:
        print(f"running {test_name(Path(s))} ...", flush=True)
        r = run_one(Path(s), args.state, args.timeout, args.keep_home)
        results.append(r)
        if len(scripts) == 1 or r.status in ("FAIL", "TIMEOUT"):
            for fname in ("stdout.txt", "stderr.txt"):
                p = r.out_dir / fname if r.out_dir else None
                text = p.read_text() if p and p.exists() else ""
                if text.strip():
                    print(f"--- {fname} ---\n{text.rstrip()}\n---")
    print_table(results)
    strict = args.strict or os.environ.get("HUSH_STRICT") == "1"
    bad = [r for r in results if r.status in ("FAIL", "TIMEOUT") or (strict and r.status == "SKIP")]
    if any(r.status == "SKIP" for r in results) and not strict:
        print("note: skipped tests need a savestate you create by hand (README). `make test STRICT=1` fails on skips.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
