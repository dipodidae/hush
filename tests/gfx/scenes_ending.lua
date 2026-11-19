-- GFX scenes (E6): the ending screen (BG3 text with the dialogue font, palette groups 1 and 2) and the title shown again after it.
-- Reached from a real game: new game, debug jump to the last room, touch the exit, wait for the ending module ($13), START.
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

hush.test("gfx scenes: ending screen + title after the ending", function()
  local m = bot.rooms()
  bot.start_new_game()
  bot.jump_to_room(m.count - 1)
  hush.wait(20)
  local x, y = bot.exit_pos(m.rooms[m.count].exits[1])
  bot.teleport(x, y)
  local t = 0
  while not (hush.read("game_mode") == 0x13 and bot.peek(0x7E00B0) == 2) and t < 200 do hush.wait(1); t = t + 1 end
  hush.assert(hush.read("game_mode") == 0x13, "ending screen not reached")
  hush.wait(70)          -- PRESS START visible (blink: bit 5 of the frame count)
  gfx.snap("ending_screen")
  hush.wait(40)          -- PRESS START in its dark phase
  hush.press({ "start" }, 3, 1)
  t = 0
  while not (hush.read("game_mode") == 0x00 and hush.read("submodule") == 0x08) and t < 900 do hush.wait(1); t = t + 1 end
  hush.assert(hush.read("game_mode") == 0x00, "title not reached")
  hush.wait(60)
  gfx.snap("title_after_ending")
  hush.pass("ending scenes dumped")
end)
