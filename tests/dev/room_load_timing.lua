-- Dev utility (not a test): frame timeline (module / submodule / brightness) of a room load.
--   .venv/bin/python tools/run_test.py tests/dev/room_load_timing.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("probe timing", function()
  bot.start_new_game()
  bot.poke(0x7EC901, 2)
  local last = ""
  for f = 0, 260 do
    local s = string.format("mode=%02X sub=%02X bright=%02X", hush.read("game_mode"), hush.read("submodule"), bot.peek(0x7E0013))
    if s ~= last then hush.log(string.format("+%3d %s", f, s)); last = s end
    hush.wait(1)
  end
  hush.pass()
end)
