-- Dev probe (engine, L3 D4; measurement only, not a test): the glow (carrier 8) per room r01..r20 + final, same walk as c5_probe.lua
-- (jump, 30 frames, then left / up / right / down 75 frames each = 300 frames).
--   .venv/bin/python tools/run_test.py src/dev/d4_probe.lua          (ROOMS=0,13,20 for a subset, 0-based)
-- Definitions (as C5, adapted to the D4 driver):
--   glow re-render frames = frames between two glow region ends (Hush_L3GRun_end), kept when Link's wanted position changed in between;
--     the open interval at the walk end is included when it moved.
--   glow lag px = mean |W - R| per frame, W = Link's glow centre ($22 - $E2, $20 + 8 - $E8), R = (16cx + RDX, 16cy + RDY) of the last
--     region that ended (snapshot at its pick, Hush_L3GPick entry: CELL[8] / WDX / WDY then become RD).
--   clamp % = frames with |WDX| = 16 or |WDY| = 16 (carrier 8).
--   region cyc = CPU cycles inside Hush_L3GRun (entry -> .x) from a pick to its region end (several calls / frames).
--   aura max = lines from Hush_LightAura entry to Hush_L3GSlice entry on frames where Hush_L3GSet ran (a glow cell change).
--   exit max = the latest scanline of Hush_LightWork_out (light time overrun check; LIGHT_VMAX = 200).
-- @timeout 1500
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local VMAX, LEG = 200, tonumber(os.getenv("LEG") or "75")

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
local function rd(a) return emu.read(a, SNES, false) end
local function rdw(a) return rd(a) + 256 * rd(a + 1) end
local function sb(v) if v >= 128 then return v - 256 end return v end
local function sw(v) if v >= 32768 then return v - 65536 end return v end
local function stats(t)
  if #t == 0 then return { n = 0, mean = 0, med = 0, p90 = 0, max = 0 } end
  local s, sum = {}, 0
  for i, v in ipairs(t) do s[i] = v; sum = sum + v end
  table.sort(s)
  return { n = #s, mean = sum / #s, med = s[#s // 2 + 1], p90 = s[math.min(#s, math.floor(#s * 0.9) + 1)], max = s[#s] }
end

local CELL, RDX, RDY, WDX, WDY = 0x7FC708, 0x7FC718, 0x7FC728, 0x7FC738, 0x7FC748

hush.test("d4 probe", function()
  local LW, LW_OUT = sym("Hush_LightWork"), sym("Hush_LightWork_out")
  local GRUN, GRUN_X, GEND, GPICK = sym("Hush_L3GRun"), sym("Hush_L3GRun_x"), sym("Hush_L3GRun_end"), sym("Hush_L3GPick")
  local AURA, GSLICE, GLOW = sym("Hush_LightAura"), sym("Hush_L3GSlice"), sym("Hush_L3GSet")
  local function now() local s = emu.getState(); return s["cpu.cycleCount"], s["ppu.scanline"] end

  local on_, R, cur = false, nil, nil
  local g0, aura0, glowran
  local cbs = {}
  local function on(addr, f) cbs[#cbs + 1] = { emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr), addr } end
  on(LW, function() if on_ then local _, l = now(); R.entry[#R.entry + 1] = l end end)
  on(LW_OUT, function() if on_ then R.lframes = R.lframes + 1; local _, l = now(); if l > R.exitmax then R.exitmax = l end end end)
  on(AURA, function() aura0 = select(2, now()); glowran = false end)
  on(GLOW, function() glowran = true end)
  on(GSLICE, function()
    if on_ and aura0 and glowran then local _, l = now(); R.aura[#R.aura + 1] = l - aura0; if l > R.axmax then R.axmax = l end end
    aura0 = nil
  end)
  local GCOMMIT, GCHG = sym("Hush_L3Commit"), sym("Hush_L3GChg")
  local gl0, gn = 0, { c = 0, p = 0, x = 0 }
  local nlog = 0
  on(GCOMMIT, function() gn.c = gn.c + 1; if cur then cur.nc = cur.nc + 1 end end)
  on(GPICK, function() gn.p = gn.p + 1 end)
  on(GCHG, function() gn.x = gn.x + 1; if cur then cur.nx = cur.nx + 1 end end)
  local TROW = sym("Hush_L3TRow")
  on(TROW, function() if cur and g0 then cur.nt = cur.nt + 1 end end)
  on(GRUN, function() g0 = now(); gl0 = select(2, now()); gn = { c = 0, p = 0, x = 0 } end)
  on(GRUN_X, function()
    if g0 and cur then cur.cyc = cur.cyc + (now() - g0) end; g0 = nil
    if on_ then
      local _, l = now(); if l > R.gxmax then R.gxmax = l end
      if l > 204 and nlog < tonumber(os.getenv("LATELOG") or "0") then
        nlog = nlog + 1
        hush.log(string.format("  GRun late exit: entry %d exit %d GLIM %d commits %d picks %d changes %d", gl0, l, rdw(0x7FC7F4), gn.c, gn.p, gn.x))
      end
    end
  end)
  on(GPICK, function()
    local cell = rd(CELL)
    local c = now()
    if g0 and cur then cur.cyc = cur.cyc + (c - g0) end
    g0 = g0 and c                                -- the time from here on is the new region's
    cur = { cyc = 0, nc = 0, nx = 0, nt = 0, pos = cell ~= 0xFF and { x = 16 * (cell & 15) + sb(rd(WDX)), y = 16 * (cell >> 4) + sb(rd(WDY)) } or nil,
            pts = 0 }
  end)
  on(GEND, function()
    if not cur then return end
    local c = now()
    if g0 then cur.cyc = cur.cyc + (c - g0); g0 = c end
    if on_ then
      R.nreg = R.nreg + 1
      R.cyc[#R.cyc + 1] = cur.cyc
      R.nc[#R.nc + 1] = cur.nc; R.nx[#R.nx + 1] = cur.nx; R.nt[#R.nt + 1] = cur.nt
      R.pts[#R.pts + 1] = (rd(0x7FC7E3) - rd(0x7FC7E2) + 1) * (rd(0x7FC7E5) - rd(0x7FC7E4) + 1)
      R.drawn = cur.pos
      if R.moved then R.iv[#R.iv + 1] = hush.frame() - R.last end
      R.last = hush.frame(); R.moved = false
    end
    cur = nil
  end)
  on(sym("Hush_L3GRun_same"), function()         -- D4: same picture, the new d counts as rendered without a region
    if on_ then
      local cell = rd(CELL)
      R.nsame = R.nsame + 1
      if cell ~= 0xFF then R.drawn = { x = 16 * (cell & 15) + sb(rd(WDX)), y = 16 * (cell >> 4) + sb(rd(WDY)) } end
      if R.moved then R.iv[#R.iv + 1] = hush.frame() - R.last end
      R.last = hush.frame(); R.moved = false
    end
  end)

  local m = bot.rooms()
  bot.start_new_game()
  local rows = {}
  local only = os.getenv("ROOMS")
  for ri = 1, m.count do
    local id = m.rooms[ri].id
    if only and not ("," .. only .. ","):find("," .. (ri - 1) .. ",", 1, true) then goto skip end
    on_ = false
    bot.jump_to_room(ri - 1)
    hush.wait(30)
    R = { entry = {}, lframes = 0, nreg = 0, cyc = {}, iv = {}, lag = {}, aura = {}, clamp = 0, frames = 0, exitmax = 0, gxmax = 0, axmax = 0,
          nc = {}, nx = {}, nt = {}, pts = {}, nsame = 0,
          last = hush.frame(), moved = false, prevw = nil, drawn = nil }
    do local c = rd(CELL); if c ~= 0xFF then R.drawn = { x = 16 * (c & 15) + sb(rd(RDX)), y = 16 * (c >> 4) + sb(rd(RDY)) } end end
    cur = nil
    local f0 = hush.frame()
    on_ = true
    local function sample()
      local ex, ey = rdw(0x7E00E2), rdw(0x7E00E8)
      local wx, wy = sw((rdw(0x7E0022) - ex) & 0xFFFF), sw((rdw(0x7E0020) + 8 - ey) & 0xFFFF)
      if R.prevw and (R.prevw[1] ~= wx or R.prevw[2] ~= wy) then R.moved = true end
      R.prevw = { wx, wy }
      if rd(CELL) ~= 0xFF then
        R.frames = R.frames + 1
        if math.abs(sb(rd(WDX))) == 16 or math.abs(sb(rd(WDY))) == 16 then R.clamp = R.clamp + 1 end
        if R.drawn then R.lag[#R.lag + 1] = math.sqrt((wx - R.drawn.x) ^ 2 + (wy - R.drawn.y) ^ 2) end
      end
    end
    for _, b in ipairs({ "left", "up", "right", "down" }) do
      for _ = 1, LEG do hush.hold({ b }, 1); sample() end
    end
    on_ = false
    local nf = hush.frame() - f0
    if R.moved then R.iv[#R.iv + 1] = hush.frame() - R.last end
    local il, sp = stats(R.iv), {}
    for _, e in ipairs(R.entry) do sp[#sp + 1] = VMAX - e end
    local sps, au = stats(sp), stats(R.aura)
    local lg = #R.lag == 0 and "-" or string.format("%.1f", stats(R.lag).mean)
    local row = string.format("| %s | %d / %d / %d | %s | %d %% | %.1f + %.1f | %d (pts %d, commits %d, changes %d, tile rows %d) | %d / %d | %d | %d / %d / %d | %d |", id, il.med, il.p90, il.max, lg,
      R.frames == 0 and 0 or math.floor(100 * R.clamp / R.frames + 0.5), R.nreg * 60 / nf, R.nsame * 60 / nf, stats(R.cyc).med, stats(R.pts).med, stats(R.nc).med,
      stats(R.nx).med, stats(R.nt).med, au.med, au.max,
      sps.med, R.exitmax, R.gxmax, R.axmax, nf - R.lframes)
    rows[#rows + 1] = row
    hush.log(row)
    ::skip::
  end
  hush.log("| room | glow re-render frames med / p90 / max | glow lag px | at clamp | regions + same-picture skips / s | region cyc med (points, commits, changed points, tile rows) | aura lines med / max | spare med | max line: LightWork exit / GRun exit / aura end | lag frames |")
  hush.log("|---|---|---|---|---|---|---|---|---|---|")
  for _, r in ipairs(rows) do hush.log(r) end
  for _, cb in ipairs(cbs) do emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  hush.pass()
end)
