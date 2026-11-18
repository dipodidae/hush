-- Dev utility (NOT a test; not run by `make test`):
-- Plays the vanilla/hacked ROM from cold boot through name entry into Link's
-- house, waits for player control, and saves build/dev_states/linkhouse.mss.
-- Used to self-verify the harness (read_link, determinism) without the
-- hand-made tests/states/test_room.mss.
--   .venv/bin/python tools/run_test.py tests/dev/make_dev_state.lua
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local function tap(b, n) for _ = 1, (n or 1) do hush.press(b, 4, 8) end end

hush.test("make_dev_state: boot -> Link's house", function()
  hush.wait(900)
  tap({ "start" }); hush.wait(120)          -- title -> player select
  tap({ "start" }); hush.wait(120)          -- empty slot -> register name
  tap({ "a" }, 2);  hush.wait(20)           -- type one letter
  tap({ "start" }); hush.wait(120)          -- confirm name
  tap({ "a" });     hush.wait(60)           -- select slot 1 -> game loads
  -- skip intro text until Link has been controllable (dungeon module 0x07,
  -- submodule 0, no text box) for ~3 seconds straight
  local tries, stable = 0, 0
  while stable < 6 do
    if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0x00 then
      stable = stable + 1
    else
      stable = 0
      hush.press({ "a" }, 4, 8)
    end
    hush.wait(30)
    tries = tries + 1
    hush.assert(tries < 400, "never reached stable gameplay; mode=" .. hush.read("game_mode"))
  end
  hush.wait(600)                            -- Link gets out of bed / Uncle leaves
  hush.screenshot("devstate")
  hush.log(string.format("room=$%04X link=(%d,%d) mode=%02X sub=%02X",
    hush.read("room_id"), hush.read("link_x"), hush.read("link_y"), hush.read("game_mode"), hush.read("submodule")))
  os.execute("mkdir -p '" .. hush.ROOT .. "/build/dev_states'")
  hush.save_state("build/dev_states/linkhouse.mss")
  hush.pass("saved build/dev_states/linkhouse.mss")
end)
