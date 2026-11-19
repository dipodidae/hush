-- Dev utility: CPU cycles spent per guard per frame, split into parts (exec callbacks + the CPU cycle counter).
--   HUSH_PROBE_KEEP=6 HUSH_PROBE_MODE=far .venv/bin/python tools/run_test.py tests/dev/guard_cost.lua
-- Needs build/hush_dev.sym (make build-dev). Parts: "entry" = Hush_GuardEntry .. the RTS at $05C226 (whole AI incl. draw),
-- "draw" = Hush_DrawGuard (or, on a ROM built before E4, the vanilla Guard_HandleAllAnimation_long $05C676 .. its RTL),
-- "frame" = $00805D to $00805D (one main-loop pass, includes NMI wait? no: the loop ends at STZ $12, so it is the logic + the NMI wait).
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local function sym(name)
  local f = io.open(os.getenv("HUSH_ROOT") .. "/build/hush_dev.sym")
  if not f then return nil end
  for l in f:lines() do
    local b, a, n = l:match("^(%x%x):(%x%x%x%x) (%S+)")
    if n == name then f:close(); return tonumber(b, 16) * 65536 + tonumber(a, 16) end
  end
  f:close()
end
hush.test("guard cost", function()
  local id = os.getenv("HUSH_PROBE_ROOM") or "ai8_crowd"
  ai.enter(id)
  local mode = os.getenv("HUSH_PROBE_MODE") or "far"
  local keep = tonumber(os.getenv("HUSH_PROBE_KEEP") or "6")
  for s = keep, 15 do bot.poke(0x7E0DD0 + s, 0) end
  if mode == "asleep" then for s = 0, keep - 1 do bot.poke(0x7E0D80 + s, 3); bot.poke(0x7E0DF0 + s, 255); bot.poke(0x7E0D90 + s, 200) end end
  if mode == "state2" then for s = 0, keep - 1 do bot.poke(0x7E0D80 + s, 2); bot.poke(0x7E0E10 + s, 255) end ai.link_to(0, 200, 20) end
  local cyc = function() return emu.getState()["cpu.cycleCount"] end
  local acc = { entry = 0, draw = 0, n = 0 }
  local t0, d0
  local refs = {}
  local function on(addr, fn) refs[#refs + 1] = { emu.addMemoryCallback(fn, emu.callbackType.exec, addr, addr), addr } end
  local entry = sym("Hush_GuardEntry") or 0x0EEE22
  on(entry, function() t0 = cyc() end)
  on(0x05C226, function() if t0 then acc.entry = acc.entry + (cyc() - t0); acc.n = acc.n + 1; t0 = nil end end)
  local dstart = (not os.getenv("HUSH_COST_VANILLA")) and sym("Hush_DrawGuard")
  if dstart then
    on(dstart, function() d0 = cyc() end)
    on(sym("Hush_GuardAI") + 4, function() if d0 then acc.draw = acc.draw + (cyc() - d0); d0 = nil end end)
  else
    on(0x05C676, function() d0 = cyc() end)
    on(0x05C67F, function() if d0 then acc.draw = acc.draw + (cyc() - d0); d0 = nil end end)
  end
  local marks = {}
  if dstart then
    for _, name in ipairs({ "Hush_DrawGuard_y_ok", "Hush_DrawGuard_write", "Hush_DrawGuard_no_icon", "Hush_DrawGuard_shadow" }) do
      local a = sym(name)
      if a then
        marks[name] = { sum = 0, n = 0 }
        on(a, function() if d0 then marks[name].sum = marks[name].sum + (cyc() - d0); marks[name].n = marks[name].n + 1 end end)
      end
    end
  end
  hush.wait(120)
  for name, m in pairs(marks) do hush.log(string.format("  mark %-26s avg %.0f cycles after draw start (%d hits)", name, m.sum / math.max(m.n, 1), m.n)) end
  for _, r in ipairs(refs) do emu.removeMemoryCallback(r[1], emu.callbackType.exec, r[2], r[2]) end
  hush.log(string.format("%s keep=%d mode=%s: guard calls=%d  AI total %.0f cycles/call, draw %.0f cycles/call (cpu cycles, 1 line ~ 227 fast-cycle equivalents)", id, keep, mode, acc.n, acc.entry / math.max(acc.n, 1), acc.draw / math.max(acc.n, 1)))
  hush.pass()
end)
