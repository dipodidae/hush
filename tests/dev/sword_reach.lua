-- Dev utility (not a test): sword reach sweep. For each dx (Link left of an unaware guard that faces east, Link facing east, B pressed)
-- log the frame the guard dies. Result (E2): dx -32 .. -16 hit (died at frame 2-3), -36 and farther miss, -12 is a contact (alert).
--   .venv/bin/python tools/run_test.py tests/dev/sword_reach.lua
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
hush.test("sword reach", function()
  ai.enter("ai4_dark")
  for _, dx in ipairs({ -60, -50, -44, -40, -36, -32, -30, -28, -26, -24, -22, -20, -18, -16, -12 }) do
    ai.link_to(0, dx, 0)
    bot.poke(0x7E002F, 6)
    hush.wait(1)
    hush.hold({ "b" }, 2)
    local died = ai.watch(14, function() return not ai.alive(0) end)
    hush.log(string.format("dx=%d died_at=%s", dx, tostring(died)))
    ai.restart(); hush.wait(10); bot.wait_control()
  end
  hush.pass()
end)
