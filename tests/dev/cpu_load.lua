-- Dev utility: CPU headroom of the game loop. The main loop ends each frame at $00805D (STZ $12); the PPU scanline at that moment
-- says how much of the frame the game logic used (NMI = scanline 225; the logic must end before it, else the frame is lost = "lag").
--   HUSH_PROBE_ROOM=ai8_crowd HUSH_PROBE_KEEP=6 HUSH_PROBE_MODE=far .venv/bin/python tools/run_test.py tests/dev/cpu_load.lua
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local lines = {}
hush.test("cpu load", function()
  local id = os.getenv("HUSH_PROBE_ROOM") or "ai8_crowd"
  ai.enter(id)
  local mode = os.getenv("HUSH_PROBE_MODE") or "far"
  local keep = tonumber(os.getenv("HUSH_PROBE_KEEP") or "8")
  for s = keep, 15 do bot.poke(0x7E0DD0 + s, 0) end
  if mode == "asleep" then for s = 0, keep - 1 do bot.poke(0x7E0D80 + s, 3); bot.poke(0x7E0DF0 + s, 255); bot.poke(0x7E0D90 + s, 200) end end
  if os.getenv("HUSH_NOSHADOW") then for s = 0, keep - 1 do bot.poke(0x7E0E60 + s, bot.peek(0x7E0E60 + s) & 0xEF) end end
  if mode == "front" then ai.link_to(0, 72, 20) end
  if mode == "state2" then for s = 0, keep - 1 do bot.poke(0x7E0D80 + s, 2); bot.poke(0x7E0E10 + s, 255) end ai.link_to(0, 200, 20) end
  if mode == "chase" then for s = 0, keep - 1 do bot.poke(0x7E0D80 + s, 2); bot.poke(0x7E0E10 + s, 255) end ai.link_to(0, 100, 24) end
  local ref = emu.addMemoryCallback(function()
    local st = emu.getState()
    lines[#lines + 1] = st["ppu.scanline"] or -1
  end, emu.callbackType.exec, 0x00805D, 0x00805D)
  hush.wait(120)
  emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x00805D, 0x00805D)
  table.sort(lines)
  local n = #lines
  local sum = 0
  for _, l in ipairs(lines) do sum = sum + l end
  hush.log(string.format("%s keep=%s mode=%s: frames=%d scanline at end of logic: min=%d median=%d max=%d  (NMI at 225; >=225 means overrun)", id, keep, mode, n, lines[1], lines[(n + 1) // 2], lines[n]))
  hush.pass()
end)
