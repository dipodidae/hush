-- tools/art/hud_snap.lua : HUD screenshots + VRAM/CGRAM dumps in the HUSH rooms, per tool stage (docs/gfx/hud_map.md)
--   HUSH_RESULTS=build/art_research/hud .venv/bin/python tools/run_test.py tools/art/hud_snap.lua
-- room 1 (no tools), room 3 (knife), room 7 (+darts), room 10 (+ink pots, both selected in turn), then 2 showcase shots
-- (12 darts, 7 ink pots, 2.5 hearts) and the START menu. $0202 = selected HUD slot (R cycles it); the HUD rebuilds on the next frames.
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
  -- room 10 (all tools): ink pots need a count to be selectable; select by poking the slot, then START twice
  -- (closing the item menu runs RebuildHUD, bank_0D.asm:13544)
  local function select_slot(slot, equip)
    bot.poke(0x7E0202, slot); bot.poke(0x7E0303, equip)
    hush.press({ "start" }, 3, 40)   -- open the item menu
    hush.press({ "start" }, 3, 60)   -- close it: HUD rebuilt with the selected item
    hush.log(string.format("slot $0202=%d equipped $0303=%d mode=%02X", bot.peek(0x7E0202), bot.peek(0x7E0303), hush.read("game_mode")))
  end
  bot.poke(0x7EF343, 3)
  select_slot(4, 1); gfx.snap("hud_r10_sel_ink")
  select_slot(1, 3); gfx.snap("hud_r10_sel_darts")
  -- showcase: counters and health (12 darts, 7 ink pots, 120 loot, 2.5 hearts)
  bot.poke(0x7EF377, 12); bot.poke(0x7EF343, 7); bot.poke(0x7EF362, 120)
  select_slot(4, 1); gfx.snap("hud_full_ink")
  select_slot(1, 3); gfx.snap("hud_full_darts")
  -- health stages: the room controller refills health every frame, so write the heart words of the HUD buffer ($7EC768...)
  -- directly (tile $A0 full, $A1 half, $A2 empty, palette 1, priority; bank_0D.asm:16995 HeartTiles) and let the NMI upload them
  local function hearts(a, b, c)
    for try = 1, 30 do   -- retry until the PPU shows these tiles for two frames in a row (the controller rewrites the buffer each frame)
      local streak = 0
      for k = 1, 3 do
        for i, t in ipairs({ a, b, c }) do
          bot.poke(0x7EC768 + 2 * (i - 1), t); bot.poke(0x7EC769 + 2 * (i - 1), 0x24)
        end
        bot.poke(0x7E0016, 1); hush.wait(1)
        local ok = true
        for i, t in ipairs({ a, b, c }) do
          if emu.read(0xC000 + (3 * 32 + 20 + i - 1) * 2, emu.memType.snesVideoRam, false) ~= t then ok = false end
        end
        if ok then streak = streak + 1 end
      end
      if streak >= 2 then return end
    end
    hush.log("hearts: could not show the requested tiles")
  end
  hearts(0xA0, 0xA0, 0xA1); gfx.snap("hud_hearts_2h")
  hearts(0xA0, 0xA1, 0xA2); gfx.snap("hud_hearts_full_half_empty")
  hearts(0xA1, 0xA2, 0xA2); gfx.snap("hud_hearts_half")
  hearts(0xA3, 0xA4, 0xA3); gfx.snap("hud_hearts_anim")
  bot.poke(0x7EF36D, 0x18); hush.wait(5)
  hush.press({ "start" }, 3, 1); hush.wait(120); gfx.snap("hud_menu")
  hush.pass("hud snaps done")
end)
