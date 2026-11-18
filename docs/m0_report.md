# M0 report: dev environment and harness

Milestone: **M0 (harness)**. Status: **complete, awaiting human gate approval.**
Commit: `dfb6aef` (branch `main`). Date: 2026-11-18.

M0 scope was tooling, repo scaffold, build pipeline, headless test harness, room
spec system and agent definitions. No game features were started.

## 1. Environment

Host: Ubuntu 26.04, x86_64, zsh, opencode 1.19.5.

| Tool | Version | How installed | Location |
|---|---|---|---|
| Python + venv | 3.14.5 | system python, `python3 -m venv` | `.venv/` |
| Pillow / PyYAML | 13.0.0 / 6.0.3 | pip | `.venv/` |
| asar | 1.91 (`v1.91` tag) | built from source with CMake | `.tools/bin/asar` |
| Floating IPS (flips) | v198, CLI build | built from source (`make TARGET=cli`) | `.tools/bin/flips` |
| MesenCE | 2.2.1 | official Linux x64 release (`nesdev-org/MesenCE`) | `.tools/mesen/Mesen` |
| apt packages | cmake, xvfb, python3-venv, libsdl2-2.0-0 | `apt-get` | system |

Everything under `.tools/`, `.venv/` and `vendor/` is gitignored and rebuilt by
`make setup` / `make vendor`. `tools/setup.sh` is idempotent and prints the exact
`apt` line if a system package is missing.

### Tooling decisions

- **flips:** the GitHub release binary links GTK, which is not wanted on a
  headless box. The CLI build is made from source instead. The canonical repo
  `Alcaro/Flips` redirects to `Sir-Walrus/Flips`, which is what is built.
- **MesenCE:** the continuation of Mesen2 is `nesdev-org/MesenCE`. `--testRunner`
  was confirmed in source (`UI/Utilities/TestRunner.cs`,
  `UI/Utilities/CommandLineHelper.cs`) and by running it. Lua I/O access is off
  by default; the harness enables it through a per-test `settings.json`.
- **scawful/mesen2-oos:** evaluated, **not adopted**. No releases (source build
  only), README documents almost nothing about the API, it targets Oracle of
  Secrets, and MesenCE `--testRunner` plus Lua already covers M0 to M5.
  Revisit only if live external control (a socket) is needed.
- **vendor/:** reference disassemblies are cloned (not submoduled) at pinned
  commits by `tools/fetch_vendor.sh`. They are large, reference-only, and some
  have unclear licences, so they are never committed. Pinned commits:
  - `AsarUSALTTPDisassembly` `28cc91a2`
  - `usdasm` `bcdd96e9`
  - `alttp-disassembly` `79207d17`
- **ZScream:** Windows GUI editor, not installed. Noted in the README.

## 2. ROM verification

Source: `/mnt/drive/roms/nintendo/snes/1 US - F-M/Legend of Zelda, The - A Link to the Past (USA).sfc`,
copied to `rom/vanilla.sfc` (gitignored).

- Size 1,048,576 bytes, no copier header, CRC32 `777AAC2F`: matches US 1.0.
- `tools/common.py::verify_vanilla` re-checks this on every build. A 512-byte
  header is reported and never stripped; a wrong size or CRC aborts the build.

## 3. Build pipeline

`make build` runs `tools/build.py`:

1. Verify the ROM (above).
2. Static ledger check: every `org` in `src/**/*.asm` must be a literal
   `$BBAAAA` inside a region in `src/FREESPACE.md`; `freecode`, `freedata`,
   `freespace`, `autoclean` are banned; regions must not overlap.
3. Copy the ROM to `build/hush.sfc`.
4. Run asar with `-werror --fix-checksum=off`, and additionally scan its output
   for "warning" or "error". On any problem, `build/hush.sfc` is deleted.
5. Byte-diff vanilla against the build; every changed run must lie inside one
   ledger region.

`make patch` builds, then creates `dist/hush.bps` with flips. While the build is
identical to vanilla it writes nothing and says so.

### Negative cases exercised

| Case | Result |
|---|---|
| `org` outside the ledger | build fails |
| asar `warn` | build fails, output ROM removed |
| 2 bytes written where the ledger covers 1 | build fails (diff check) |
| overlapping ledger rows | check fails |
| `freecode` | check fails |
| ROM with 512-byte header | refused, not stripped |
| ROM with wrong CRC | refused |
| BPS round trip (vanilla + `hush.bps`) | byte-identical to `build/hush.sfc` |

