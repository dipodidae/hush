-- Dev probe (engine, E rev5 debug; not a test): counts of the amber pass entry points + guard carrier state in r08.
--   .venv/bin/python tools/run_test.py src/dev/e5_dbg.lua
-- @timeout 600
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local function rd(a) return emu.read(a, SNES, false) end
local function rdw(a) return rd(a) + 256 * rd(a + 1) end
local function sb(v) if v >= 128 then return v - 256 end return v end
local CA = 0x412860
local symtab
local function sym(name)
  if not symtab then
    symtab = {}
    for line in io.lines(os.getenv("HUSH_ROOT") .. "/build/hush.sym") do
      local b, a, n = line:match("^(%x%x):(%x%x%x%x) (%S+)$")
      if n then symtab[n] = tonumber(b, 16) * 65536 + tonumber(a, 16) end
    end
  end
  return symtab[name] or error("no symbol " .. name)
end

hush.test("e5 dbg", function()
  local cnt = {}
  for _, n in ipairs({ "Hush_L3AStep", "Hush_L3APick", "Hush_L3ARow", "Hush_L3ARow_end", "Hush_L3ARow_call", "Hush_L3ACommit", "Hush_L3GLat", "Hush_L3AZero", "Hush_L3PA", "Hush_L3GA", "Hush_L3Unit" }) do
    cnt[n] = 0
    emu.addMemoryCallback(function() cnt[n] = cnt[n] + 1 end, emu.callbackType.exec, sym(n), sym(n), emu.cpuType.sa1, emu.memType.sa1Memory)
  end
  local m = bot.rooms()
  bot.start_new_game()
  bot.jump_to_room(7)
  hush.wait(120)
  local s = {}
  for k, v in pairs(cnt) do s[#s + 1] = k .. "=" .. v end
  hush.log(table.concat(s, " "))
  for g = 0, 8 do hush.log(string.format("g%d cell %02X rd %d,%d wd %d,%d db x %d-%d y %d-%d lb x %d-%d y %d-%d", g, rd(0x41C700 + g),
    sb(rd(0x41C710 + g)), sb(rd(0x41C720 + g)), sb(rd(0x41C730 + g)), sb(rd(0x41C740 + g)), rd(0x41C750 + g), rd(0x41C760 + g),
    rd(0x41C770 + g), rd(0x41C780 + g), rd(0x41C790 + g), rd(0x41C7A0 + g), rd(0x41C7B0 + g), rd(0x41C7C0 + g))) end
  hush.log(string.format("apass %02X aj %02X rdm %04X adb %02X job %02X", rd(0x413D00), rd(0x413D01), rdw(0x41C7E8), rd(0x41DBC0), rd(0x40E770)))
  local nz, lnz = 0, 0
  for j = 0, 28 do for i = 0, 32 do if rd(CA + 38 * (j + 2) + i + 2) > 0 then nz = nz + 1 end end end
  for k = 0, 1291 do if rd(0x410000 + k) > 0 then lnz = lnz + 1 end end
  hush.log("CA non-zero points " .. nz .. ", lattice 0 non-zero bytes " .. lnz)
  local sp = {}
  for j = 0, 28 do sp[#sp + 1] = rd(0x413D40 + j) .. "-" .. rd(0x413D60 + j) end
  hush.log("spans " .. table.concat(sp, " "))
  hush.pass()
end)
