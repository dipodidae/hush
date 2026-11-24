-- Dev probe (engine, SA-1 bring-up step 4; measurement only, not a test): the light worker on the SA-1. Per room r01..final, the walk of
-- d4_probe.lua (jump, 30 frames, then left / up / right / down LEG frames each).
--   .venv/bin/python tools/run_test.py src/dev/sa1_probe.lua          (ROOMS=0,13,20 for a subset, 0-based; LEG=75)
-- Columns:
--   logic end   = scanline of the SNES main loop end ($00805D, as spare_probe.lua) med / p90 / max; lag = frames without one.
--   NMI end     = max scanline of the NMI's INIDISP restore ($00821D / $0082BF, bank_00.asm:437 / :543; >= 262 = past the next frame's line 0).
--   rows / NMI  = max light cell rows uploaded by one Hush_LightNmi (Hush_LightUpRow calls, one per cell row since step 4); LIGHT_NMIEND caps it.
--   SA-1 busy   = scanlines (masterClock / 1364) from Hush_LightJob entry to Hush_LightJob_done, summed per frame: mean / max per frame;
--                 job med / max = one job; cut = % of jobs that ended because the next frame was posted (work left, not "done").
--   skip        = SNES frames that could not post (SA1_SKIP, I-RAM $3008: the previous frame not yet taken by the SA-1).
--   glow re-render frames / lag px: as d4_probe.lua (regions = Hush_L3GRun_end / _same; BW-RAM light_l3car, carrier 8).
-- @timeout 1500
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local LEG = tonumber(os.getenv("LEG") or "75")

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

local CELL, RDX, RDY, WDX, WDY = 0x41C708, 0x41C718, 0x41C728, 0x41C738, 0x41C748