The ledger itself (`src/FREESPACE.md`) is empty: no ROM space is claimed yet.

## 4. Test harness

`tools/run_test.py` runs MesenCE with `--testRunner --doNotSaveSettings
--enableStdout --timeout=N`, wrapped in `xvfb-run` when there is no `$DISPLAY`.

Per test it creates an isolated `$HOME` with a seeded `settings.json` (Lua
I/O on), sets `HUSH_ROOT`, `HUSH_OUT`, `HUSH_STATE`, and writes
`build/test-results/<test>/{stdout.txt,stderr.txt,meta.json,*.png}`. Exit code
comes from `emu.stop(code)`; a timeout or Mesen's own `-1` is TIMEOUT, which
counts as a failure. Two flags are forced for reproducibility and function:

- `--snes.ramPowerOnState=AllZeros`: default is random, which breaks cold-boot
  determinism.
- `--snes.port1.type=SnesController`: a fresh config has no controller, so
  `emu.setInput` silently did nothing.

The debugger's "Uninitialized memory read" log spam is filtered out of
`stdout.txt` (the count is kept in `meta.json`).

Script tags: `-- @requires-state` (SKIP, not FAIL, when the savestate is
missing) and `-- @timeout <sec>`. `make test STRICT=1` fails on skips.

`tests/lib/hush.lua` provides: `wait`, `hold`, `press`, `play` (input-script
files), `read` (RAM values by name, parsed from `docs/ram_map.md`), `sprite`,
`active_sprites`, `link`, `dump_ram` / `diff_dumps`, `screenshot`, `load_state`,
`save_state`, `assert` / `assert_eq` / `assert_gt`, `pass` / `fail`. Lua API
calls were checked against MesenCE 2.2.1's `LuaDocumentation.json` and source
(for example, `emu.loadSavestate` only works inside an exec callback).

### Tests

| Test | Needs state | Result now |
|---|---|---|
| `smoke/boot.lua`: boot, 600 frames, exit 0 | no | PASS |
| `smoke/read_link.lua`: hold Right 60 frames, X must increase | yes | SKIP |
| `smoke/determinism.lua`: same state + inputs twice, WRAM must match | yes | SKIP |

Self-verification without the human's state: `tests/dev/make_dev_state.lua`
plays from cold boot into Link's house and writes
`build/dev_states/linkhouse.mss`. Against that state `read_link` and
`determinism` both PASS, and a deliberately different second run makes
`determinism` FAIL with a list of differing WRAM bytes (so it can detect
differences). The harness also reports correctly for a failing assertion, a Lua
runtime error and a hang. A Lua syntax error currently shows as TIMEOUT rather
than a distinct error.

`make chaos` runs `tests/chaos/` (empty). Its README lists the five planned
fuzz targets: attack on the frame a guard turns, two guards alerting at once,
a sleeping guard woken by another's alarm, room-transition edges, dying sprites.

## 5. RAM map

`docs/ram_map.md` lists the addresses the tests need, each with a disassembly
file and line: Link X/Y (`$7E0022`/`$7E0020`), layer (`$7E00EE`), room id
(`$7E00A0`), health (`$7EF36D`, max `$7EF36C`), game mode / submodule
(`$7E0010`/`$7E0011`), and sprite arrays for type, state, X/Y (low and high),
and health. It also has value tables (sprite states, soldier type ids) and
caveats (`$7E00EE` and `$7E0022` are shared with other subsystems outside
their normal mode). The file is machine-read by `hush.lua`.

`read_link` and `determinism` run against real emulation, which confirmed the
Link X/Y, game mode and submodule rows. The sprite-array rows are not yet
exercised by any test.

## 6. Room spec system

`design/rooms/_template.yaml` has all required fields (id, status, floor,
teaches, layout, lighting, guards, tools_given, intended_solution,
solution_inputs, par_time_sec, ghost_possible, must_not). `make validate`
(`tools/validate_specs.py`) checks types, enums, id equals file name, unknown
keys, that the template matches the schema, and that a room with status
`built` has an existing `solution_inputs` file. Verified with good and bad
specs. I added a `status` field (`draft` / `specified` / `built`) beyond the
fields you listed, so "once its status is built" has something to check.

