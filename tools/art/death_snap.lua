-- tools/art/death_snap.lua : the vanilla game-over menu (module $12) for the legibility check (docs/gfx/hud_map.md section 7)
--   HUSH_RESULTS=build/art_research/menu .venv/bin/python tools/run_test.py tools/art/death_snap.lua
-- Link cannot die in HUSH (the room controller refills health every frame), so the health byte is zeroed after the controller ran.
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

hush.test("death snaps", function()
  bot.start_new_game()
  bot.jump_to_room(9)
  hush.wait(60)
  -- the dying sequence is module $12 (death) submodule 0; set it directly after zeroing health (the controller refills health in module 7 only)
  bot.poke(0x7EF36D, 0)
  bot.poke(0x7E0010, 0x12); bot.poke(0x7E0011, 0x00)
  hush.log("module " .. string.format("%02X", hush.read("game_mode")))
  hush.wait(200); gfx.snap("death_a")
  hush.wait(200); gfx.snap("death_b")
  hush.press({ "down" }, 3, 1); hush.wait(20); gfx.snap("death_c")
  hush.pass("death snaps done")
end)
