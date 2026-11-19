-- Research probe: does a ceiling cell hide Link? (docs/gfx/art_map.md 3.2)  Link is put on the top free row of room 11 and screenshotted.
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("priority probe", function()
  bot.start_new_game()
  bot.jump_to_room(10)
  hush.wait(40)
  local m = bot.rooms()
  local rm = m.rooms[11]
  for s = 0, 15 do bot.poke(0x7E0DD0 + s, 0) end
  bot.teleport(rm.base_x + m.win_x + 5 * 16, rm.base_y + m.win_y + 2 * 16 - 8)
  hush.wait(6)
  hush.hold({ "up" }, 20)
  hush.wait(6)
  hush.screenshot("link_at_top_wall")
  hush.pass()
end)
