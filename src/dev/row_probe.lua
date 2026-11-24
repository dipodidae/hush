-- Dev probe (engine, L3 B2d / C1 profile, C4: tile loop, tiles == LUT(composite) check, render intervals; not a test): where the light's
-- frame time goes, per region unit, while walking.
-- Rooms (0-based index list, env ROOMS, default "0,12,20" = r01, r13, final). Addresses come from build/hush.sym; the few unnamed
-- points (JSR return sites, the RTL into the RAM loop, the end of the commit compare loop, the light_tiles store) are found by scanning
-- the ROM bytes from a named label and checked against the expected opcodes (the probe errors if the code moved under it).
-- Time = cpu.cycleCount deltas (CPU cycles; Mesen2 counts every bus / internal cycle) and masterClock deltas (/ 1364 = scanlines).
--   .venv/bin/python tools/run_test.py src/dev/row_probe.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local VMAX, RSET_C, RQ_C = 200, tonumber(os.getenv("RSET") or "6"), tonumber(os.getenv("RQ") or "6")   -- C4: sizing constants (light.asm L3_RSET / L3_RQ)

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
local function find_jsr(from, to, target)            -- address of `JSR target` (20 lo hi) in [from, to)
  for p = from, to - 3 do
    if rd(p) == 0x20 and rdw(p + 1) == (target & 0xFFFF) then return p end
  end
  error(string.format("no JSR %06X in %06X-%06X", target, from, to))
end
local function expect(a, op, what) if rd(a) ~= op then error(string.format("%s: %06X is %02X, expected %02X", what, a, rd(a), op)) end end
local function find_jsl(from, to, target)            -- address of `JSL target` (22 lo hi bank) in [from, to)  (C3)
  for p = from, to - 4 do
    if rd(p) == 0x22 and rdw(p + 1) == (target & 0xFFFF) and rd(p + 3) == (target >> 16) then return p end
  end
  error(string.format("no JSL %06X in %06X-%06X", target, from, to))
end

