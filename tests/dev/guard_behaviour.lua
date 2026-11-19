-- Dev utility (not a test): vanilla guard AI state ($0D80), direction ($0DE0) and position over 900 frames in room 1.
--   .venv/bin/python tools/run_test.py tests/dev/guard_behaviour.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("probe guard", function()
  bot.start_new_game()
  for f = 0, 900, 30 do
    for s = 0, 15 do
      local t = hush.read("spr_type", s)
      if t == 0x41 and hush.read("spr_state", s) == 9 then
        local sp = hush.sprite(s)
        hush.log(string.format("+%3d slot%d x=%d y=%d ai=%d dir=%d sub=%d hp=%d", f, s, sp.x % 512 - 128, sp.y % 512 - 144, bot.peek(0x7E0D80 + s), bot.peek(0x7E0DE0 + s), bot.peek(0x7E0E30 + s), sp.health))
      end
    end
    hush.wait(30)
  end
  hush.pass()
end)
