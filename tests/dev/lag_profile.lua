-- Dev utility (E7, B-006): where does the frame go? Replays a chaos / bug repro like dev/chaos_replay.lua and, for every frame, records
--   * the PPU scanline when the main loop ends ($00805D, STZ $12; NMI = 225, later = the frame is lost),
--   * the number of live ancilla slots ($0C4A-$0C58 non-zero),
--   * the number of executed instructions per address (exec callback over the whole address space) split into two groups:
--     "busy" frames (>= HUSH_PROF_MIN live ancillae, default 4) and "idle" frames (no ancilla).
-- Output: build/lag_profile_<group>.txt with `bucket instructions-per-frame` lines (bucket = address >> 4; groups: lag = lagged frame + the one before,
-- ok = play frames without lag, busy_ok = ok frames with many ancillae) and a summary line per group.
--   HUSH_REPLAY=tests/chaos/repros/B-006_lag_pots_arrows_final.inputs .venv/bin/python tools/run_test.py tests/dev/lag_profile.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")

hush.test("lag profile", function()
  local path = os.getenv("HUSH_REPLAY")
  hush.assert(path and path ~= "", "set HUSH_REPLAY=<repro file>")
  if path:sub(1, 1) ~= "/" then path = hush.ROOT .. "/" .. path end
  local room, scenario, seed = nil, "replay", 0
  local pokes = {}
  for line in io.lines(path) do
    local r = line:match("^#%s*@room%s+(%S+)")
    if r then room = r end
    local sc, sd = line:match("^# chaos repro: scenario=(%S+) seed=(%d+)")
    if sc then scenario, seed = sc, tonumber(sd) end
    local f, a, v = line:match("^#@poke (%d+) (%x+) (%d+)")
    if f then pokes[#pokes + 1] = { frame = tonumber(f), addr = tonumber(a, 16), v = tonumber(v) } end
  end
  hush.assert(room, "no '# @room' header in " .. path)
  local minanc = tonumber(os.getenv("HUSH_PROF_MIN") or "4")
  local profile = os.getenv("HUSH_PROF_ADDR") ~= "0"
  C.NO_REPRO = true
  C.boot()
  local run = C.enter("lagprof_" .. scenario, seed, room, { menu_limit = 4000 })

  -- per frame: instruction counts per 16-byte bucket (addr >> 4); frames are classified when the run is over
  local pf, info = {}, {}
  local cur = nil
  local cur_scan = nil
  local ref1, ref2
  local wtype = tonumber(os.getenv("HUSH_PROF_TYPE") or "-1", 16)     -- HUSH_PROF_TYPE=09: per-address instruction counts inside HandleSingleAncilla calls of that type
  local win, winflag = {}, false
  if profile then
    ref1 = emu.addMemoryCallback(function(addr)
      if winflag then win[addr] = (win[addr] or 0) + 1 end
      if cur then
        local b = addr >> 4
        cur[b] = (cur[b] or 0) + 1
      end
    end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  end
  ref2 = emu.addMemoryCallback(function()
    cur_scan = emu.getState()["ppu.scanline"]
  end, emu.callbackType.exec, 0x00805D, 0x00805D)

  -- cycles per ancilla call by type ($088335 = JSR HandleSingleAncilla, $088338 = the next slot), only in play frames
  local acost = {}
  local ac0, atype
  local cyc = function() return emu.getState()["cpu.cycleCount"] end
  local refa = emu.addMemoryCallback(function() ac0 = cyc(); local x = emu.getState()["cpu.x"]; winflag = (wtype >= 0 and emu.read(0x7E0C4A + x, emu.memType.snesMemory, false) == wtype); atype = emu.read(0x7E0C4A + x, emu.memType.snesMemory, false); if atype == 7 then atype = 0x700 + emu.read(0x7E0C5E + x, emu.memType.snesMemory, false) end end, emu.callbackType.exec, 0x088335, 0x088335)
  local refb = emu.addMemoryCallback(function()
    winflag = false
    if ac0 then
      local t = atype
      local a = acost[t] or { n = 0, c = 0 }
      a.n = a.n + 1; a.c = a.c + (cyc() - ac0); acost[t] = a
      ac0 = nil
    end
  end, emu.callbackType.exec, 0x088338, 0x088338)
  local pi = 1
  C.guard(run, function()
    for _, s in ipairs(hush.parse_input_script(path)) do
      for _ = 1, s.frames do
        while pokes[pi] and pokes[pi].frame <= run.n do
          local p = pokes[pi]
          if p.addr == 0x7EC901 and p.v > 0 then run:jump(p.v - 1) else run:poke(p.addr, p.v) end
          pi = pi + 1
        end
        local n, tys = 0, {}
        for i = 0, 14 do local t = C.rd(0xC4A + i); if t ~= 0 then n = n + 1; tys[#tys + 1] = string.format("%02X", t) end end
        local k = #info + 1
        cur = {}
        cur_scan = nil
        local before = run.stats.lagged
        run:step(s.buttons)
        pf[k] = cur
        cur = nil
        local ax = {}
        for i = 0, 4 do ax[#ax + 1] = string.format("%d:%02X@%d,%d t%d", i, C.rd(0xC4A + i), C.rd(0xC04 + i) + 256 * C.rd(0xC18 + i), C.rd(0xBFA + i) + 256 * C.rd(0xC0E + i), C.rd(0xC5E + i)) end
        local gs = {}
        for g = 0, run.ng - 1 do gs[#gs + 1] = string.format("g%d@%d,%d/s%d/%02X", g, C.rd(0xD10 + g) + 256 * C.rd(0xD30 + g), C.rd(0xD00 + g) + 256 * C.rd(0xD20 + g), C.rd(0xD80 + g), C.rd(0xDD0 + g)) end
        info[k] = { axx = string.format("Link %d,%d  %s", C.rd16(0x22), C.rd16(0x20), table.concat(gs, " ")) .. " | " .. table.concat(ax, " | "), anc = n, tys = table.concat(tys, ","), ink = C.rd16(0xC90C), lag = run.stats.lagged > before, mod = C.rd(0x10), scan = cur_scan }
      end
    end
  end)
  emu.removeMemoryCallback(refa, emu.callbackType.exec, 0x088335, 0x088335)
  emu.removeMemoryCallback(refb, emu.callbackType.exec, 0x088338, 0x088338)
  for t, a in pairs(acost) do hush.log(string.format("ancilla type $%03X (7xx = bomb, xx = phase $0C5E): %d calls, %.0f cpu cycles per call (1 scanline ~ 227)", t, a.n, a.c / a.n)) end
  if profile then emu.removeMemoryCallback(ref1, emu.callbackType.exec, 0x000000, 0xFFFFFF) end
  emu.removeMemoryCallback(ref2, emu.callbackType.exec, 0x00805D, 0x00805D)
  -- groups: "lag" = a lagged frame and the one before it (the pass that overran), "ok" = play frames with no lag around them
  local grp, total, nfr = { lag = {}, ok = {}, busy_ok = {}, a0 = {}, fly = {}, nofly = {} }, { lag = 0, ok = 0, busy_ok = 0, a0 = 0, fly = 0, nofly = 0 }, { lag = 0, ok = 0, busy_ok = 0, a0 = 0, fly = 0, nofly = 0 }
  local function add(g, k)
    nfr[g] = nfr[g] + 1
    for b, c in pairs(pf[k]) do grp[g][b] = (grp[g][b] or 0) + c; total[g] = total[g] + c end
  end
  local anc_hist = { lag = {}, ok = {} }
  for k = 2, #info - 1 do
    local f = info[k]
    if f.mod == 7 and f.anc == 5 and not f.lag and not info[k + 1].lag then
      if f.tys:find("09", 1, true) then add("fly", k) else add("nofly", k) end
    end
    if f.mod == 7 then
      if f.lag then
        add("lag", k); add("lag", k - 1)
        anc_hist.lag[f.anc] = (anc_hist.lag[f.anc] or 0) + 1
      elseif not info[k + 1].lag then
        add("ok", k)
        if f.anc >= minanc then add("busy_ok", k) end
        if f.anc == 0 then add("a0", k) end
        anc_hist.ok[f.anc] = (anc_hist.ok[f.anc] or 0) + 1
      end
    end
  end
  if profile and wtype >= 0 then
    local f = io.open(hush.ROOT .. "/build/lag_profile_win.txt", "w")
    for a, c in pairs(win) do f:write(string.format("%06X %d\n", a, c)) end
    f:close()
  end
  if profile then
    for g, t in pairs(grp) do
      local f = io.open(hush.ROOT .. "/build/lag_profile_" .. g .. ".txt", "w")
      for b, c in pairs(t) do f:write(string.format("%05X %.2f\n", b, c / math.max(nfr[g], 1))) end
      f:close()
    end
  end
  for _, g in ipairs({ "lag", "ok", "busy_ok", "a0", "fly", "nofly" }) do
    hush.log(string.format("group %-8s: frames=%d  instructions/frame=%.0f", g, nfr[g], total[g] / math.max(nfr[g], 1)))
  end
  -- scanline where the logic ends, by ancilla signature (play frames that are not lagged); `n_lag` counts lagged frames with that signature
  local sig = {}
  for k = 1, #info do
    local f = info[k]
    if f.mod == 7 then
      local key = f.tys == "" and "-" or f.tys
      local e = sig[key] or { n = 0, sum = 0, max = 0, lag = 0 }
      if f.lag then e.lag = e.lag + 1 elseif f.scan then e.n = e.n + 1; e.sum = e.sum + f.scan; if f.scan > e.max then e.max = f.scan end end
      sig[key] = e
    end
  end
  local keys = {}
  for k, e in pairs(sig) do if e.n + e.lag >= 20 then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local e = sig[k]
    hush.log(string.format("ancillae [%-16s] frames ok=%-4d lagged=%-4d mean end-of-logic scanline=%.1f max=%d", k, e.n, e.lag, e.sum / math.max(e.n, 1), e.max))
  end
  local function h(t) local o = {} for i = 0, 14 do if t[i] then o[#o + 1] = i .. ":" .. t[i] end end return table.concat(o, " ") end
  if os.getenv("HUSH_PROF_TIMELINE") then
    local a, b = os.getenv("HUSH_PROF_TIMELINE"):match("(%d+)-(%d+)")
    for k = tonumber(a), tonumber(b) do
      local f = info[k]
      hush.log(string.format("frame %4d mod %02X anc=%d [%s] ink=%d scan=%s %s", k, f.mod, f.anc, f.tys, f.ink, tostring(f.scan), f.lag and "LAG" or "") .. "   " .. (f.axx or ""))
    end
  end
  hush.log("live ancillae of lagged frames: " .. h(anc_hist.lag))
  hush.log("live ancillae of ok play frames: " .. h(anc_hist.ok))
  hush.log(string.format("total lagged frames of the run: %d", run.stats.lagged))
  C.finish("profiled " .. run.n .. " frames of " .. path)
end)
