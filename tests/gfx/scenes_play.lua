-- GFX scenes reached from the in-game dev state (build/dev_states/gfx_house.mss, made by
-- tests/gfx/scenes_boot.lua from THIS build) by setting save-data WRAM and pressing buttons:
-- HUD at several health values, each tool in use, pause menu, death screen.
-- RAM used (all cited in vendor/alttp-disassembly/Zelda_3_SRM.log / Zelda_3_RAM.log):
--   $7EF36C max health (SRM:341)   $7EF36D health (SRM:345)   $7EF359 sword (SRM:232)
--   $7EF340 bow (SRM:171)          $7EF377 arrows (SRM:379)   $7EF343 bombs (SRM:177)
--   $0202   selected item (RAM.log:1216)
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local gfx = require("gfx")

local function poke(addr, v) emu.write(addr - 0x7E0000, v, emu.memType.snesWorkRam) end
local function peek(addr) return emu.read(addr - 0x7E0000, emu.memType.snesWorkRam, false) end

hush.test("gfx scenes: HUD, tools, pause, death (from gfx_house state)", function()
  hush.load_state("build/dev_states/gfx_house.mss")
  hush.wait(30)
  hush.assert(hush.read("game_mode") == 0x07, "state is not in the house (module " .. hush.read("game_mode") .. ")")

  -- HUD at several health values (hearts row, half hearts, second heart row)
  for _, v in ipairs({ { 0x18, 0x18, "hud_3_full" }, { 0x18, 0x0C, "hud_3_half" }, { 0xA0, 0xA0, "hud_20_full" }, { 0x28, 0x04, "hud_low" } }) do
    poke(0x7EF36C, v[1]); poke(0x7EF36D, v[2])
    hush.wait(40); gfx.snap(v[3])
  end
  poke(0x7EF36C, 0x28); poke(0x7EF36D, 0x28); hush.wait(20)

  -- sword (Shade Knife slot): fighter sword, swing
  poke(0x7EF359, 1)
  hush.wait(10)
  hush.hold({ "b" }, 3); hush.wait(4); gfx.snap("sword_swing_a")
  hush.wait(4); gfx.snap("sword_swing_b")
  hush.wait(40)

  -- bow (Hush Dart slot): bow with arrows, select, fire
  poke(0x7EF340, 2); poke(0x7EF377, 30); poke(0x0202 + 0x7E0000, 1)
  hush.wait(20); gfx.snap("bow_selected")
  hush.press({ "y" }, 3, 1); hush.wait(6); gfx.snap("arrow_in_flight")
  hush.wait(40)

  -- bombs (Ink Pot slot): place and watch it
  poke(0x7EF343, 10); poke(0x0202 + 0x7E0000, 4)
  hush.wait(20); gfx.snap("bomb_selected")
  hush.press({ "y" }, 3, 1); hush.wait(10); gfx.snap("bomb_placed")
  hush.wait(70); gfx.snap("bomb_exploding")
  hush.wait(60)

  -- pause / item menu
  hush.press({ "start" }, 3, 1); hush.wait(90)
  gfx.snap("pause_menu")
  hush.press({ "start" }, 3, 1); hush.wait(90)

  -- death / game over
  poke(0x7EF36D, 0)
  hush.wait(240); gfx.snap("death_1")
  hush.wait(240); gfx.snap("death_menu")
  hush.pass("scenes dumped; final module " .. hush.read("game_mode"))
end)
