-- tools/art/hud_snap.lua : HUD screenshots + VRAM/CGRAM dumps in the HUSH rooms, per tool stage (research/QA helper for docs/gfx/hud_map.md)
--   .venv/bin/python tools/run_test.py tools/art/hud_snap.lua      (output: build/test-results/tools_art_hud_snap or hud_snap)
-- room 0 (no tools), room 2 (knife), room 6 (+darts), room 9 (+ink pots); in the last room each item slot is selected.
-- $0202 = HUD slot, $0303 = equipped item (docs/engine_notes.md section 11: both must be poked; HUD rebuilds on the next frames)
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

hush.test("hud snaps", function()
  bot.start_new_game()
  for _, e in ipairs({ { 0, "hud_r01_none" }, { 2, "hud_r03_knife" }, { 6, "hud_r07_darts" }, { 9, "hud_r10_ink" } }) do
    bot.jump_to_room(e[1])
    hush.wait(60)
    gfx.snap(e[2])
  end
  -- room 10 (all tools): select the bow (slot 1, item 3) and bombs (slot 4, item 1)
  bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3); hush.wait(30); gfx.snap("hud_r10_sel_darts")
  bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1); hush.wait(30); gfx.snap("hud_r10_sel_ink")
  -- low health stages (hearts: full / half / empty); 3 hearts = $18
  bot.poke(0x7EF36D, 0x0C); hush.wait(1); gfx.snap("hud_hp_half")
  bot.poke(0x7EF36D, 0x18); hush.wait(5)
  -- vanilla item menu (START): which BG3 cells does it use? (it shares the HUD sheets)
  hush.press({ "start" }, 3, 1); hush.wait(120); gfx.snap("hud_menu")
  hush.pass("hud snaps done")
end)
