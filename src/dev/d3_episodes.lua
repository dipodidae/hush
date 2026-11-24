-- Dev probe (engine, D3 / B-010; not a test): replays the exact input of tests/smoke/lighting.lua (jump, 40 frames, 24 legs of 10 frames
-- + wait for light_done, r05 ink poke at t = 8) with its catch-up tracker (section 5 "Catch-up"), and for every stale episode whose change ->
-- commit time exceeds LONG frames prints the guard light jobs of that time: per job slot, class, start / end frame, restarts, frames per
-- phase, and whether the committed signature was already stale (the guard moved during the job).
--   .venv/bin/python tools/run_test.py src/dev/d3_episodes.lua      (HUSH_PROBE_ROOMS="r12 final" limits the logging, default all)
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, W, false) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
-- light state: SA-1 BW-RAM since SA-1 step 3 (offset = (bank - $40) * $10000 + addr: $40:E770 -> $E770, $41:DBC0 -> $1DBC0)
local B = emu.memType.snesSaveRam
local function rl(a) return emu.read(a, B, false) end
local function rl16(a) return rl(a) + 256 * rl(a + 1) end
local LONG = tonumber(os.getenv("HUSH_PROBE_LONG") or "40")
local WANT = {}
for id in (os.getenv("HUSH_PROBE_ROOMS") or ""):gmatch("%S+") do WANT[id] = true end

