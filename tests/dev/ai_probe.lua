-- Dev utility (not a test): put Link in front of the first guard of the first room and log awareness over time.
--   .venv/bin/python tools/run_test.py tests/dev/ai_probe.lua
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("ai probe", function()
  bot.start_new_game()
  hush.wait(20)
  local g = bot.rooms().rooms[1].guards[1]
  local slot
  for s = 0, 15 do if hush.read("spr_type", s) == 0x41 and hush.read("spr_state", s) == 9 then slot = s end end
  bot.teleport(g.x, g.y - 8 + 48)       -- 48 px in front of a guard that faces down
  for f = 0, 420, 6 do
    local sp = hush.sprite(slot)
    hush.log(string.format("+%3d state=%d dir=%d g=(%d,%d) link=(%d,%d) t=%d/%d caught=%d flash=%d", f, bot.peek(0x7E0D80 + slot), bot.peek(0x7E0DE0 + slot), sp.x, sp.y,
      hush.read("link_x"), hush.read("link_y"), bot.peek(0x7E0DF0 + slot), bot.peek(0x7E0E10 + slot), bot.peek(0x7EC902), bot.peek(0x7EC903)))
    if f == 90 then hush.screenshot("alert") end
    hush.wait(6)
  end
  hush.pass()
end)
