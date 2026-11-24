-- Dev probe (engine, E rev5; measurement only): SA-1 time per unit kind (master clocks / 1364 = scanlines) in a few rooms, Link walking
-- as in e5_probe (left / up / right / down 75 frames).
--   .venv/bin/python tools/run_test.py src/dev/e5_prof.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local symtab
local function sym(name)
  if not symtab then
    symtab = {}
    for line in io.lines(os.getenv("HUSH_ROOT") .. "/build/hush.sym") do
      local b, a, n = line:match("^(%x%x):(%x%x%x%x) (%S+)$")
      if n then symtab[n] = tonumber(b, 16) * 65536 + tonumber(a, 16) end
    end
  end
  return symtab[name]
end
hush.test("e5 prof", function()
  local function clk() return emu.getState()["masterClock"] end
  local T, N, t0, kind = {}, {}, nil, nil
  local on_ = false
  local function leave() if on_ and t0 then T[kind] = (T[kind] or 0) + clk() - t0; N[kind] = (N[kind] or 0) + 1 end; t0 = nil end
  local function enter(k) return function() leave(); if on_ then t0, kind = clk(), k end end end
  local pairs_ = {
    { "Hush_L3APick", "pick" }, { "Hush_L3ARow", "row" }, { "Hush_L3TPass", "tiles" }, { "Hush_LightStep", "job" }, { "Hush_L3GSlice", "glow" },
    { "Hush_L3GStep", "glow" }, { "Hush_L3GLat", "lattice" }, { "Hush_LightPub", "pub" }, { "Hush_LightRun_wait", "wait" }, { "Hush_LightJob", "run" },
    { "Hush_LightRun_unit", "loop" } }
  -- exits: every routine returns into Hush_L3Unit / Hush_LightRun; measure from entry to the next return point of the run loop
  for _, p in ipairs(pairs_) do
    local a = sym(p[1])
    if a then emu.addMemoryCallback(enter(p[2]), emu.callbackType.exec, a, a, emu.cpuType.sa1, emu.memType.sa1Memory) end
  end
  for _, n in ipairs({ "Hush_LightJob_done" }) do
    local a = sym(n)
    if a then emu.addMemoryCallback(leave, emu.callbackType.exec, a, a, emu.cpuType.sa1, emu.memType.sa1Memory) end
  end
  local m = bot.rooms()
  bot.start_new_game()
  for _, ri in ipairs({ 11, 18, 20 }) do
    T, N = {}, {}
    bot.jump_to_room(ri)
    hush.wait(30)
    on_ = true
    for _, b in ipairs({ "left", "up", "right", "down" }) do hush.hold({ b }, 75) end
    on_ = false
    local s = {}
    for k, v in pairs(T) do s[#s + 1] = string.format("%s %.1f lines/frame (%d calls)", k, v / 1364 / 300, N[k]) end
    table.sort(s)
    hush.log(m.rooms[ri + 1].id .. ": " .. table.concat(s, ", "))
  end
  hush.pass()
end)