local function live_sig(s)
  local st, typ, aw = rd(0x0DD0 + s), rd(0x0E20 + s), rd(0x0D80 + s)
  if st ~= 9 or typ ~= 0x41 or aw >= 3 then return "0/0/0" end
  local x = rd(0x0D10 + s) + 256 * rd(0x0D30 + s) + 8 - rd16(0xE2)
  local y = rd(0x0D00 + s) + 256 * rd(0x0D20 + s) + 8 - rd16(0xE8)
  if x < 0 or x >= 256 or y < 0 or y >= 224 then return "0/0/0" end
  local cls = aw + 1
  return string.format("%d/%d/%d", cls, cls == 1 and (rd(0x0DE0 + s) & 3) or 0, (y // 16 + 8) * 32 + x // 16 + 8)
end
local function sigc(s) local b = 0xE748 + 4 * s; return string.format("%d/%d/%d", rl(b), rl(b + 1), rl16(b + 2)) end
local function jsig() return string.format("%d/%d/%d", rl(0xE76C), rl(0xE76D), rl16(0xE76E)) end

hush.test("D3 catch-up episode probe (smoke_lighting replay)", function()
  local m = bot.rooms()
  bot.start_new_game()
  local moves = { { "left" }, { "up" }, { "right" }, { "down" } }
  local summary = {}
  for ri = 1, m.count do
    local r = m.rooms[ri]
    local log = (next(WANT) == nil) or WANT[r.id]
    bot.jump_to_room(ri - 1)
    local jobs, cur = {}, nil          -- job records
    local last, open = {}, {}
    local frames, busy, phf = 0, 0, {}
    local long, eps = {}, {}
    local function tick(buttons, n)
      for _ = 1, n do
        hush.hold(buttons, 1)
        local now = hush.frame()
        if rd(0x10) ~= 7 or rd(0x11) ~= 0 or rl(0xE740) ~= 1 then
          for s = 0, 7 do open[s] = nil; last[s] = nil end
          cur = nil
        else
          frames = frames + 1
          local j, ph = rl(0xE770), rl(0xE771)
          if j ~= 0xFF then busy = busy + 1; phf[ph] = (phf[ph] or 0) + 1 end
          -- job tracking
          local js = jsig()
          if cur and not cur.t1 and (j ~= cur.slot or (js ~= cur.sig0 and rl(0xE7FF) == 0)) then
            cur.t1 = now                       -- ended (a new job may already run in the same frame)
            cur.stale = (sigc(cur.slot) ~= live_sig(cur.slot))
          end
          if j ~= 0xFF and (not cur or cur.t1) then
            cur = { slot = j, sig0 = js, t0 = now, ph = {}, rst = 0, cls = rl(0xE76C) }
            jobs[#jobs + 1] = cur
          end
          if cur and not cur.t1 then
            cur.ph[ph] = (cur.ph[ph] or 0) + 1
            if rl(0xE7FF) == 1 then cur.rst = 1; cur.sig0 = js end
          end
          local shown = rl(0x1DC18) == 0xFF and rl(0x1DBC0) == 0xFF and (rl16(0xE742) & 0x3FFF) == 0
          local amb, dirty = rl(0x1DBC0) ~= 0xFF, (rl16(0xE742) & 0x3FFF) ~= 0
          local gch = (amb and dirty) and "B" or (amb and "A") or (dirty and "D") or ((j ~= 0xFF and ph == 2) and "c") or (j ~= 0xFF and "w") or "_"
          for s = 0, 7 do
            local lv = live_sig(s)
            local changed = last[s] and lv ~= last[s]
            if changed then
              open[s] = open[s] or { t0 = now, n = 0, tl = {}, gl = {} }
              open[s].n = open[s].n + 1
              open[s].sig = lv
            end
            last[s] = lv
            local o = open[s]
            if o and not o.tc and sigc(s) == o.sig and j ~= s then o.tc = now end
            if o and o.tc and sigc(s) ~= o.sig then o.tc = nil end
            if o then
              o.tl[#o.tl + 1] = changed and "L" or (j == s and "j") or (o.tc and "c") or "."
              o.gl[#o.gl + 1] = gch
            end
            if o and o.tc then
              if shown then
                eps[#eps + 1] = now - o.t0
                if o.tc - o.t0 > LONG then long[#long + 1] = { s = s, t0 = o.t0, tc = o.tc, t1 = now, n = o.n, tl = table.concat(o.tl), gl = table.concat(o.gl) } end
                open[s] = nil
              end
            end
          end
        end
      end
    end
    tick({}, 40)
    for t = 1, 24 do
      tick(moves[(t // 6) % 4 + 1], 10)
      if r.id == "r05" and t == 8 then
        local gx, gy = rd(0x0D10) + 256 * rd(0x0D30), rd(0x0D00) + 256 * rd(0x0D20)
        bot.poke(0x7EC908, (gx - 40) & 0xFF); bot.poke(0x7EC909, (gx - 40) >> 8)
        bot.poke(0x7EC90A, (gy + 8) & 0xFF); bot.poke(0x7EC90B, (gy + 8) >> 8)
        bot.poke(0x7EC90C, 200); bot.poke(0x7EC90D, 0)
        tick({}, 2)
      end
      local w0 = hush.frame()
      while not (rd(0x10) == 7 and rd(0x11) == 0 and rl(0xE7F6) == 1) do
        if rd(0x10) ~= 7 or rd(0x11) ~= 0 then w0 = hush.frame() end
        if hush.frame() - w0 > 1200 then break end
        tick({}, 1)
      end
    end
    -- per-room job stats
    local dur, cnt, stale, byc = {}, 0, 0, {}
    for _, jb in ipairs(jobs) do
      if jb.t1 then
        cnt = cnt + 1
        dur[#dur + 1] = jb.t1 - jb.t0
        if jb.stale then stale = stale + 1 end
        byc[jb.cls] = (byc[jb.cls] or 0) + 1
      end
    end
    table.sort(dur)
    local function q(p) return #dur > 0 and dur[math.max(1, math.ceil(p * #dur))] or 0 end
    local cs = {}
    for c, n in pairs(byc) do cs[#cs + 1] = c .. ":" .. n end
    table.sort(cs)
    table.sort(eps)
    local function qe(p) return #eps > 0 and eps[math.max(1, math.ceil(p * #eps))] or 0 end
    summary[#summary + 1] = string.format("%s catch-up (change -> shown) med %d p90 %d max %d over %d episodes; jobs %d (class %s) frames/job med %d p90 %d max %d, stale at commit %d, busy %d/%d frames, ph0/1/2 %d/%d/%d",
      r.id, qe(0.5), qe(0.9), qe(1), #eps, cnt, table.concat(cs, " "), q(0.5), q(0.9), q(1), stale, busy, frames, phf[0] or 0, phf[1] or 0, phf[2] or 0)
    if log then
      for _, e in ipairs(long) do
        local parts = {}
        for _, jb in ipairs(jobs) do
          if jb.t0 <= e.tc and (jb.t1 or 1e9) >= e.t0 then
            parts[#parts + 1] = string.format("[s%d c%d %d-%s ph%d/%d/%d%s%s]", jb.slot, jb.cls, jb.t0 - e.t0, jb.t1 and (jb.t1 - e.t0) or "?",
              jb.ph[0] or 0, jb.ph[1] or 0, jb.ph[2] or 0, jb.rst > 0 and " rst" or "", jb.stale and " STALE" or "")
          end
        end
        hush.log(string.format("%s slot %d episode: commit after %d, shown after %d, %d live changes; jobs (frames from the change): %s",
          r.id, e.s, e.tc - e.t0, e.t1 - e.t0, e.n, table.concat(parts, " ")))
        hush.log("  slot   (L live change, j its job, c committed = live, . stale): " .. e.tl)
        hush.log("  global (A amber tiles pending, D dirty rows, B both; else c commit / w clear-wedges with nothing pending, _ idle): " .. e.gl)
      end
    end
  end
  for _, l in ipairs(summary) do hush.log(l) end
  hush.pass()
end)