hush.test("sa1 probe", function()
  local JOB, JDONE = sym("Hush_LightJob"), sym("Hush_LightJob_done")
  local GEND, GSAME, GPICK = sym("Hush_L3GRun_end"), sym("Hush_L3GRun_same"), sym("Hush_L3GPick")
  local UPROW, LNMI = sym("Hush_LightUpRow"), sym("Hush_LightNmi")
  local function clk() return emu.getState()["masterClock"] end
  local function line() return emu.getState()["ppu.scanline"] end

  local on_, R, cur = false, nil, nil
  local cbs = {}
  local function on(addr, f, cpu)
    local ref
    if cpu then ref = emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr, emu.cpuType.sa1, emu.memType.sa1Memory)
    else ref = emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr) end
    cbs[#cbs + 1] = { ref, addr, cpu }
  end
  -- SNES side
  on(0x00805D, function() if on_ then R.ends[#R.ends + 1] = line() end end)
  local function nmi_end() if on_ then local l = line(); if l < 200 then l = l + 262 end; if l > R.nmimax then R.nmimax = l end end end
  on(0x00821D, nmi_end); on(0x0082BF, nmi_end)
  local rows, nl0, nl1 = 0, 0, 0
  on(LNMI, function()
    if on_ then
      if rows > R.rowmax then R.rowmax = rows end
      local l = line(); if l < 200 then l = l + 262 end
      if l > R.nmient then R.nmient = l end
      if rows >= 2 then R.rowl[#R.rowl + 1] = (nl1 - nl0) / (rows - 1) end
    end
    rows = 0
  end)
  local upc, upd = nil, {}
  on(UPROW, function()
    local l = line(); if l < 200 then l = l + 262 end
    if rows == 0 then nl0 = l; upc = nil end
    nl1 = l
    local c = clk(); if upc and #upd < 400 then upd[#upd + 1] = c - upc end; upc = c
    rows = rows + 1
  end)
  -- SA-1 side
  local j0, jl0, posts, nlong = nil, 0, 0, 0
  on(sym("Hush_LightPost_stage"), function() posts = posts + 1 end)
  on(JOB, function() j0 = clk(); jl0 = line(); posts = 0 end, true)
  on(JDONE, function()
    if on_ and j0 then
      local d = (clk() - j0) / 1364
      R.jobs[#R.jobs + 1] = d
      local f = hush.frame()
      R.busy[f] = (R.busy[f] or 0) + d
      if rd(0x003000) ~= 0 then R.cut = R.cut + 1 end
      if d > 100 and nlong < tonumber(os.getenv("LONGLOG") or "0") then
        nlong = nlong + 1
        hush.log(string.format("  long job: %.0f lines, line %d -> %d, frame %d, posts during it %d, cmd %02X, light_job %02X, adb %02X, rc %02X, dirty %04X",
          d, jl0, line(), f, posts, rd(0x003000), rd(0x40E770), rd(0x41DBC0), rd(0x41C7E0), rdw(0x40E742)))
      end
    end
    j0 = nil
  end, true)
  on(GPICK, function()
    local cell = rd(CELL)
    cur = { pos = cell ~= 0xFF and { x = 16 * (cell & 15) + sb(rd(WDX)), y = 16 * (cell >> 4) + sb(rd(WDY)) } or nil }
  end, true)
  local function region_done(pos)
    if not on_ then return end
    R.drawn = pos or R.drawn
    if R.moved then R.iv[#R.iv + 1] = hush.frame() - R.last end
    R.last = hush.frame(); R.moved = false
  end
  on(GEND, function() if cur then region_done(cur.pos) end; cur = nil end, true)
  on(GSAME, function()
    local cell = rd(CELL)
    region_done(cell ~= 0xFF and { x = 16 * (cell & 15) + sb(rd(WDX)), y = 16 * (cell >> 4) + sb(rd(WDY)) } or nil)
  end, true)

  local m = bot.rooms()
  bot.start_new_game()
  local out = {}
  local only = os.getenv("ROOMS")
  for ri = 1, m.count do
    local id = m.rooms[ri].id
    if only and not ("," .. only .. ","):find("," .. (ri - 1) .. ",", 1, true) then goto skip end
    on_ = false
    bot.jump_to_room(ri - 1)
    hush.wait(30)
    R = { ends = {}, nmimax = 0, nmient = 0, rowl = {}, rowmax = 0, jobs = {}, busy = {}, cut = 0, iv = {}, lag = {}, last = hush.frame(), moved = false }
    do local c = rd(CELL); if c ~= 0xFF then R.drawn = { x = 16 * (c & 15) + sb(rd(RDX)), y = 16 * (c >> 4) + sb(rd(RDY)) } end end
    cur = nil
    local f0, skip0 = hush.frame(), rdw(0x003008)
    on_ = true
    local prevw
    for _, b in ipairs({ "left", "up", "right", "down" }) do
      for _ = 1, LEG do
        hush.hold({ b }, 1)
        local wx, wy = sw((rdw(0x7E0022) - rdw(0x7E00E2)) & 0xFFFF), sw((rdw(0x7E0020) + 8 - rdw(0x7E00E8)) & 0xFFFF)
        if prevw and (prevw[1] ~= wx or prevw[2] ~= wy) then R.moved = true end
        prevw = { wx, wy }
        if rd(CELL) ~= 0xFF and R.drawn then R.lag[#R.lag + 1] = math.sqrt((wx - R.drawn.x) ^ 2 + (wy - R.drawn.y) ^ 2) end
      end
    end
    on_ = false
    local nf = hush.frame() - f0
    if R.moved then R.iv[#R.iv + 1] = hush.frame() - R.last end
    local bl = {}
    for f = f0 + 1, f0 + nf do bl[#bl + 1] = R.busy[f] or 0 end
    local e, b, j, il = stats(R.ends), stats(bl), stats(R.jobs), stats(R.iv)
    local row = string.format("| %s | %d/%d/%d | %d | %d / %d | %d (%.2f lines) | %.1f / %.1f | %.1f / %.1f | %d %% | %d | %d / %d / %d | %s |", id,
      e.med, e.p90, e.max, nf - #R.ends, R.nmient, R.nmimax, R.rowmax, stats(R.rowl).med, b.mean, b.max, j.med, j.max,
      #R.jobs == 0 and 0 or math.floor(100 * R.cut / #R.jobs + 0.5), (rdw(0x003008) - skip0) & 0xFFFF,
      il.med, il.p90, il.max, #R.lag == 0 and "-" or string.format("%.1f", stats(R.lag).mean))
    out[#out + 1] = row
    hush.log(row)
    ::skip::
  end
  local us = stats(upd)
  hush.log(string.format("master clocks between Hush_LightUpRow calls in one NMI: med %d p90 %d max %d (n %d)", us.med, us.p90, us.max, us.n))
  hush.log("| room | logic end med/p90/max | lag | light NMI entry / NMI end max | rows / NMI max (lines per row med) | SA-1 busy lines / frame mean / max | job lines med / max | cut | skip | glow re-render frames med / p90 / max | glow lag px |")
  hush.log("|---|---|---|---|---|---|---|---|---|---|---|")
  for _, r in ipairs(out) do hush.log(r) end
  for _, cb in ipairs(cbs) do
    if cb[3] then emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2], emu.cpuType.sa1, emu.memType.sa1Memory)
    else emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  end
  hush.pass()
end)
