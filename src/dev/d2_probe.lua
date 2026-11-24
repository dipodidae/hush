-- Dev probe (engine, D2 / B-010; not a test): where a guard light job's frames go while Link stands still.
-- Rooms hard-coded (ROOMS). Per room: post-new-game + debug jump, 40 frames, left 10 frames, then STILL frames standing still
-- (the tests/dev/b010_light_done.lua set-up). Per light unit (Hush_LightWork .unit -> return of JSR Hush_L3Unit) the kind of the last
-- worker entered decides where its CPU cycles go: Hush_LightStep (job phase 0 clear / 1 wedges / 2 commit / 3 lattice, or the idle scan),
-- Hush_L3RegStep .row (region row: amber / glow), Hush_L3Pick. "gated lines" = VMAX - LightWork exit line when the loop ended below VMAX
-- (every unit said "not now"). Job = Hush_LightStep .start -> Hush_L3Lat .idle (frames, units per phase).
--   .venv/bin/python tools/run_test.py src/dev/d2_probe.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local VMAX = 200
local ROOMS = { "r19", "final", "r16", "r18" }
local STILL = 1200

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
local function rd(a) return emu.read(a, SNES, false) end
local function rdw(a) return rd(a) + 256 * rd(a + 1) end
local function stats(t)
  if #t == 0 then return { n = 0, mean = 0, med = 0, p90 = 0, max = 0, sum = 0 } end
  local s, sum = {}, 0
  for i, v in ipairs(t) do s[i] = v; sum = sum + v end
  table.sort(s)
  return { n = #s, mean = sum / #s, med = s[#s // 2 + 1], p90 = s[math.min(#s, math.floor(#s * 0.9) + 1)], max = s[#s], sum = sum }
end

hush.test("D2 probe (B-010 job profile)", function()
  local LW, LW_UNIT, LW_EXIT, LW_OUT = sym("Hush_LightWork"), sym("Hush_LightWork_unit"), sym("Hush_LightWork_exit"), sym("Hush_LightWork_out")
  local STEP, START, REG_ROW, PICK = sym("Hush_LightStep"), sym("Hush_LightStep_start"), sym("Hush_L3RegStep_row"), sym("Hush_L3Pick")
  local LATIDLE = sym("Hush_L3Lat_idle") or sym("Hush_LightCommit_end")   -- D2: the job ends at the commit
  local UNIT_RET
  for p = LW_UNIT, LW_UNIT + 8 do if rd(p) == 0x20 and rdw(p + 1) == (sym("Hush_L3Unit") & 0xFFFF) then UNIT_RET = p + 3 end end
  assert(UNIT_RET, "no JSR Hush_L3Unit")
  local function now() local s = emu.getState(); return s["cpu.cycleCount"], s["masterClock"], s["ppu.scanline"] end

  local R, fr, unit, job
  local cbs = {}
  local function on(addr, f) if addr then cbs[#cbs + 1] = { emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr), addr } end end
  local function new_room(name)
    R = { name = name, frames = 0, cyc = {}, cnt = {}, entry = {}, gated = {}, gatedby = {}, jobs = {}, jobunits = {}, jobfr = {},
          done = {}, used = {}, ra = { n = 0, pts = 0, chg = 0, tiles = 0, pre = 0, cmp = 0, til = 0, post = 0 } }
  end

  on(LW, function() local c, m, l = now(); fr = { c0 = c, m0 = m, l0 = l, last = nil } end)
  on(LW_UNIT, function() if fr then unit = { c0 = now(), kind = "none" } end end)
  on(STEP, function()
    if not unit then return end
    local j = rd(0x7EE770)
    if j == 0xFF then unit.kind = "scan" else unit.kind = "job" .. rd(0x7EE771) end
  end)
  on(REG_ROW, function() if unit then unit.kind = (rd(0x7FC7E1) == 0) and "regA" or "regG" end end)
  on(PICK, function() if unit then unit.kind = "pick" end end)
  on(sym("Hush_L3TPass"), function() if unit and rd(0x7FDBC0) ~= 0xFF then unit.kind = "tpass" end end)
  on(sym("Hush_L3LRow"), function()
    if unit then unit.kind = "lrow" end
    if R then R.lr0 = now(); R.lcalls = (R.lcalls or 0) + 1 end
  end)
  on(sym("Hush_L3LRow_stop"), function() if R and R.lr0 then R.lcyc = (R.lcyc or 0) + now() - R.lr0; R.lr0 = nil end end)
  on(sym("Hush_L3LRow_do"), function() if R then R.lrows = (R.lrows or 0) + 1 end end)
  on(sym("Hush_L3LRow_p"), function() if R then R.lpts = (R.lpts or 0) + 1 end end)
  on(sym("Hush_L3LRow_chg"), function() if R then R.lchg = (R.lchg or 0) + 1 end end)
  on(sym("Hush_LightStep_pick"), function() if R then R.scans = (R.scans or 0) + 1 end end)
  local ADIRTY, ADIRTY_RET = sym("Hush_L3ADirty"), nil
  if ADIRTY then
    on(ADIRTY, function() if R then R.adc0 = now(); R.adn = (R.adn or 0) + 1 end end)
    on(sym("Hush_L3ADirty_out"), function() if R and R.adc0 then R.adcyc = (R.adcyc or 0) + now() - R.adc0; R.adc0 = nil end end)
    on(sym("Hush_L3ADirty_chg"), function() if R then R.adchg = (R.adchg or 0) + 1 end end)
    on(sym("Hush_L3ADirty_mark"), function() if R then R.admark = (R.admark or 0) + 1 end end)
    on(sym("Hush_LightCommit_wait"), function() if R then R.cwait = (R.cwait or 0) + 1 end end)
    on(sym("Hush_LightCommit_chg"), function() if R then R.cchg = (R.cchg or 0) + 1 end end)
    on(sym("Hush_L3Tile"), function() if R then R.tiles = (R.tiles or 0) + 1 end end)
    on(sym("Hush_L3TPass"), function() if R then R.tp0 = now() end end)
    on(sym("Hush_L3TPass_fin"), function() if R and R.tp0 then R.tpcyc = (R.tpcyc or 0) + now() - R.tp0; R.tpn = (R.tpn or 0) + 1; R.tp0 = nil end end)
    on(sym("Hush_L3TPass_go"), function() if R then R.tprows = (R.tprows or 0) + 1 end end)
  end
  -- region row detail (amber): columns, changed points, compare / tile cycles
  local CMT, CMT_TILES, CMT_CHG, CMT_OUT = sym("Hush_L3Commit"), sym("Hush_L3Commit_tiles"), sym("Hush_L3Commit_chg"), sym("Hush_L3Commit_out")
  local CMT_CALL, CMT_R = sym("Hush_L3Commit_call"), sym("Hush_L3Commit_r")
  local function dpb(o) return rd(0x7E0000 + o) end
  on(CMT, function() if unit then unit.cm = { c0 = now(), n = dpb(1) - dpb(0) + 1, chg = 0, tiles = 0 } end end)
  on(CMT_CHG, function() if unit and unit.cm then unit.cm.chg = unit.cm.chg + 1 end end)
  on(CMT_TILES, function() if unit and unit.cm then unit.cm.c1 = now() end end)
  on(CMT_CALL, function() if unit and unit.cm then unit.cm.tiles = unit.cm.tiles + dpb(0x0B) - dpb(0x0A) + 1 end end)
  on(CMT_OUT, function() if unit and unit.cm then unit.cm.c2 = now() end end)
  on(START, function() job = { f0 = R and R.frames or 0, u = {} } end)
  on(LATIDLE, function()
    if job and R then
      R.jobfr[#R.jobfr + 1] = R.frames - job.f0
      R.jobs[#R.jobs + 1] = job
    end
    job = nil
  end)
  on(UNIT_RET, function()
    if not (unit and R) then return end
    local c = now()
    local k = unit.kind
    R.cyc[k] = (R.cyc[k] or 0) + (c - unit.c0)
    R.cnt[k] = (R.cnt[k] or 0) + 1
    if job and k:sub(1, 3) == "job" then job.u[k] = (job.u[k] or 0) + 1; job.c = (job.c or 0) + (c - unit.c0) end
    if k == "regA" and unit.cm and unit.cm.c2 then
    local q = R.ra
      q.n = q.n + 1; q.pts = q.pts + unit.cm.n; q.chg = q.chg + unit.cm.chg; q.tiles = q.tiles + unit.cm.tiles
      q.pre = q.pre + unit.cm.c0 - unit.c0; q.cmp = q.cmp + (unit.cm.c1 or unit.cm.c2) - unit.cm.c0
      q.til = q.til + unit.cm.c2 - (unit.cm.c1 or unit.cm.c2); q.post = q.post + c - unit.cm.c2
    end
    fr.last = k
    unit = nil
  end)
  on(LW_OUT, function()
    if not (fr and R) then return end
    local _, m, l = now()
    R.frames = R.frames + 1
    R.entry[#R.entry + 1] = fr.l0
    R.used[#R.used + 1] = (m - fr.m0) / 1364
    if l < VMAX and fr.l0 < VMAX then
      R.gated[#R.gated + 1] = VMAX - l
      local k = (rd(0x7EE770) ~= 0xFF) and ("job" .. rd(0x7EE771)) or "idle"
      k = k .. (rd(0x7FC7E0) ~= 0xFF and "+reg" or "")
      R.gatedby[k] = (R.gatedby[k] or 0) + (VMAX - l)
    end
    R.done[#R.done + 1] = rd(0x7EE7F6)
    fr = nil
  end)

  local function report()
    local f = function(fmt, ...) hush.log(string.format(fmt, ...)) end
    local e, u, g = stats(R.entry), stats(R.used), stats(R.gated)
    local first, run, maxrun, nd = nil, 0, 0, 0
    for i, d in ipairs(R.done) do
      if d == 1 then nd = nd + 1; first = first or i; run = 0 else run = run + 1; if run > maxrun then maxrun = run end end
    end
    f("== %s: %d light frames; first done %s, done on %d, longest done=0 run %d", R.name, R.frames, tostring(first), nd, maxrun)
    f("  entry line med %d p90 %d max %d; light lines used med %.1f; gated frames %d, gated lines sum %d (med %d)", e.med, e.p90, e.max, u.med, g.n, g.sum, g.med)
    local ks = {}
    for k, v in pairs(R.gatedby) do ks[#ks + 1] = string.format("%s %d", k, v) end
    table.sort(ks); f("  gated lines by state: %s", table.concat(ks, ", "))
    ks = {}
    local tot = 0
    for _, v in pairs(R.cyc) do tot = tot + v end
    for k, v in pairs(R.cyc) do ks[#ks + 1] = string.format("%s n=%d cyc=%d (%.0f%%, %.0f/unit)", k, R.cnt[k], v, 100 * v / tot, v / R.cnt[k]) end
    table.sort(ks); f("  units: %s", table.concat(ks, "; "))
    local jf = stats(R.jobfr)
    f("  jobs done %d: frames per job med %d p90 %d max %d", jf.n, jf.med, jf.p90, jf.max)
    local up = {}
    for _, jb in ipairs(R.jobs) do for k, v in pairs(jb.u) do up[k] = up[k] or {}; up[k][#up[k] + 1] = v end end
    ks = {}
    for k, t in pairs(up) do local s = stats(t); ks[#ks + 1] = string.format("%s med %d max %d", k, s.med, s.max) end
    table.sort(ks); f("  units per job: %s", table.concat(ks, "; "))
    local q = R.ra
    if R.adn then
      f("  ADirty calls %d, cyc %d (%.0f/call), changed points %d, marks %d; commit cell changes %d, waits %d; tiles derived (all) %d",
        R.adn, R.adcyc or 0, (R.adcyc or 0) / R.adn, R.adchg or 0, R.admark or 0, R.cchg or 0, R.cwait or 0, R.tiles or 0)
      f("  TPass calls reaching .fin %d, cyc %d, rows derived %d; LRow calls %d, cyc %d, lattice rows %d, points %d, changed %d",
        R.tpn or 0, R.tpcyc or 0, R.tprows or 0, R.lcalls or 0, R.lcyc or 0, R.lrows or 0, R.lpts or 0, R.lchg or 0)
    end
    if q.n > 0 then
      f("  amber row units %d: points/unit %.1f, changed/unit %.1f, tiles/unit %.1f; cyc/unit: before commit %.0f, compare %.0f, tiles %.0f, after %.0f",
        q.n, q.pts / q.n, q.chg / q.n, q.tiles / q.n, q.pre / q.n, q.cmp / q.n, q.til / q.n, q.post / q.n)
    end
  end

  local m = bot.rooms()
  bot.start_new_game()
  for _, id in ipairs(ROOMS) do
    local ri
    for i = 1, m.count do if m.rooms[i].id == id then ri = i end end
    R = nil; fr, unit, job = nil, nil, nil
    bot.jump_to_room(ri - 1)
    hush.wait(40)
    hush.hold({ "left" }, 10)
    new_room(id)
    fr, unit, job = nil, nil, nil
    hush.wait(STILL)
    report()
  end
  for _, cb in ipairs(cbs) do emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  hush.pass()
end)
