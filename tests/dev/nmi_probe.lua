-- Dev utility (not a test): frame budget with / without lighting. Scanline of Hush_NmiTM (NMI) and of the end of the game logic ($00805D).
--   ROOM=20 NOLIGHT=1 .venv/bin/python tools/run_test.py tests/dev/nmi_probe.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("nmi probe", function()
  bot.start_new_game()
  bot.jump_to_room(tonumber(os.getenv("ROOM") or "20"))
  hush.wait(30)
  if (os.getenv("NOLIGHT") or "") ~= "" then hush.poke("light_on", 0) end   -- SA-1 BW-RAM (was the stale $7EE640)
  local lines, ends = {}, {}
  local r1 = emu.addMemoryCallback(function() lines[#lines + 1] = emu.getState()["ppu.scanline"] end, emu.callbackType.exec, 0x07FFAA, 0x07FFAA)
  local r2 = emu.addMemoryCallback(function() ends[#ends + 1] = emu.getState()["ppu.scanline"] end, emu.callbackType.exec, 0x00805D, 0x00805D)
  local f0 = hush.frame()
  hush.hold({"left"}, 60)
  hush.hold({"up"}, 60)
  hush.hold({"right"}, 60)
  local nf = hush.frame() - f0
  emu.removeMemoryCallback(r1, emu.callbackType.exec, 0x07FFAA, 0x07FFAA)
  emu.removeMemoryCallback(r2, emu.callbackType.exec, 0x00805D, 0x00805D)
  local late = 0
  for _, l in ipairs(ends) do if l >= 225 or l < 120 then late = late + 1 end end
  table.sort(lines); table.sort(ends)
  hush.log(string.format("frames=%d logic_ends=%d (lag=%d) late=%d | NmiTM min=%d med=%d max=%d | logic end min=%d med=%d p90=%d max=%d",
    nf, #ends, nf - #ends, late, lines[1], lines[#lines // 2], lines[#lines], ends[1], ends[#ends // 2], ends[math.floor(#ends * 0.9)], ends[#ends]))
  hush.pass()
end)
