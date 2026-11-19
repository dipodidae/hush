-- Dev utility (not a test): sprite palette rows (CGRAM) and OAM tile usage in a guard room.
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("probe gfx", function()
  bot.start_new_game()
  bot.jump_to_room(2)
  hush.wait(60)
  for r = 0, 7 do
    local t = {}
    for i = 0, 15 do
      local a = 0x100 + r * 32 + i * 2
      local c = emu.read(a, emu.memType.snesCgRam, false) + 256 * emu.read(a + 1, emu.memType.snesCgRam, false)
      t[#t + 1] = string.format("%04X", c)
    end
    hush.log("SPR row " .. r .. ": " .. table.concat(t, " "))
  end
  -- OAM tiles in use
  local seen = {}
  for i = 0, 127 do
    local y = emu.read(i * 4 + 1, emu.memType.snesSpriteRam, false)
    local tile = emu.read(i * 4 + 2, emu.memType.snesSpriteRam, false)
    local attr = emu.read(i * 4 + 3, emu.memType.snesSpriteRam, false)
    if y < 0xE0 then seen[#seen + 1] = string.format("%d:t%02X a%02X", i, tile, attr) end
  end
  hush.log("OAM: " .. table.concat(seen, ", "))
  hush.screenshot("probe")
  hush.pass()
end)
