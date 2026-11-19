-- Dev utility (E7): the pause menu hides the room (TM = BG3 only), the pendant flags follow the floor, the text box interior.
-- Jumps to r10 (floor 1) and to the first floor-2 / floor-3 rooms, opens the menu with START, logs TM ($212C as the PPU has it), $7EF374,
-- takes screenshots (build/test-results/dev_menu_probe/*.png), closes the menu (TM must be the room's again).
--   .venv/bin/python tools/run_test.py tests/dev/menu_probe.lua
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local function tm() return emu.read(0x00212C, emu.memType.snesMemory, false) end   -- (write-only register: use the PPU state instead)
local function ppu_tm()
  local st = emu.getState()
  return st["ppu.mainScreenLayers"] or st["ppu.layers.main"] or -1
end

hush.test("menu probe", function()
  bot.start_new_game()
  local rooms = bot.rooms().rooms
  local picks = {}
  for i, r in ipairs(rooms) do if not picks[r.floor] then picks[r.floor] = i - 1 end end
  for floor = 1, 3 do
    local idx = picks[floor]
    if idx then
      bot.jump_to_room(idx)
      hush.wait(60)
      local flags = bot.peek(0x7EF374)
      local before = ppu_tm()
      hush.press({ "start" }, 3, 1)
      hush.wait(60)
      local open = ppu_tm()
      hush.screenshot("menu_floor" .. floor)
      local mod = bot.peek(0x7E0010)
      hush.log(string.format("floor %d (room %d): $7EF374 = %02X, TM in the room = %s, in the menu (module %02X) = %s", floor, idx, flags, tostring(before), mod, tostring(open)))
      hush.press({ "start" }, 3, 1)
      hush.wait(60)
      hush.log(string.format("   after closing: module %02X, TM = %s", bot.peek(0x7E0010), tostring(ppu_tm())))
    end
  end
  hush.pass()
end)