local function stats(t)
  if #t == 0 then return { n = 0, mean = 0, med = 0, p90 = 0, max = 0, min = 0, sum = 0 } end
  local s = {}
  local sum = 0
  for i, v in ipairs(t) do s[i] = v; sum = sum + v end
  table.sort(s)
  return { n = #s, mean = sum / #s, med = s[#s // 2 + 1], p90 = s[math.min(#s, math.floor(#s * 0.9) + 1)], max = s[#s], min = s[1], sum = sum }
end

hush.test("row probe (C1 profile)", function()
  -- named points
  local LW, LW_UNIT, LW_EXIT, LW_OUT = sym("Hush_LightWork"), sym("Hush_LightWork_unit"), sym("Hush_LightWork_exit"), sym("Hush_LightWork_out")
  local UNIT, REG, REG_ROW, PICK, LIST = sym("Hush_L3Unit"), sym("Hush_L3RegStep"), sym("Hush_L3RegStep_row"), sym("Hush_L3Pick"), sym("Hush_L3List")
  local COMP, COMP_C, COMP_CALL, COMP_R, COMP_OUT = sym("Hush_L3Compose"), sym("Hush_L3Compose_c"),
    sym("Hush_L3Compose_call"), sym("Hush_L3Compose_r"), sym("Hush_L3Compose_out")
  local CMT, CMT_TILES, CMT_CHG, CMT_CALL, CMT_R, CMT_OUT = sym("Hush_L3Commit"), sym("Hush_L3Commit_tiles"), sym("Hush_L3Commit_chg"),
    sym("Hush_L3Commit_call"), sym("Hush_L3Commit_r"), sym("Hush_L3Commit_out")
  local TL, TL_S, TL_V = sym("Hush_L3Tile"), sym("Hush_L3Tile_S"), sym("Hush_L3Tile_V")   -- C4: RAM tile loop (bank $7F)
  local LV, LATE, STEP, AURA = sym("Hush_LightV"), sym("Hush_LightLate"), sym("Hush_LightStep"), sym("Hush_LightAura")
  local LUTA, LUTV = sym("Hush_LightLutA"), sym("Hush_LightLutV")
  local G0, G1, P0, P1 = sym("Hush_L3ComposeG"), sym("Hush_L3ComposeG_1"), sym("Hush_L3ComposeP"), sym("Hush_L3ComposeP_1")
  -- derived points (checked)
  local UNIT_RET = find_jsr(LW_UNIT, LW_UNIT + 8, UNIT) + 3
  local AURA_RET = find_jsr(LW, LW_UNIT, AURA) + 3
  local PICK_JSR = PICK                                 -- C3: RegStep JMPs to the pick; a pick is a unit of its own
  local COMP_JSR = find_jsl(REG_ROW, REG_ROW + 0xA0, COMP)
  local CMT_JSR = find_jsl(REG_ROW, REG_ROW + 0xA0, CMT)
  local CMT_RET = CMT_JSR + 4
  local CALL_RTL
  for p = COMP_CALL, COMP_R - 1 do if rd(p) == 0x6B then CALL_RTL = p end end
  if CALL_RTL ~= COMP_R - 1 then error("Compose .call: RTL not right before .r") end
  local TCALL_RTL = CMT_R - 1                           -- C4: the RTL into the tile loop
  expect(TCALL_RTL, 0x6B, "Commit .call RTL")      -- (the RAM loop is copied at the first room load: not checked here)
  expect(LV + 24, 0x60, "Hush_LightV RTS")
  hush.log(string.format("points: unit %06X-%06X pick %06X compose %06X rtl %06X commit %06X tiles %06X tile-rtl %06X ram loop %06X",
    LW_UNIT, UNIT_RET, PICK_JSR, COMP_JSR, CALL_RTL, CMT_JSR, CMT_TILES, TCALL_RTL, TL))

  local function now() local s = emu.getState(); return s["cpu.cycleCount"], s["masterClock"], s["ppu.scanline"] end
  local function dpb(o) local d = emu.getState()["cpu.d"] or 0; return emu.read(0x7E0000 + ((d + o) & 0xFFFF), SNES, false) end

  -- per-run state
  local R                       -- current room accumulator
  local fr, unit, comp, seg, cmt
  local cbs = {}
  local function on(addr, f) cbs[#cbs + 1] = { emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr), addr } end

  local function new_room(name)
    R = { name = name, frames = 0, entry = {}, exitl = {}, spare = {}, used = {}, pre = {}, aura = {}, nunits_reg = {}, nunits_job = {},
      job = {}, pickonly = {}, regunits = {}, lv = {}, late = {}, lvcost = {}, idle_after = {}, regstart = {}, regend = {}, dh = {}, wd = {},
      rdlast = {}, rdfr = {}, rdint8 = {}, rdintg = {}, rdy_nz = 0, rdy_s = 0, behind8 = 0, checks = 0, badidx = 0, badtile = 0 }
  end

  on(LW, function()
    local c, m, l = now()
    fr = { c0 = c, m0 = m, l0 = l, nreg = 0, njob = 0, lv = 0, late = 0, first = nil }
  end)
  on(AURA, function() if fr then fr.aura0 = now() end end)
  on(AURA_RET, function() if fr and fr.aura0 then local c = now(); R.aura[#R.aura + 1] = c - fr.aura0; fr.aura0 = nil end end)
  on(LV, function() if fr then fr.lv = fr.lv + 1; fr.lvc0 = now() end end)
  on(LV + 24, function() if fr and fr.lvc0 then R.lvcost[#R.lvcost + 1] = now() - fr.lvc0; fr.lvc0 = nil end end)
  on(LATE, function() if fr then fr.late = fr.late + 1 end end)
  on(LW_UNIT, function()
    if not fr then return end
    local c, m, l = now()
    if not fr.first then fr.first = c; R.pre[#R.pre + 1] = c - fr.c0 end
    unit = { c0 = c, m0 = m, l0 = l, kind = "none", lv0 = fr.lv }
  end)
  on(STEP, function() if unit and unit.kind ~= "region" then unit.kind = "job" end end)
  on(PICK_JSR, function() if unit and unit.kind ~= "region" then unit.kind = "pick" end end)
  on(REG_ROW, function()
    if not unit then return end
    unit.kind = "region"
    unit.r0 = now()                                    -- C4: the sizing point (RegStep has just read V)
    unit.i0, unit.i1, unit.j = dpb(0), nil, nil
  end)
  on(COMP_JSR, function() if unit then unit.i0, unit.i1, unit.j = dpb(0), dpb(1), dpb(2) end end)
  on(COMP, function()
    if not unit then return end
    comp = { c0 = now(), ncar = 0, nlat = rd(0x7FC7ED), ncall = 0, setups = {}, skips = {}, loop = 0, pts = 0, ptsG = 0, ptsP = 0, loopG = 0, loopP = 0 }
    seg = nil
  end)
  local function close_seg(c)
    if not seg then return end
    local tot = c - seg.c0
    if seg.loop then comp.setups[#comp.setups + 1] = tot - seg.loop else comp.skips[#comp.skips + 1] = tot end
    seg = nil
  end
  on(COMP_C, function()
    if not comp then return end
    local c = now()
    if comp.ncar == 0 then comp.zero = c - comp.c0 end
    close_seg(c)
    comp.ncar = comp.ncar + 1
    seg = { c0 = c }
  end)
  on(CALL_RTL, function()
    if not (comp and seg) then return end
    local s = emu.getState()
    local entry = ((s["cpu.a"] or 0) + 1) & 0xFFFF
    local lo = (s["cpu.x"] or 0) & 0xFF
    local e = dpb(0x06)                                -- C3: end = hi + 1 at $06
    local k = dpb(3) // 16                             -- C3: list entry
    local key = string.format("entry %d pS %04X", k, rdw(0x7FC640 + 16 * k + 4))
    R.dh[key] = (R.dh[key] or 0) + 1
    seg.l0 = s["cpu.cycleCount"]
    seg.n = e - lo
    seg.g = (entry == (G0 & 0xFFFF) or entry == (G1 & 0xFFFF))
    if not seg.g and not (entry == (P0 & 0xFFFF) or entry == (P1 & 0xFFFF)) then seg.g = nil end
  end)
  on(COMP_R, function()
    if not (comp and seg and seg.l0) then return end
    local l = now() - seg.l0
    seg.loop = l
    comp.ncall = comp.ncall + 1
    comp.loop = comp.loop + l
    comp.pts = comp.pts + seg.n
    if seg.g then comp.ptsG = comp.ptsG + seg.n; comp.loopG = comp.loopG + l else comp.ptsP = comp.ptsP + seg.n; comp.loopP = comp.loopP + l end
  end)
  on(COMP_OUT, function()
    if not comp then return end
    local c = now()
    close_seg(c)
    comp.total = c - comp.c0
    if unit then unit.comp = comp end
    comp = nil
  end)
  on(CMT, function() if unit then cmt = { c0 = now(), tiles = 0, changed = 0, vio = 0, chg = 0, loop = 0, tail = (emu.getState()["cpu.a"] or 0) & 0x80 ~= 0 } end end)
  on(CMT_CHG, function() if cmt then cmt.chg = cmt.chg + 1 end end)
  on(CMT_TILES, function() if cmt then cmt.cmp = now() - cmt.c0; cmt.c1 = now() end end)
  on(CMT_CALL, function() if cmt then cmt.tiles = cmt.tiles + dpb(0x0B) - dpb(0x0A) + 1 end end)
  on(TCALL_RTL, function() if cmt then cmt.l0 = now() end end)
  on(CMT_R, function() if cmt and cmt.l0 then cmt.loop = cmt.loop + now() - cmt.l0; cmt.l0 = nil end end)
  on(TL_V, function() if cmt then cmt.vio = cmt.vio + 1 end end)
  on(TL_S, function() if cmt then cmt.changed = cmt.changed + 1 end end)
  on(CMT_OUT, function()
    if not cmt then return end
    local c = now()
    cmt.tile = c - (cmt.c1 or c)
    cmt.total = c - cmt.c0
    if unit then unit.cmt = cmt end
    cmt = nil
  end)
  on(UNIT_RET, function()
    if not (unit and fr) then return end
    local c, m, l = now()
    unit.total = c - unit.c0
    unit.rtotal = unit.r0 and (c - unit.r0) or unit.total
    unit.lines = (m - unit.m0) / 1364
    if unit.kind == "region" then
      fr.nreg = fr.nreg + 1
      if unit.comp or unit.cmt then                    -- C3: units that rendered a segment (C4: or a tail row)
        R.regstart[#R.regstart + 1] = unit.l0
        R.regend[#R.regend + 1] = l
      end
      R.regunits[#R.regunits + 1] = unit
    elseif unit.kind == "job" then
      fr.njob = fr.njob + 1
      R.job[#R.job + 1] = unit.total
    elseif unit.kind == "pick" then
      R.pickonly[#R.pickonly + 1] = unit.total
    end
    unit = nil
  end)
  on(LW_EXIT, function() if fr then local _, _, l = now(); fr.exitl = l end end)
  on(LW_OUT, function()
    if not fr then return end
    local c, m, l = now()
    R.frames = R.frames + 1
    R.entry[#R.entry + 1] = fr.l0
    if fr.l0 < VMAX then R.spare[#R.spare + 1] = VMAX - fr.l0 end
    R.used[#R.used + 1] = (m - fr.m0) / 1364
    R.exitl[#R.exitl + 1] = l
    R.nunits_reg[#R.nunits_reg + 1] = fr.nreg
    R.nunits_job[#R.nunits_job + 1] = fr.njob
    R.lv[#R.lv + 1] = fr.lv
    R.late[#R.late + 1] = fr.late
    if l < VMAX then R.idle_after[#R.idle_after + 1] = VMAX - l end
    local function sb(v) if v >= 128 then return v - 256 end return v end
    local key = string.format("W(%d,%d) R(%d,%d) cell %02X", sb(rd(0x7FC738)), sb(rd(0x7FC748)), sb(rd(0x7FC718)), sb(rd(0x7FC728)), rd(0x7FC708))
    R.wd[key] = (R.wd[key] or 0) + 1
    -- C4: rendered d changes per carrier (a new region snapshot = a re-render of a moved carrier)
    for c = 0, 8 do
      local dx, dy = sb(rd(0x7FC710 + c)), sb(rd(0x7FC720 + c))
      local k = dx .. "," .. dy
      if R.rdlast[c] and R.rdlast[c] ~= k then
        local t = (c == 8) and R.rdint8 or R.rdintg
        if R.rdfr[c] then t[#t + 1] = R.frames - R.rdfr[c] end
        R.rdfr[c] = R.frames
      end
      R.rdlast[c] = k
      if dy ~= 0 then R.rdy_nz = R.rdy_nz + 1 end
      if dy % 8 ~= 0 then R.rdy_s = R.rdy_s + 1 end
    end
    if sb(rd(0x7FC738)) ~= sb(rd(0x7FC718)) or sb(rd(0x7FC748)) ~= sb(rd(0x7FC728)) then R.behind8 = R.behind8 + 1 end
    -- C4: with no region running, every BG1 tile must be LUT(composite corners) and IA / IV must hold its index
    if rd(0x7FC7E0) == 0xFF and R.frames % 5 == 0 then
      R.checks = R.checks + 1
      for ty = 0, 27 do
        for tx = 0, 31 do
          local function g(base, i, j) return rd(0x7F0000 + base + (j + 2) * 38 + i + 2) end
          local a, b, cc, d = g(0xB400, tx, ty), g(0xB400, tx + 1, ty), g(0xB400, tx, ty + 1), g(0xB400, tx + 1, ty + 1)
          local ia = 2 * (((a * 7 + b) * 7 + cc) * 7 + d)
          local va, vb, vc, vd = g(0xB910, tx, ty), g(0xB910, tx + 1, ty), g(0xB910, tx, ty + 1), g(0xB910, tx + 1, ty + 1)
          local iv = 2 * (((va * 3 + vb) * 3 + vc) * 3 + vd)
          local want = (ia ~= 0) and rdw(LUTA + ia) or rdw(LUTV + iv)
          local o = (ty + 1) * 68 + (tx + 1) * 2
          if rdw(0x7FCB00 + o) ~= ia or rdw(0x7FD2F8 + o) ~= iv then R.badidx = R.badidx + 1 end
          if rdw(0x7EDA40 + ty * 64 + tx * 2) ~= want then
            R.badtile = R.badtile + 1
            if not R.firstbad then R.firstbad = string.format("frame %d tile (%d,%d) has %04X want %04X", R.frames, tx, ty, rdw(0x7EDA40 + ty * 64 + tx * 2), want) end
          end
        end
      end
    end
    fr = nil
  end)

  local function report()
    local function f(fmt, ...) return string.format((fmt:gsub("%%d", "%%.0f")), ...) end
    local e, sp, ex, us = stats(R.entry), stats(R.spare), stats(R.exitl), stats(R.used)
    hush.log(f("== %s: %d light frames", R.name, R.frames))
    hush.log(f("  LightWork entry line med %d p90 %d max %d; spare lines to VMAX med %d min %d; exit line med %d; light time used med %.1f max %.1f lines; unused before VMAX at exit med %d",
      e.med, e.p90, e.max, sp.med, sp.min, ex.med, us.med, us.max, stats(R.idle_after).med))
    hush.log(f("  pre-units (Want/Pal/Ink/Aura) cyc med %d max %d; Aura cyc med %d (n %d)", stats(R.pre).med, stats(R.pre).max, stats(R.aura).med, #R.aura))
    hush.log(f("  units/frame: region mean %.2f, job mean %.2f; job unit cyc med %d mean %d max %d (n %d); pick-only units n %d cyc med %d",
      stats(R.nunits_reg).mean, stats(R.nunits_job).mean, stats(R.job).med, stats(R.job).mean, stats(R.job).max, #R.job, #R.pickonly, stats(R.pickonly).med))
    hush.log(f("  LightV calls/frame mean %.1f, cyc/call med %d; LightLate calls/frame mean %.1f", stats(R.lv).mean, stats(R.lvcost).med, stats(R.late).mean))
    hush.log(f("  region unit start line med %d p90 %d max %d; end line med %d p90 %d max %d", stats(R.regstart).med, stats(R.regstart).p90, stats(R.regstart).max,
      stats(R.regend).med, stats(R.regend).p90, stats(R.regend).max))
    local tot, pick, ct, zero, setup, skip, loop, pts, cols, ncar, nlat, ncall = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
    local cmpc, tilec, tiles, chg, other, ctot, loopG, ptsG, loopP, ptsP, lines, vio, emp = {}, {}, {}, {}, {}, {}, 0, 0, 0, 0, {}, {}, {}
    local perpt = {}
    local fitn, fitt, fitk, tailt, tailtiles, chgpts, perchg = {}, {}, {}, {}, {}, {}, {}
    for _, u in ipairs(R.regunits) do
      if u.cmt and u.cmt.tail then
        tailt[#tailt + 1] = u.total; tailtiles[#tailtiles + 1] = u.cmt.tiles
      end
      if u.comp and u.cmt then
        local c = u.comp
        local n = (u.i1 or u.i0) - u.i0 + 1
        fitn[#fitn + 1] = n; fitt[#fitt + 1] = u.rtotal; fitk[#fitk + 1] = c.nlat
        chgpts[#chgpts + 1] = u.cmt.chg
        if n >= 3 then perchg[#perchg + 1] = u.cmt.chg / n end
        tot[#tot + 1] = u.total; lines[#lines + 1] = u.lines
        pick[#pick + 1] = u.pick or 0
        ct[#ct + 1] = c.total; zero[#zero + 1] = c.zero or 0
        for _, v in ipairs(c.setups) do setup[#setup + 1] = v end
        for _, v in ipairs(c.skips) do skip[#skip + 1] = v end
        loop[#loop + 1] = c.loop; pts[#pts + 1] = c.pts; cols[#cols + 1] = n
        ncar[#ncar + 1] = c.ncar; nlat[#nlat + 1] = c.nlat; ncall[#ncall + 1] = c.ncall
        loopG, ptsG, loopP, ptsP = loopG + c.loopG, ptsG + c.ptsG, loopP + c.loopP, ptsP + c.ptsP
        cmpc[#cmpc + 1] = u.cmt.cmp or 0; tilec[#tilec + 1] = u.cmt.tile or 0; tiles[#tiles + 1] = u.cmt.tiles; chg[#chg + 1] = u.cmt.changed
        vio[#vio + 1] = u.cmt.vio; emp[#emp + 1] = u.cmt.loop
        ctot[#ctot + 1] = u.cmt.total
        other[#other + 1] = u.total - (u.pick or 0) - c.total - u.cmt.total
        perpt[#perpt + 1] = u.total / n
      end
    end
    local function row(name, t) local s = stats(t); hush.log(f("  | %s | %d | %.1f | %d | %d | %d |", name, s.n, s.mean, s.med, s.p90, s.max)) end
    hush.log("  | per region unit | n | mean | med | p90 | max |")
    row("unit total cyc", tot); row("unit total lines", lines); row("columns (lattice points) per unit", cols); row("unit cyc per column", perpt)
    row("(a) pick cyc (0 if none)", pick)
    row("(b) compose total cyc", ct); row("(b) compose NEW clear cyc", zero);     row("(b) carriers walked (.c)", ncar)
    row("(b) list entries (L3_RN)", nlat); row("(b) carriers overlapping row (loop called)", ncall)
    row("(b) set-up cyc per overlapping carrier", setup); row("(b) cost cyc per skipped carrier", skip)
    row("(c) loop cyc per unit", loop); row("(c) points looped per unit", pts)
    row("(d) commit compare cyc (incl. deltas)", cmpc); row("(d) changed points per unit", chgpts); row("(e) commit tile part cyc", tilec)
    row("(e) tiles derived", tiles); row("(e) tiles changed", chg)
    row("(e) tiles via violet path", vio); row("(e) RAM tile loop cyc (incl. RTL in / out)", emp)
    row("(f) other in unit cyc (RegStep, V, JSRs)", other)
    row("tail-row units cyc", tailt); row("tail-row tiles derived", tailtiles); row("changed points per column (n >= 3)", perchg)
    hush.log(f("  (c) loop cyc/point: general (s>0) %.1f over %d pts, s=0 %.1f over %d pts", ptsG > 0 and loopG / ptsG or 0, ptsG, ptsP > 0 and loopP / ptsP or 0, ptsP))
    -- C4: unit cost model total = a + b n (least squares), and the worst per-column slope above a
    local sn, st2, snn, snt, m = 0, 0, 0, 0, #fitn
    for i = 1, m do sn = sn + fitn[i]; st2 = st2 + fitt[i]; snn = snn + fitn[i] ^ 2; snt = snt + fitn[i] * fitt[i] end
    if m >= 2 and (m * snn - sn ^ 2) ~= 0 then
      local b = (m * snt - sn * st2) / (m * snn - sn ^ 2)
      local a = (st2 - b * sn) / m
      local over = {}
      for i = 1, m do over[#over + 1] = (fitt[i] - a) / fitn[i] end
      local o = stats(over)
      local ratio, overrun = {}, 0
      for i = 1, m do
        local model = (RSET_C + fitk[i] + fitn[i] * (RQ_C + fitk[i]) / 4) * 175
        ratio[#ratio + 1] = fitt[i] / model
        if fitt[i] > model then overrun = overrun + 1 end
      end
      local rs = stats(ratio)
      hush.log(f("  unit model fit (from RegStep .row to unit end): total = %d + %.1f n cyc (n %d units); (total - a) / n p90 %d max %d; sizing (RSET %d, RQ %d): actual / model med %.2f p90 %.2f max %.2f, %d overrun(s)",
        a, b, m, o.p90, o.max, RSET_C, RQ_C, rs.med, rs.p90, rs.max, overrun))
    end
    local i8, ig = stats(R.rdint8), stats(R.rdintg)
    hush.log(f("  frames between renders (rendered d changes): glow med %d p90 %d max %d (n %d); guards med %d p90 %d max %d (n %d); frames glow W != R %d of %d",
      i8.med, i8.p90, i8.max, i8.n, ig.med, ig.p90, ig.max, ig.n, R.behind8, R.frames))
    hush.log(f("  carrier-frames with rendered dy != 0: %d, with s > 0 (dy %% 8 != 0): %d", R.rdy_nz, R.rdy_s))
    hush.log(f("  tiles == LUT(composite) check at %d idle frames: %d bad tiles, %d bad IA / IV entries%s", R.checks, R.badtile, R.badidx,
      R.firstbad and ("; first " .. R.firstbad) or ""))
    local ks = {}
    for k, v in pairs(R.dh) do ks[#ks + 1] = string.format("%s x%d", k, v) end
    table.sort(ks)
    hush.log("  loop calls by carrier / rendered d: " .. table.concat(ks, "; "))
    ks = {}
    for k, v in pairs(R.wd) do ks[#ks + 1] = string.format("%s x%d", k, v) end
    table.sort(ks)
    hush.log("  per frame, carrier 8 wanted d / rendered d / CELL: " .. table.concat(ks, "; "))
    local st, sc = stats(tilec).sum, stats(tiles).sum
    hush.log(f("  (e) tile part cyc per derived tile %.1f; RAM loop cyc per tile %.1f", sc > 0 and st / sc or 0, sc > 0 and stats(emp).sum / sc or 0))
  end

  local rooms = {}
  for x in (os.getenv("ROOMS") or "0,12,20"):gmatch("%d+") do rooms[#rooms + 1] = tonumber(x) end
  local m = bot.rooms()
  bot.start_new_game()
  for _, ri in ipairs(rooms) do
    fr, unit, comp, seg, cmt = nil, nil, nil, nil, nil
    new_room("") -- discard the load frames
    bot.jump_to_room(ri)
    hush.wait(30)
    new_room(m.rooms[ri + 1].id)
    fr, unit, comp, seg, cmt = nil, nil, nil, nil, nil
    local f0 = hush.frame()
    hush.hold({"left"}, 60); hush.hold({"up"}, 60); hush.hold({"right"}, 60); hush.hold({"down"}, 60)   -- C4: + down
    hush.log(string.format("%s: %d frames walked, %d light frames (lag = difference)", R.name, hush.frame() - f0, R.frames))
    report()
  end
  for _, cb in ipairs(cbs) do emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  hush.pass()
end)
