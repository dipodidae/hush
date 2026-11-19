# Tests

Run everything: `make test`. Single script: `.venv/bin/python tools/run_test.py <script.lua> [--state file.mss]`.

| Dir | What | Needs savestate? |
|---|---|---|
| `smoke/` | boot, new game, room advance/restart/ending, every room loads, walk to the exit, guard facing (E1); `visual_tiles.lua` (E3: tilemap/VRAM tile ids per cell kind, `$7F2000` = grid, palette sets, OBJ palettes identical); **`ai_*.lua` (E2): vision, line of sight, sword, darts, ink pots, caught -> restart, awareness timers, patrol, real-input stealth** (they run on the dev ROM, `-- @rom dev`); **`guard_draw.lua` (E4): the custom guard drawing against the GFX_BC sheet contract (tiles, flips, positions, palette, 5 OAM entries, lantern flicker, culling window; real ROM, build/hush.sym)**; RAM reads and determinism | only `read_link` and `determinism` |
| `solutions/` | **`all_rooms.lua`: every one of the 21 rooms played from its recorded `<id>.inputs` on the real ROM (post-new-game state + debug jump per room): exit reached, hush_room advanced (final: back to the title), Link never caught; `must_not.lua`: the specs' `must_not` lines as tests**; regenerate with `tools/solve_rooms.py` (see `solutions/README.md`) | no |
| `gfx/` | scripted scenes that dump VRAM/CGRAM for `make leakcheck` (`tests/lib/gfx.lua`) | no (made from this build) |
| `chaos/` | seeded fuzzing (see its README) | yes |
| `lib/hush.lua` (also `snapshot()` / `restore()`: in-memory savestates), `lib/bot.lua` (also `jump_to_room_synced`), `lib/ai.lua` | shared helpers; `bot` = new game, `walk_to(px,py)`, BFS `walk_exit`, `jump_to_room`, `teleport`, room metadata from `build/rooms_gen.lua` (or `build/dev/rooms_gen.lua` for dev-ROM tests: `HUSH_ROOMS_LUA`); `ai` = E2 helpers (`enter(room id)`, `state(slot)`, `link_to(slot, dx, dy)`, `restart()`) | - |
| `states/` | savestates you create by hand (gitignored) | - |
| `dev/` | utilities, not tests (`record_room.lua` and `trace_room.lua` = the solution recorder / per-frame tracer driven by `tools/solve_rooms.py`, `ram_at_room_start.lua`, `make_dev_state.lua`, `dump_collision.lua`, `room_load_timing.lua`, `guard_behaviour.lua` (vanilla AI, E1), `cpu_load.lua` (scanline where the logic ends), `guard_cost.lua` (CPU cycles per guard per frame, draw and AI; E4), `oam_probe.lua` (visible OAM entries of a room; E4), `sword_reach.lua`, `ai_probe.lua`, `probe_gfx.lua`) and `dev/rooms/*.yaml`, the engine dev room set: compiled into the **dev ROM** `build/hush_dev.sfc` (`make build-dev`, run by `make test`) and used as the main ROM's rooms while `design/rooms` has no rooms or with `HUSH_ROOMS_DIR=tests/dev/rooms` | no |

Scripts tagged `-- @requires-state` are **skipped** (not failed) when
`tests/states/test_room.mss` is missing. `make test STRICT=1` fails on skips.
Header tags: `-- @requires-state`, `-- @timeout <sec>`, **`-- @rom dev`** (run on `build/hush_dev.sfc`: the same code and graphics but the rooms of `tests/dev/rooms`, so the test does not depend on what `design/rooms` contains; `bot.rooms()` then returns the dev rooms).

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
