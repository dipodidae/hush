# HUSH - project rules (read this first)

HUSH is a ROM hack of **The Legend of Zelda: A Link to the Past (SNES, US 1.0)**,
built with asar (65816 assembly), tested headless in MesenCE with Lua, shipped
as a BPS patch. Humans approve every milestone gate.

## The game

You play a shadow thief infiltrating a vault tower guarded by
lantern-carrying guards. No overworld: ~20 single-screen stealth-puzzle rooms
across 3 floors, plus a final heist room.

- **Core rule:** weapons are made of shadow and melt in lantern light.
  **Unaware** guards can be taken down; **alerted** guards (lantern unhooded,
  sprite turns amber) cannot be hurt at all.
- **Tools:** Shade Knife (sword slot, melee, permanent takedown of an unaware
  guard), Hush Darts (bow slot, ranged, ~8 s sleep on an unaware guard), Ink Pots
  (bomb slot, darkness cloud that makes alerted guards lose you).
- **Guard states:** Unaware (no icon) -> Suspicious ("?", turns and
  investigates) -> Alert ("!", amber, charges). Caught = instant room restart.
  Alerted guards return to patrol after losing sight of you.
- Lit rooms increase guard detection range.
- **Art:** deep indigo + warm amber; the player and their tools are faint
  violet. **Amber = danger, violet = you.**
- **Planned custom ASM:** (1) 3-state awareness per guard built on vanilla
  soldier detection, with a de-alert timer; (2) conditional damage on sword/arrow
  hit based on awareness; (3) caught -> instant room restart; (4) lit rooms
  increase detection range (later).

Full design: `design/pillars.md`. Room specs: `design/rooms/*.yaml`
(template: `design/rooms/_template.yaml`).

## Legal / safety rules (non-negotiable)

- The vanilla ROM is supplied by the human at `rom/vanilla.sfc`. It is
  **never committed, copied into `dist/`, or uploaded anywhere.** `rom/`,
  `build/` and `*.sfc` / `*.smc` are gitignored. Never `git add -f` them.
- Verify the ROM: headerless, 1 MiB, CRC32 `777AAC2F`. If it has a 512-byte
  copier header, tell the human; **never silently strip it**.
- The **only distributable output is a BPS patch** in `dist/` (`make patch`).
- Never download ROMs or copyrighted assets from anywhere. Do not paste ROM
  data into docs beyond the few bytes of a replaced instruction in a hook header.
- Secrets live in `.env.local` (gitignored). Never commit credentials.
- `vendor/` (reference disassemblies) is read-only and gitignored.

## Working rules

1. **Every change must pass `make build` and `make test` before it is done.**
   (`make check` runs build + validate + test.) Report the actual output.
2. **Specs change before code, never the other way around.** If behaviour
   needs to change, the spec (`design/`) changes first, then tests, then code.
3. **Never make a failing test pass by editing the test unless the spec
   changed.** A failing test is information; fix the code or escalate.
4. **Every ASM hook documents its address and the vanilla code it replaces**
   (header comment format in `src/hooks/README.md`).
5. **ROM space is allocated only through `src/FREESPACE.md`.** Every `org` and
   every changed ROM byte must be inside a listed region; `freecode`/`freedata`
   are banned. `tools/check_freespace.py` enforces it.
6. **Small diffs; one feature per change.**
7. **Never guess** a RAM address, ROM address, CLI flag or file format. Look it
   up in `docs/ram_map.md`, `vendor/` (cite file:line), or the tool docs.
8. Stay at MVP scope. If an idea is not in `design/pillars.md`, it needs the
   director and a human decision first.

## Layout

```
AGENTS.md  README.md  Makefile
src/main.asm  src/hooks/  src/FREESPACE.md      engine agent only
design/pillars.md  design/rooms/                designer only
gfx/src  gfx/build  tools/gfx_convert.py        art agent only
tests/ (lib, smoke, solutions, chaos, states)   qa agent only
docs/ram_map.md  docs/backlog.md  docs/bugs.md  RAM map (cited) / director / qa
tools/  (build, run_test, validate_specs, check_freespace, gfx_convert, setup)
telemetry/   logs from human playtests (read by designer)
rom/ build/ vendor/ .tools/ .venv/              gitignored
dist/                                           BPS output only
```

## Commands

| Command | Does |
|---|---|
| `make setup` | install local tools (asar, flips, MesenCE) into `.tools/`, venv into `.venv/` |
| `make build` | verify ROM CRC, copy to `build/hush.sfc`, assemble `src/main.asm`; fails on any asar warning; checks the freespace ledger |
| `make patch` | build, then `dist/hush.bps` via flips |
| `make validate` | check `design/rooms/*.yaml` against the schema |
| `make test` | smoke + solution tests, headless; prints a pass/fail table |
| `make chaos` | fuzz tests in `tests/chaos/` |
| `make check` | build + validate + test |

Tests that need a savestate are skipped (not failed) until the human creates
`tests/states/test_room.mss`; `make test STRICT=1` fails on skips.

## Agents (`.opencode/agents/`)

| Agent | Mode | Owns | Edits |
|---|---|---|---|
| `director` | primary | plan, backlog, gates, scope | `docs/backlog.md` |
| `designer` | subagent | pillars, room specs, difficulty curve | `design/` |
| `engine` | subagent | all ASM, ROM space ledger | `src/` (+ `docs/ram_map.md` rows) |
| `art` | subagent | graphics conversion, colour rules | `gfx/`, `tools/gfx_convert.py` |
| `qa` | subagent | tests, replays, chaos, bug reports | `tests/`, `docs/bugs.md` |
| `critic` | subagent | read-only review vs pillars and specs | nothing |

Commands: `/build`, `/test`, `/chaos`, `/gate` (`.opencode/commands/`).

## Milestones

Each milestone ends at a **gate where a human must approve** before the next
starts. The director stops and asks at every gate.

| M | Scope | Gate |
|---|---|---|
| **M0** | Harness: toolchain, scaffold, build pipeline, headless tests, agents | Human confirms the ROM verifies, `make build`/`make test` run, and has made `tests/states/test_room.mss` |
| **M1** | One test room with one guard and the Shade Knife | Human fun check: is one guard + knife fun for 10 minutes? |
| **M2** | Five teaching rooms | Human plays all five; curve and readability OK |
| **M3** | Art: guards, tools, awareness icons, palette | Human reviews in-emulator; colour rules pass |
| **M4** | Full tower (~20 rooms + heist room) + chaos suite | Human playthrough; chaos suite green |
| **M5** | Instant respawn, polish, BPS release | Human approves `dist/hush.bps` |

Current milestone: **M0** (done when the human approves its gate).