## 7. Agents and commands

Format: opencode 1.19.5 reads **V1** agent frontmatter (`permission:` map,
last matching rule wins). The public docs describe V2 (`permissions:` list),
which this version silently ignores, so V1 is used. Resolved rules were checked
with `opencode debug agent <name>`. Not yet run end to end.

| Agent | Mode | Can edit | Shell |
|---|---|---|---|
| director | primary | `docs/backlog.md` | read-only git, `make build/test/validate/check/chaos`; `git add/commit` ask |
| designer | subagent | `design/**` | read-only git, `make validate` |
| engine | subagent | `src/**`, `docs/ram_map.md` | read-only git, `make build/test/check/validate/patch/freespace`, test runner, freespace check |
| art | subagent | `gfx/**`, `tools/gfx_convert.py` | read-only git, `gfx_convert.py` |
| qa | subagent | `tests/**`, `docs/bugs.md` | read-only git, `make build/test/chaos/check/validate`, test runner |
| critic | subagent | nothing | read-only git |

All agents deny reads of `.env` / `.env.*` (except `.env.example`) and
`*.sfc` / `*.smc`. The director can launch only the five subagents. Each agent
file has a body with role, inputs, outputs, "done means" and "never".

Commands in `.opencode/commands/`: `/build`, `/test`, `/chaos` (run the make
target and report), `/gate` (director report; stops and asks the human to
approve).

Limits of enforcement: edit permissions are path-based and shell permissions are
command-pattern based, so they are guardrails, not a security boundary. The
`gfx_convert.py` colour rules, the freespace ledger and the legal rules are
enforced by tools; the agents' working rules are instructions only.

## 8. Other deliverables

- `AGENTS.md`: game summary, legal rules, 8 working rules, layout, commands,
  agent table, milestones (current: M0).
- `design/pillars.md`: five pillars, game rules, tools, art direction, MVP
  scope, difficulty-curve skeleton.
- `docs/backlog.md` (M0 done list, M1 outline), `docs/bugs.md` (template),
  `telemetry/README.md`, `tests/README.md`, `tests/chaos/README.md`.
- `tools/gfx_convert.py`: PNG to SNES 4bpp + BGR555 palette with SNES limits
  and amber/violet role rules, verified on passing and failing samples.
  No game art exists yet.
- `README.md`: setup, commands, manual steps, how to make the savestate.

## 9. Safety audit (before the commit)

- `.gitignore` covers `rom/`, `build/`, `*.sfc`, `*.smc`, `*.srm`, `*.ips`,
  `*.ups`, `.env*` (except `.env.example`), `.venv/`, `.tools/`, `vendor/`,
  `tests/states/*.mss`, and everything in `dist/` except `*.bps`.
- Staged set checked: no forbidden file names, no file over 200 KB, no blob
  with ROM size (1 MiB or 1 MiB + 512) or CRC `777AAC2F`, and no occurrence of
  the contents of `~/.sudo-pwd`. `.env.local` exists and is ignored.
- `~/.sudo-pwd` was used only for `apt-get`, and not written to the repo.

## 10. Known limitations

- `read_link` and `determinism` have never run against the human's
  `test_room.mss`; only against the generated Link's-house state.
- Savestates are tied to MesenCE 2.2.1 and to the running code; remake them
  after upgrading the emulator or moving hooks.
- `smoke_boot` only proves the ROM runs 600 frames without crashing (it stays
  on the title screen); it does not exercise gameplay.
- Header checksum is not updated (`--fix-checksum=off`); the ledger notes this
  for M5.
- A Lua syntax error in a test shows as TIMEOUT, not a clear error.
- `tools/setup.sh` was run on the already-set-up machine, so a from-scratch
  setup on a clean machine is untested.
- Agents have not been run end to end; their permission rules are only checked
  as resolved config.

## 11. Gate checklist (human)

1. `rom/vanilla.sfc` is the intended ROM (CRC `777AAC2F`).
2. `make build` and `make test` run on your machine.
3. `tests/states/test_room.mss` made (README: "Making `tests/states/test_room.mss`").
4. `make test STRICT=1` passes all three tests.
5. `/gate` run in opencode and M0 approved. Then change "Current milestone" in
   `AGENTS.md` to M1 (the director proposes this edit, it does not make it).
