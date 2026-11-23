-- Dev probe (a MEASUREMENT, not a test): how long a guard's lantern light lags behind the guard (design/lighting.md, L1).
-- @timeout 240
--   .venv/bin/python tools/run_test.py tests/dev/light_latency.lua
-- Rooms are hard-coded (ROOMS below, no env vars): r19 and final (5-6 guards, the heavy ones), r13 as a calm reference.
-- Per room: jump in, Link stands still for FRAMES frames. Every frame, per guard slot:
--   * live signature (class, facing, padded cell), computed exactly like tests/smoke/lighting.lua live_sig();
--   * a CHANGE = the live signature differs from the previous frame's. It is open until the first later frame where
--     (a) the slot's committed signature `light_sigc` equals it AND (b) nothing is left to render / upload:
--         `light_dirty` == 0 (bits 0-13 rows waiting for the NMI, bit 15 render pending), every `light_tdirty` byte 0,
--         and the worker (`light_job` + 8) is neither $FE (render pending) nor running a job for this very slot.
--     latency = that frame - the change frame. A change replaced by a newer one before it resolved is counted as SUPERSEDED
--     (no latency; the newer change carries on).
--   * stale EPISODE = from the first change of a slot that is not yet resolved (kept across supersedes) to the frame it resolves:
--     how long the player actually sees an out-of-date light for that guard. "open ep age@end" = age of an episode still open at the end.
--   * out-of-date frame = a frame where some slot has an open change (or, at room entry, a committed signature that is not
--     yet the live one: those "initial" items count for the fraction but not for the latency stats).
-- Frames outside player control (caught -> restart, transitions) are not measured; open items are dropped and the count is logged.
-- Ends with hush.pass(<summary>) only after the measurement; it asserts only that something was measured.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local ROOMS = { "r13", "r19", "final" }
local FRAMES = 600

local W = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, W, false) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local L = {}
local function init_L()
  local function ram(name) local e = hush.ram[name]; if not e then hush.fail("docs/ram_map.md has no row " .. name) end; return e.addr end
  L = { SIGC = ram("light_sigc"), DIRTY = ram("light_dirty"), JOB = ram("light_job") + 8, TDIRTY = ram("light_tdirty"), ON = ram("light_on") }
end

