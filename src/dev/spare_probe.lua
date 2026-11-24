-- Engine dev probe (NOT a qa test; engine-owned measurement helper for light.asm, docs/engine_notes.md section 16):
-- per room, the scanline at Hush_LightWork entry (= start of the light's spare time), end of logic ($00805D), NMI reach, lag.
--   .venv/bin/python tools/run_test.py src/dev/spare_probe.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local function sym(name)
  for line in io.lines(os.getenv("HUSH_ROOT") .. "/build/hush.sym") do
    local b, a, n = line:match("^(%x%x):(%x%x%x%x) (%S+)$")
    if n == name then return tonumber(b, 16) * 65536 + tonumber(a, 16) end
  end
  error("no symbol " .. name)
end
local function pct(t, p) if #t == 0 then return -1 end local k = math.max(1, math.ceil(p * #t)); return t[k] end

hush.test("spare probe", function()
  local m = bot.rooms()
  bot.start_new_game()
  local aw = sym("Hush_LightWork")
  hush.log("| room | guards | frames | lag | LightWork entry med/p90/max | logic end med/p90/max | NmiTM max |")
  for ri = 1, m.count do
    local id = m.rooms[ri].id
    bot.jump_to_room(ri - 1)
    hush.wait(20)
    local ent, ends, nmi = {}, {}, {}
    local r1 = emu.addMemoryCallback(function() ent[#ent + 1] = emu.getState()["ppu.scanline"] end, emu.callbackType.exec, aw, aw)
    local r2 = emu.addMemoryCallback(function() ends[#ends + 1] = emu.getState()["ppu.scanline"] end, emu.callbackType.exec, 0x00805D, 0x00805D)
    local r3 = emu.addMemoryCallback(function() nmi[#nmi + 1] = emu.getState()["ppu.scanline"] end, emu.callbackType.exec, 0x07FFAA, 0x07FFAA)
    local f0 = hush.frame()
    hush.hold({"left"}, 40); hush.hold({"up"}, 40); hush.hold({"right"}, 40); hush.hold({"down"}, 40)
    local nf = hush.frame() - f0
    emu.removeMemoryCallback(r1, emu.callbackType.exec, aw, aw)
    emu.removeMemoryCallback(r2, emu.callbackType.exec, 0x00805D, 0x00805D)
    emu.removeMemoryCallback(r3, emu.callbackType.exec, 0x07FFAA, 0x07FFAA)
    local g = 0
    for s = 0, 15 do if bot.peek(0x7E0DD0 + s) == 9 and bot.peek(0x7E0E20 + s) == 0x41 then g = g + 1 end end
    table.sort(ent); table.sort(ends); table.sort(nmi)
    hush.log(string.format("| %s | %d | %d | %d | %d/%d/%d | %d/%d/%d | %d |", id, g, nf, nf - #ends,
      pct(ent, 0.5), pct(ent, 0.9), ent[#ent] or -1, pct(ends, 0.5), pct(ends, 0.9), ends[#ends] or -1, nmi[#nmi] or -1))
  end
  hush.pass("done")
end)
