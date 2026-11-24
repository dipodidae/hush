# Tests

Run everything: `make test`. Single script: `.venv/bin/python tools/run_test.py <script.lua> [--state file.mss]`.

| Dir | What | Needs savestate? |
|---|---|---|
| `smoke/` | boot, new game, room advance/restart/ending, every room loads, walk to the exit, guard facing (E1); `visual_tiles.lua` (E3: tilemap/VRAM tile ids per cell kind, `$7F2000` = grid, palette sets, OBJ palettes identical); **`ai_*.lua` (E2): vision, line of sight, sword, darts, ink pots, caught -> restart, awareness timers, patrol, real-input stealth** (they run on the dev ROM, `-- @rom dev`); **`guard_draw.lua` (E4): the custom guard drawing against the GFX_BC sheet contract (tiles, flips, positions, palette, 5 OAM entries, lantern flicker, culling window; real ROM, build/hush.sym)**; RAM reads and determinism; **`mustnot2.lua` (QA bug hunt, real ROM, ~50 s): the adversarial must_nots - knife / dart through one-cell walls (cases computed from the room grids), pillar, sleeping guard blocking a corridor, hiding spots and sight lines named in the specs, ink cloud timing, exit cells, tool gating, SELECT; known bugs are listed in `KNOWN` / per case with their `docs/bugs.md` id and reported as XFAIL (a known case that passes is an XPASS and fails the test)**; **E6 game feel: `transition.lua` (exit -> next room in <= 45 frames, measured 23; fast load == full load: VRAM / CGRAM / tile buffers / collision identical), `feedback.lua` (the SFX ids on the APU ports for ? ! knife dart caught, the caught flash registers), `music.lua` (a song per floor started once, the SPC echo), `hud.lua` (no gem counter, ink / dart counters follow the tools), `ending.lua` (ending screen text read back from VRAM, stats, START -> title -> new game, SELECT does nothing), `ink_palette.lua` (teal specks)**; **stealth meter (design/pillars.md:42-122; dev ROM): `meter_refill` (crit 1), `meter_hits` (2, 3), `meter_contact` (4), `meter_cooldown` (5; exact boundary: +120 blocked, +121 allowed, small and big, B-007), `meter_two_guards` (6), `meter_empty` (7), `meter_caught_wins` (8), `meter_hud` (10: HUD buffer `$7EC768` cells compared with each other, no tile ids), `meter_nohit` (11); helpers in `lib/meter.lua`** | only `read_link` and `determinism` |
| `solutions/` | **`all_rooms.lua`: every one of the 21 rooms played from its recorded `<id>.inputs` on the real ROM (post-new-game state + debug jump per room): exit reached, hush_room advanced (final: the ending screen, E6), Link never caught, health == max every gameplay frame and no game-over module (meter crit 9); `meter_budget.lua`: the same replays with the meter budget (pillars.md:204: <= 2 small hits, no big hit, and exactly 1 "?" in r05 / 0 in every other room (final exits with 32), counted from awareness transitions with the spec's table + cooldown) and the engine's meter compared with it; `must_not.lua`: the specs' `must_not` lines as tests**; regenerate with `tools/solve_rooms.py` (see `solutions/README.md`) | no |
| `gfx/` | scripted scenes that dump VRAM/CGRAM for `make leakcheck` (`tests/lib/gfx.lua`; E6: `scenes_ending.lua` = the ending screen and the title after it) | no (made from this build) |
| `chaos/` | **seeded fuzz (README in the dir)**: `chaos_mash` (random buttons, 22 seeds), `chaos_menu` (item-menu mashing, never stuck), `chaos_churn` (50 room jumps + 50 caught-restarts, no leaks, bounded frame counts), `chaos_spam` (pot / dart spam), `chaos_determinism` (same seed twice = identical WRAM), `chaos_edge` (frame-offset races); invariants checked every frame by `chaos/lib/chaos.lua`; a failing seed writes `chaos/repros/<scenario>_<seed>.inputs`, replayed by `dev/chaos_replay.lua` (`make chaos`, ~4.5 min) | no |
| `lib/hush.lua` (also `snapshot()` / `restore()`: in-memory savestates), `lib/bot.lua` (also `jump_to_room_synced`), `lib/ai.lua` | shared helpers; `bot` = new game, `walk_to(px,py)`, BFS `walk_exit`, `jump_to_room`, `teleport`, room metadata from `build/rooms_gen.lua` (or `build/dev/rooms_gen.lua` for dev-ROM tests: `HUSH_ROOMS_LUA`); `ai` = E2 helpers (`enter(room id)`, `state(slot)`, `link_to(slot, dx, dy)`, `restart()`) | - |
| `states/` | savestates you create by hand (gitignored) | - |
| `dev/` | utilities, not tests (E6: `room_load_profile.lua` = frames per room-load step, `fastload_diff.lua` = fast vs full load diff (+ dumps for a cross-ROM compare with `HUSH_ROM`), `phase_probe.lua` = the `$1A` phase at the first AI pass (keeps the replays valid), `flash_probe.lua`, `ending_probe.lua`, `title_diff.lua`, `hud_probe.lua`, `menu_vram.lua` (does the item menu leave VRAM intact? it does: the fast load relies on it); **`chaos_replay.lua` = replay of a chaos repro / bug repro file with the invariants: `HUSH_REPLAY=tests/chaos/repros/<file> .venv/bin/python tools/run_test.py tests/dev/chaos_replay.lua`**, `record_room.lua` and `trace_room.lua` = the solution recorder / per-frame tracer driven by `tools/solve_rooms.py`, **`record_final.lua` (record_room with fixed paths, plan `dev/plans/final_qa.plan`), `final_probe.lua` (replay + every awareness transition with slot -> spec letter and cells; `b008_probe.lua` = the same on the B-008 repro; `final_top_probe.lua` = final room, who sees Link at col 8 per Link y 9928-9946 and AI phase: the B-009 repro)**, `ram_at_room_start.lua`, `make_dev_state.lua`, `dump_collision.lua`, `room_load_timing.lua`, `guard_behaviour.lua` (vanilla AI, E1), `cpu_load.lua` (scanline where the logic ends), `guard_cost.lua` (CPU cycles per guard per frame, draw and AI; E4), `oam_probe.lua` (visible OAM entries of a room; E4), `sword_reach.lua`, `meter_hits_phase.lua` (smoke/meter_hits at every `$1A` start phase: a flake check), `ai_probe.lua`, `probe_gfx.lua`) and `dev/rooms/*.yaml`, the engine dev room set: compiled into the **dev ROM** `build/hush_dev.sfc` (`make build-dev`, run by `make test`) and used as the main ROM's rooms while `design/rooms` has no rooms or with `HUSH_ROOMS_DIR=tests/dev/rooms` | no |

`HUSH_ROM=/path/to/hush.sfc` runs a suite / script against another ROM (the runner's override), e.g. a clean build of `HEAD` in a `git worktree` while the working tree is in flux.

**Unit (Python, `tests/unit/`; `make test` runs `test_autotile.py`, whose `main()` also runs the others):** `test_autotile.py` (T0 autotile oracle), `test_depth.py` (design/tiles.md 2.1 depth rule: bit 13 per quarter over all rooms + the gallery + random grids), `test_light_tiles.py` (design/lighting.md 4: every stored light tile = the 4.2 bilinear + Bayer formula, step-1 visibility, every reachable corner tuple resolves, and the `light_lut` corner LUTs follow the 4.5 item 4 substitute rule; needs the engine export named in its docstring).
**Depth / smooth light in the emulator:** `smoke/visual_tiles.lua` + `smoke/visual_gallery.lua` also check the priority bit against the grid rule; `smoke/depth_oam.lua` (Link / guard bodies OAM priority 2, "?" / "!" priority 3; `dev/depth_oam_probe.lua` lists the entries); `smoke/guard_draw.lua` checks the same priorities per draw call; `smoke/lighting.lua` (lighting.md rev 4, section 5) waits for `light_done` = 1 after each walk leg (bound 120 frames, max reported per room; `dev/b010_light_done.lua` = the B-010 probe) and then checks every BG1 tile word against `light.lut_amber` (undisplaced 4.1 lattice) / `light.lut_violet` (4.5 displaced glow lattice, carrier 8's rendered d) in `build/rooms_gen.lua` (format in its header).
`MUST_NOT:` lines of `smoke/mustnot2.lua` (`mn2 <family> <case>`) and `solutions/must_not.lua` appear in the runner's per-case report.

Scripts tagged `-- @requires-state` are **skipped** (not failed) when
`tests/states/test_room.mss` is missing. `make test STRICT=1` fails on skips.
Header tags (read from the **first 20 lines** only): `-- @requires-state`, `-- @timeout <sec>`, **`-- @rom dev`** (run on `build/hush_dev.sfc`: the same code and graphics but the rooms of `tests/dev/rooms`, so the test does not depend on what `design/rooms` contains; `bot.rooms()` then returns the dev rooms).

## Writing a test

```lua
-- @requires-state
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

hush.test("name", function()
  hush.hold({"right"}, 60)          -- hold buttons for N frames
  hush.press({"b"})                 -- tap
  hush.wait(30)                     -- N frames
  hush.play("tests/solutions/room01.inputs")
  local x = hush.read("link_x")     -- names come from docs/ram_map.md
  local t = hush.read("spr_type", 3)  -- 16-slot arrays take a slot index
  hush.screenshot("after")
  hush.assert_gt(x, 0, "message shown on failure")
  hush.pass()
end)
```

Every test body must end with `hush.pass()` or `hush.fail(msg)`; an assertion
failure fails the test with its message.

## Input script format (`hush.play`, `tests/solutions/*.inputs`)

```
# frames  buttons (joined with +)   comment
30  right
10  right+b
5   -            # idle
```

Buttons: `a b x y l r start select up down left right`.

## What the harness guarantees

- Fresh isolated MesenCE settings dir per test; settings never saved.
- Cold boots use `ramPowerOnState=AllZeros` (reproducible); player 1 is a SNES
  pad (a fresh config has no controller, so `emu.setInput` would do nothing).
- Lua `io`/`os` are enabled (screenshots, input files, RAM dumps).
- Results: `build/test-results/<suite>_<name>/{stdout.txt,stderr.txt,meta.json,*.png}`.
- Savestates are tied to the MesenCE version in `tools/setup.sh` (2.2.1);
  newer-version states are rejected by older emulators. Remake them if the
  emulator is upgraded or if hooks move code that was executing when you saved.