-- same as tests/smoke/lighting.lua live_sig()
local function live_sig(s)
  local st, typ, aw = rd(0x0DD0 + s), rd(0x0E20 + s), rd(0x0D80 + s)
  if st ~= 9 or typ ~= 0x41 or aw >= 3 then return { 0, 0, 0 } end
  local x = rd(0x0D10 + s) + 256 * rd(0x0D30 + s) + 8 - rd16(0xE2)
  local y = rd(0x0D00 + s) + 256 * rd(0x0D20 + s) + 8 - rd16(0xE8)
  if x < 0 or x >= 256 or y < 0 or y >= 224 then return { 0, 0, 0 } end
  local cls = aw + 1
  return { cls, cls == 1 and (rd(0x0DE0 + s) & 3) or 0, (y // 16 + 8) * 32 + x // 16 + 8 }
end
local function sigc(s) return { rd(L.SIGC + 4 * s), rd(L.SIGC + 4 * s + 1), rd16(L.SIGC + 4 * s + 2) } end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

local function render_idle()
  if rd16(L.DIRTY) ~= 0 then return false end
  for i = 0, 111 do if rd(L.TDIRTY + i) ~= 0 then return false end end
  return rd(L.JOB) ~= 0xFE
end

local function pct(sorted, p)            -- nearest rank
  if #sorted == 0 then return nil end
  local k = math.max(1, math.ceil(p * #sorted))
  return sorted[k]
end
local function fmt(v) return v and tostring(v) or "-" end

local function measure(id, idx)
  bot.jump_to_room(idx)
  hush.wait(2)
  local open, last = {}, {}               -- slot -> { t = change frame, sig = live sig, initial = bool }; slot -> last live sig
  local lat, sup, stale, measured, skipped, drops, guards = {}, 0, 0, 0, 0, 0, {}
  local epi = {}                          -- stale episodes: first unresolved change (t0, kept across supersedes) -> caught up
  local f0 = hush.frame()
  for s = 0, 7 do
    last[s] = live_sig(s)
    if last[s][1] ~= 0 then guards[s] = true end
    if not (same(sigc(s), last[s]) and render_idle()) then open[s] = { t = f0, sig = last[s], initial = true } end
  end
  for _ = 1, FRAMES do
    hush.wait(1)
    if rd(0x10) ~= 7 or rd(0x11) ~= 0 or rd(L.ON) ~= 1 then
      skipped = skipped + 1
      for s = 0, 7 do if open[s] then drops = drops + 1; open[s] = nil end; last[s] = { -1, -1, -1 } end
      goto continue
    end
    do
      local now, idle, job = hush.frame(), render_idle(), rd(L.JOB)
      local any = false
      for s = 0, 7 do
        local lv = live_sig(s)
        if lv[1] ~= 0 then guards[s] = true end
        if not same(lv, last[s]) then
          if last[s][1] ~= -1 then          -- not the first frame after a skipped stretch
            local t0 = now
            if open[s] then t0 = open[s].t0 or now; if not open[s].initial then sup = sup + 1 end end
            open[s] = { t = now, t0 = t0, sig = lv }
          elseif not (same(sigc(s), lv) and idle) then
            open[s] = { t = now, sig = lv, initial = true }
          end
          last[s] = lv
        end
        local o = open[s]
        if o and same(sigc(s), o.sig) and idle and job ~= s then
          if not o.initial then lat[#lat + 1] = now - o.t end
          if o.t0 then epi[#epi + 1] = now - o.t0 end
          open[s] = nil
        end
        if open[s] then any = true end
      end
      measured = measured + 1
      if any then stale = stale + 1 end
    end
    ::continue::
  end
  local unresolved = 0
  for s = 0, 7 do if open[s] and not open[s].initial then unresolved = unresolved + 1 end end
  local ng = 0
  for _ in pairs(guards) do ng = ng + 1 end
  local oldest = 0                         -- age of a still-open episode at the end (a lower bound of its length)
  for s = 0, 7 do if open[s] and open[s].t0 then oldest = math.max(oldest, hush.frame() - open[s].t0) end end
  table.sort(lat); table.sort(epi)
  local r = { id = id, guards = ng, changes = #lat + sup + unresolved, done = #lat, sup = sup, unres = unresolved,
              med = pct(lat, 0.5), p90 = pct(lat, 0.9), max = lat[#lat], stale = stale, measured = measured,
              skipped = skipped, drops = drops, ne = #epi, emed = pct(epi, 0.5), ep90 = pct(epi, 0.9), emax = epi[#epi], oldest = oldest }
  hush.log(string.format("%s: guards=%d changes=%d resolved=%d superseded=%d unresolved=%d lat med/p90/max=%s/%s/%s stale %d/%d skipped=%d dropped=%d",
    id, ng, r.changes, r.done, sup, unresolved, fmt(r.med), fmt(r.p90), fmt(r.max), stale, measured, skipped, drops))
  return r
end

hush.test("light latency probe (dev measurement)", function()
  init_L()
  local m = bot.rooms()
  bot.start_new_game()
  local res = {}
  for _, id in ipairs(ROOMS) do
    local idx
    for i, r in ipairs(m.rooms) do if r.id == id then idx = i - 1 end end
    hush.assert(idx, "room " .. id .. " not in build/rooms_gen.lua")
    res[#res + 1] = measure(id, idx)
  end
  hush.log("")
  hush.log("| room | guards | changes | resolved | superseded | unresolved@end | median | p90 | max | episodes | ep median | ep p90 | ep max | open ep age@end | out-of-date frames | skipped frames |")
  hush.log("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
  local total = 0
  for _, r in ipairs(res) do
    total = total + r.measured
    hush.log(string.format("| %s | %d | %d | %d | %d | %d | %s | %s | %s | %d | %s | %s | %s | %d | %d/%d = %.1f %% | %d |", r.id, r.guards, r.changes, r.done, r.sup, r.unres,
      fmt(r.med), fmt(r.p90), fmt(r.max), r.ne, fmt(r.emed), fmt(r.ep90), fmt(r.emax), r.oldest,
      r.stale, r.measured, r.measured > 0 and 100 * r.stale / r.measured or 0, r.skipped))
  end
  hush.assert_gt(total, 0, "measured frames")
  hush.pass("light latency measured for " .. table.concat(ROOMS, ", "))
end)
