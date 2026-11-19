-- tools/art/menu_snap.lua : START item menu (+ select/save screens) screenshots with VRAM/CGRAM dumps (docs/gfx/hud_map.md section 7)
--   HUSH_RESULTS=build/art_research/menu .venv/bin/python tools/run_test.py tools/art/menu_snap.lua
-- room 10 (all tools), darts + ink pots + knife given, START opens the item menu; menu_* snapshots at several cursor slots,
-- then the SELECT save-and-continue screen and the game-over menu.
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

hush.test("menu snaps", function()
  bot.start_new_game()
  bot.jump_to_room(9)
  hush.wait(60)
  bot.poke(0x7EF359, 1)    -- sword (Shade Knife)
  bot.poke(0x7EF340, 2)    -- bow (Hush Darts)
  bot.poke(0x7EF377, 12)   -- darts
  bot.poke(0x7EF343, 7)    -- bombs (Ink pots)
  bot.poke(0x7EF362, 120)
  hush.wait(10)
  hush.press({ "start" }, 3, 1)
  hush.wait(90); gfx.snap("menu_open")
  for i = 1, 8 do hush.wait(5); gfx.snap("menu_flick" .. i) end   -- cursor flickers (bit 4 of $0207)
  for i = 1, 3 do hush.press({ "right" }, 3, 1); hush.wait(6) end   -- cursor on slot 4 = the bombs (Ink Pots)
  for i = 1, 8 do hush.wait(4); gfx.snap("menu_ink" .. i) end
  hush.press({ "down" }, 3, 1); hush.wait(20); gfx.snap("menu_down")   -- an empty slot (nothing there: the name row clears)
  for i = 1, 3 do hush.press({ "left" }, 3, 1); hush.wait(6) end
  hush.press({ "up" }, 3, 1); hush.wait(20); gfx.snap("menu_left")
  bot.poke(0x7EF377, 0); hush.press({ "right" }, 3, 1); hush.press({ "left" }, 3, 1); hush.wait(10)
  gfx.snap("menu_noarrows")   -- bow without arrows: the shorter name row
  bot.poke(0x7EF377, 12)
  hush.press({ "start" }, 3, 1); hush.wait(90)
  -- SELECT = save and continue screen (vanilla)
  hush.press({ "select" }, 3, 1); hush.wait(120); gfx.snap("menu_select")
  hush.pass("menu snaps done")
end)
