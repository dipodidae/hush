# Tests

Run everything: `make test`. Single script: `.venv/bin/python tools/run_test.py <script.lua> [--state file.mss]`.

| Dir | What | Needs savestate? |
|---|---|---|
| `smoke/` | boot, RAM reads, determinism | `boot` no; the others yes |
| `solutions/` | one replay per room: plays `solution_inputs` and asserts the room is cleared | yes (per room) |
| `chaos/` | seeded fuzzing (see its README) | yes |
| `lib/hush.lua` | shared helpers | - |
| `states/` | savestates you create by hand (gitignored) | - |
| `dev/` | utilities, not tests (`make_dev_state.lua`) | no |

Scripts tagged `-- @requires-state` are **skipped** (not failed) when
`tests/states/test_room.mss` is missing. `make test STRICT=1` fails on skips.
Header tags: `-- @requires-state`, `-- @timeout <sec>`.

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
