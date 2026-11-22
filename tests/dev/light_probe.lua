-- Dev utility (not a test): lighting state (design/lighting.md) in a HUSH room: registers, the composite light grid, a screenshot.
--   ROOM=20 FRAMES=90 .venv/bin/python tools/run_test.py tests/dev/light_probe.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("light probe", function()
  bot.start_new_game()
  local room = tonumber(os.getenv("ROOM") or "20")
  bot.jump_to_room(room)
  hush.wait(tonumber(os.getenv("FRAMES") or "90"))
  local function p(a) return bot.peek(0x7E0000 + a) end
  hush.log(string.format("TM=%02X TS=%02X CGWSEL=%02X CGADSUB=%02X on=%d job=%02X dirty=%04X",
    p(0x1C), p(0x1D), p(0x99), p(0x9A), p(0xE740), p(0xE770), p(0xE742) + 256 * p(0xE743)))
  for cy = 0, 13 do
    local t = {}
    for cx = 0, 15 do
      local i = cy * 16 + cx
      local c, v, s = p(0xD880 + i), p(0xD960 + i), p(0xCA00 + (cy + 8) * 32 + cx + 8)
      t[#t + 1] = c > 0 and tostring(c) or (v > 0 and "v" or (s & 1 == 1 and "#" or "."))
    end
    hush.log(table.concat(t))
  end
  for r = 2, 3 do
    local t, u = {}, {}
    for i = 0, 15 do local a = r * 32 + i * 2
      t[#t + 1] = string.format("%04X", emu.read(a, emu.memType.snesCgRam, false) + 256 * emu.read(a + 1, emu.memType.snesCgRam, false))
      u[#u + 1] = string.format("%04X", p(0xC500 + a) + 256 * p(0xC501 + a)) end
    hush.log("CGRAM row " .. r .. ": " .. table.concat(t, " ") .. " | buf " .. table.concat(u, " "))
  end
  hush.screenshot("probe")
  hush.pass()
end)
