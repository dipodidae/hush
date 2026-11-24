-- Dev probe (engine, E rev5; measurement + self-check, not a test): design/lighting.md revision 5 (every carrier displaced).
--   .venv/bin/python tools/run_test.py src/dev/e5_probe.lua          (ROOMS=0,12,18,20 0-based subset; LEG=75; CHECKS=6)
-- Per room: jump, 30 frames, walk left / up / right / down LEG frames each (the c5 / d4 walk), then CHECKS times: 10 frames of walking,
-- wait for light_done (<= 400 frames) and compare every BG1 tile with the rev 5 oracle (amber = max over guards g of V_g: the 4.1 lattice
-- of g's committed map (light_gmap) displaced by its rendered d (light_l3car), violet = the glow displaced; LUTs from build/rooms_gen.lua),
-- plus every carrier's rendered d vs 4.5 item 2 (centre = sprite origin + (8, 8) for guards, Link (x + 8, y + 16); clamp 16, D = 1).
-- Rates (walk part only):
--   guard renders: a guard is "rendered" at the end of an amber pass (Hush_L3ARow_end) whose snapshot changed its drawn position
--   (16 cx + 8 + RDX, ...); "render frames" = frames from the first frame its centre moved after its last render to the next render
--   (= frames between renders while it keeps moving; still carriers and carriers without light are not counted; open at the walk end
--   included).
--   glow renders: Hush_L3GRun_end / _same as d4_probe. lag px: mean |wanted - rendered| over frames x carriers with a lattice cell
--   (wanted = the carrier's centre, unclamped). clamp %: frames x carriers with |RDX| or |RDY| = 16. lag frames: frames without a main
--   loop end ($00805D). busy: SA-1 lines per frame (Hush_LightJob .. _done).
-- @timeout 2400
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local function rd(a) return emu.read(a, SNES, false) end
local function rdw(a) return rd(a) + 256 * rd(a + 1) end
local function sb(v) if v >= 128 then return v - 256 end return v end
local function sw(v) if v >= 32768 then return v - 65536 end return v end
local function cfg(k) local c = rawget(_G, "HUSH_PROBE_CFG"); return (c and c[k]) or os.getenv(k) end   -- wrappers (e5_quick.lua) set it
local LEG = tonumber(cfg("LEG") or "75")
local NCHK = tonumber(cfg("CHECKS") or "24")
local CAR, CELL, RDX, RDY, WDX, WDY = 0x41C700, 0x41C700, 0x41C710, 0x41C720, 0x41C730, 0x41C740
local GMAP, TILES, DONE, SIGC = 0x40D180, 0x40DA40, 0x40E7F6, 0x40E748
local VIO = 0x40D960

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
local function stats(t)
  if #t == 0 then return { n = 0, mean = 0, med = 0, p90 = 0, max = 0 } end
  local s, sum = {}, 0
  for i, v in ipairs(t) do s[i] = v; sum = sum + v end
  table.sort(s)
  return { n = #s, mean = sum / #s, med = s[#s // 2 + 1], p90 = s[math.min(#s, math.floor(#s * 0.9) + 1)], max = s[#s] }
end

-- 4.1 lattice (exact integers, as tests/smoke/lighting.lua) and 4.5 item 3
local PTS = {}
do
  local function add(t, cx, cy) if cx >= 0 and cx <= 15 and cy >= 0 and cy <= 13 then t[#t + 1] = cy * 16 + cx end end
  for j = 0, 28 do for i = 0, 32 do
    local t
    if i % 2 == 1 and j % 2 == 1 then t = { 1 }; add(t, (i - 1) // 2, (j - 1) // 2)
    elseif i % 2 == 1 then t = { 2 }; add(t, (i - 1) // 2, j // 2 - 1); add(t, (i - 1) // 2, j // 2)
    elseif j % 2 == 1 then t = { 2 }; add(t, i // 2 - 1, (j - 1) // 2); add(t, i // 2, (j - 1) // 2)
    else t = { 4 }; add(t, i // 2 - 1, j // 2 - 1); add(t, i // 2, j // 2 - 1); add(t, i // 2 - 1, j // 2); add(t, i // 2, j // 2) end
    PTS[j * 33 + i] = t
  end end
end
local function lattice(map, vmax, n)
  local lev = {}
  for p = 0, 33 * 29 - 1 do
    local t = PTS[p]
    local sum = 0
    for k = 2, #t do sum = sum + map[t[k]] end
    lev[p] = (2 * sum * (n - 1) + vmax * t[1]) // (2 * vmax * t[1])
  end
  return lev
end
local function displace(l, dx, dy)
  if dx == 0 and dy == 0 then return l end
  local H, V = {}, {}
  for j = 0, 28 do
    for i = 0, 32 do
      local X = 8 * i - dx
      local i0, t = X // 8, X % 8
      local a = (i0 >= 0 and i0 <= 32) and l[j * 33 + i0] or 0
      local b = (i0 + 1 >= 0 and i0 + 1 <= 32) and l[j * 33 + i0 + 1] or 0
      H[j * 33 + i] = ((8 - t) * a + t * b + 4) // 8
    end
  end
  for j = 0, 28 do
    local Y = 8 * j - dy
    local j0, s = Y // 8, Y % 8
    for i = 0, 32 do
      local a = (j0 >= 0 and j0 <= 28) and H[j0 * 33 + i] or 0
      local b = (j0 + 1 >= 0 and j0 + 1 <= 28) and H[(j0 + 1) * 33 + i] or 0
      V[j * 33 + i] = ((8 - s) * a + s * b + 4) // 8
    end
  end
  return V
end
local function want_d(v) v = math.max(-16, math.min(16, v)); return v end   -- D = 1

-- carrier centre (unclamped, room px) and its cell
local function centre(c)
  if c == 8 then return sw((rdw(0x7E0022) + 8 - rdw(0x7E00E2)) & 0xFFFF), sw((rdw(0x7E0020) + 16 - rdw(0x7E00E8)) & 0xFFFF) end
  return sw((rd(0x7E0D10 + c) + 256 * rd(0x7E0D30 + c) + 8 - rdw(0x7E00E2)) & 0xFFFF),
         sw((rd(0x7E0D00 + c) + 256 * rd(0x7E0D20 + c) + 8 - rdw(0x7E00E8)) & 0xFFFF)
end
local function rendered(c)
  local cl = rd(CELL + c)
  if cl == 0xFF then return nil end
  return 16 * (cl & 15) + 8 + sb(rd(RDX + c)), 16 * (cl >> 4) + 8 + sb(rd(RDY + c))
end

-- catch-up (design/lighting.md section 5), episodes as tests/smoke/lighting.lua (live signature changes to S; closes at the first frame
-- where the light drawn in VRAM for that guard is S or a later signature of that slot), "drawn in VRAM" tracked per guard through the
-- pipeline (SA-1 exec callbacks): RS = its signature at the end of the last amber pass that included its current lattice
-- (Hush_L3ARow_end, slot not marked); TS = RS once no pass runs and no amber tile row is pending (at every Hush_LightPub); PS = TS at a
-- publication (Hush_LightPub_publish); SH (shown) = PS when that publication is retired (uploaded; Hush_LightPub_retire), or TS
-- directly when nothing is published or pending (light_tiles = VRAM).
local RS, TS, PS, SH = {}, {}, {}, {}
local function live_sig(s)
  local st, typ, aw = rd(0x7E0DD0 + s), rd(0x7E0E20 + s), rd(0x7E0D80 + s)
  if st ~= 9 or typ ~= 0x41 or aw >= 3 then return { 0, 0, 0 } end
  local x = rd(0x7E0D10 + s) + 256 * rd(0x7E0D30 + s) + 8 - rdw(0x7E00E2)
  local y = rd(0x7E0D00 + s) + 256 * rd(0x7E0D20 + s) + 8 - rdw(0x7E00E8)
  if x < 0 or x >= 256 or y < 0 or y >= 224 then return { 0, 0, 0 } end
  local cls = aw + 1
  return { cls, cls == 1 and (rd(0x7E0DE0 + s) & 3) or 0, (y // 16 + 8) * 32 + x // 16 + 8 }
end
local function sigc(s) return { rd(SIGC + 4 * s), rd(SIGC + 4 * s + 1), rdw(SIGC + 4 * s + 2) } end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
local function new_cu()
  local cu = { open = {}, last = {}, epi = {} }
  for s = 0, 7 do cu.last[s] = { -1, -1, -1 }; cu.open[s] = {} end
  return cu
end
local function cu_tick(cu)
  if rd(0x7E0010) ~= 7 or rd(0x7E0011) ~= 0 then
    for s = 0, 7 do cu.open[s] = {}; cu.last[s] = { -1, -1, -1 } end
    return
  end
  local now, job = hush.frame(), rd(0x40E770)
  for s = 0, 7 do
    local lv = live_sig(s)
    local list = cu.open[s]
    if not same(lv, cu.last[s]) then
      if cu.last[s][1] ~= -1 then list[#list + 1] = { t0 = now, sig = lv } end
      cu.last[s] = lv
    end
    if #list > 0 and job ~= s and SH[s] then
      local k = 0
      for i = #list, 1, -1 do if same(SH[s], list[i].sig) then k = i; break end end
      if k > 0 then
        for i = 1, k do cu.epi[#cu.epi + 1] = now - list[i].t0 end
        local rest = {}
        for i = k + 1, #list do rest[#rest + 1] = list[i] end
        cu.open[s] = rest
      end
    end
  end
end

hush.test("e5 probe", function()
  local m = bot.rooms()
  local lt = m.light
  local cbs = {}
  local function on(addr, f, cpu)
    local ref
    if cpu then ref = emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr, emu.cpuType.sa1, emu.memType.sa1Memory)
    else ref = emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr) end
    cbs[#cbs + 1] = { ref, addr, cpu }
  end
  local on_, R = false, nil
  local function clk() return emu.getState()["masterClock"] end
  on(0x00805D, function() if on_ then R.ends = R.ends + 1 end end)
  local j0
  on(sym("Hush_LightJob"), function() j0 = clk() end, true)
  on(sym("Hush_LightJob_done"), function()
    if on_ and j0 then local f = hush.frame(); R.busy[f] = (R.busy[f] or 0) + (clk() - j0) / 1364 end
    j0 = nil
  end, true)
  local function render(c)                 -- carrier c's drawn position may have changed: a render event if it did
    if not on_ then return end
    local x, y = rendered(c)
    local key = x and (x .. "," .. y) or "none"
    if R.dkey[c] ~= key then
      R.dkey[c] = key
      if R.moved[c] then local iv = hush.frame() - R.moved[c]; local t = c == 8 and R.giv or R.iv; t[#t + 1] = iv end
      R.last[c] = hush.frame(); R.moved[c] = false
    end
  end
  on(sym("Hush_L3ARow_end"), function() for c = 0, 7 do render(c) end end, true)
  on(sym("Hush_L3ARow_end"), function()
    local rdm = rdw(0x41C7E8)
    for g = 0, 7 do if rdm & (1 << g) == 0 then RS[g] = sigc(g) end end
  end, true)
  on(sym("Hush_LightPub"), function()
    if rd(0x413D00) == 0 and rd(0x41DBC0) == 0xFF then
      for g = 0, 7 do TS[g] = RS[g] end
      if rd(0x00300A) == 0 and rdw(0x40E746) == 0 and rdw(0x40E744) == 0 then for g = 0, 7 do SH[g] = TS[g] end end
    end
  end, true)
  on(sym("Hush_LightPub_publish"), function() for g = 0, 7 do PS[g] = TS[g] end end, true)
  on(sym("Hush_LightPub_retire"), function() for g = 0, 7 do SH[g] = PS[g] end end, true)
  on(sym("Hush_L3GRun_end"), function() render(8) end, true)
  on(sym("Hush_L3GRun_same"), function() render(8) end, true)

  bot.start_new_game()
  local out, bad_total, chk_total, tiles_total = {}, 0, 0, 0
  local only = cfg("ROOMS")
  for ri = 1, m.count do
    local id = m.rooms[ri].id
    if only and not ("," .. only .. ","):find("," .. (ri - 1) .. ",", 1, true) then goto skip end
    on_ = false
    for g = 0, 7 do RS[g], TS[g], PS[g], SH[g] = nil, nil, nil, nil end
    bot.jump_to_room(ri - 1)
    hush.wait(30)
    R = { ends = 0, busy = {}, iv = {}, giv = {}, last = {}, moved = {}, dkey = {}, lag = {}, glag = {}, clamp = 0, cf = 0, pos = {} }
    for c = 0, 8 do R.last[c] = hush.frame(); R.moved[c] = false; local x, y = rendered(c); R.dkey[c] = x and (x .. "," .. y) or "none" end
    local f0 = hush.frame()
    local cu = new_cu()
    on_ = true
    for _, b in ipairs({ "left", "up", "right", "down" }) do
      for _ = 1, LEG do
        hush.hold({ b }, 1)
        cu_tick(cu)
        for c = 0, 8 do
          local px, py = centre(c)
          local k = px .. "," .. py
          if R.pos[c] and R.pos[c] ~= k and rd(CELL + c) ~= 0xFF and not R.moved[c] then R.moved[c] = hush.frame() end   -- (no light: nothing to render)
          R.pos[c] = k
          local rx, ry = rendered(c)
          if rx then
            local d = math.sqrt((px - rx) ^ 2 + (py - ry) ^ 2)
            local t = c == 8 and R.glag or R.lag
            t[#t + 1] = d
            R.cf = R.cf + 1
            if math.abs(sb(rd(RDX + c))) == 16 or math.abs(sb(rd(RDY + c))) == 16 then R.clamp = R.clamp + 1 end
          end
        end
      end
    end
    on_ = false
    for c = 0, 8 do if R.moved[c] then local t = c == 8 and R.giv or R.iv; t[#t + 1] = hush.frame() - R.moved[c] end end
    local nf = hush.frame() - f0
    local bl = {}
    for f = f0 + 1, f0 + nf do bl[#bl + 1] = R.busy[f] or 0 end
    -- oracle checks
    local bad, chk, maxwait, msgs, nodone = 0, 0, 0, {}, 0
    for k = 1, NCHK do
      for _ = 1, 10 do hush.hold({ ({ "left", "up", "right", "down" })[(k // 6) % 4 + 1] }, 1); cu_tick(cu) end
      local w0 = hush.frame()
      while not (rd(0x7E0010) == 7 and rd(0x7E0011) == 0 and rd(DONE) == 1) and hush.frame() - w0 < 400 do hush.wait(1); cu_tick(cu) end
      if rd(DONE) ~= 1 then nodone = nodone + 1; goto nextk end
      maxwait = math.max(maxwait, hush.frame() - w0)
      do
        chk = chk + 1
        local amb = {}
        for p = 0, 33 * 29 - 1 do amb[p] = 0 end
        for g = 0, 7 do
          local map = {}
          local any = false
          for i = 0, 223 do map[i] = rd(GMAP + 224 * g + i); if map[i] > 0 then any = true end end
          local cl, dx, dy = rd(CELL + g), sb(rd(RDX + g)), sb(rd(RDY + g))
          if cl ~= 0xFF then
            local sg = rdw(SIGC + 4 * g + 2)
            local ccx, ccy = (sg % 32) - 8, (sg // 32) - 8
            if rd(SIGC + 4 * g) ~= 0 and cl ~= ccy * 16 + ccx then msgs[#msgs + 1] = string.format("g%d cell %02X vs sigc (%d,%d)", g, cl, ccx, ccy); bad = bad + 1 end
            local px, py = centre(g)
            local ex, ey = want_d(px - (16 * (cl & 15) + 8)), want_d(py - (16 * (cl >> 4) + 8))
            if ex ~= dx or ey ~= dy then msgs[#msgs + 1] = string.format("g%d rendered d (%d,%d) want (%d,%d)", g, dx, dy, ex, ey); bad = bad + 1 end
          else
            dx, dy = 0, 0
            if any then msgs[#msgs + 1] = string.format("g%d has light but no lattice cell", g); bad = bad + 1 end
          end
          if any then
            local V = displace(lattice(map, 6, lt.n), dx, dy)
            for p = 0, 33 * 29 - 1 do if V[p] > amb[p] then amb[p] = V[p] end end
          end
        end
        local vio = {}
        for i = 0, 223 do vio[i] = rd(VIO + i) end
        local c8, vdx, vdy = rd(CELL + 8), sb(rd(RDX + 8)), sb(rd(RDY + 8))
        if c8 == 0xFF then vdx, vdy = 0, 0 end
        local vlt = displace(lattice(vio, 2, lt.nv), vdx, vdy)
        for ty = 0, 27 do for tx = 0, 31 do
          local p = ty * 33 + tx
          local a, b, c, d = amb[p], amb[p + 1], amb[p + 33], amb[p + 34]
          local ew
          if a + b + c + d > 0 then ew = lt.lut_amber[((a * lt.n + b) * lt.n + c) * lt.n + d + 1]
          else
            a, b, c, d = vlt[p], vlt[p + 1], vlt[p + 33], vlt[p + 34]
            ew = lt.lut_violet[((a * lt.nv + b) * lt.nv + c) * lt.nv + d + 1]
          end
          local w = rdw(TILES + ty * 64 + tx * 2)
          tiles_total = tiles_total + 1
          if w ~= ew then
            bad = bad + 1
            if #msgs < 4 then msgs[#msgs + 1] = string.format("tile (%d,%d) %04X want %04X corners %d %d %d %d", tx, ty, w, ew, a, b, c, d) end
          end
        end end
      end
      ::nextk::
    end
    bad_total, chk_total = bad_total + bad, chk_total + chk
    local il, gl, lg, gg, b = stats(R.iv), stats(R.giv), stats(R.lag), stats(R.glag), stats(bl)
    for s = 0, 7 do for _, o in ipairs(cu.open[s]) do local a = hush.frame() - o.t0; if a > 90 then cu.epi[#cu.epi + 1] = a end end end
    local ce = stats(cu.epi)
    local function near(p) if ce.n == 0 then return "-" end local s = {} for i, v in ipairs(cu.epi) do s[i] = v end table.sort(s) return s[math.max(1, math.ceil(p * #s))] end
    local row = string.format("| %s | %d/%d/%d (%d) | %.1f | %d/%d/%d (%d) | %.1f | %.1f %% | %d | %.0f / %.0f | %s/%s/%s (%d) | %d checks, %d bad, wait max %d, %d waits > 400 |", id,
      il.med, il.p90, il.max, il.n, lg.mean, gl.med, gl.p90, gl.max, gl.n, gg.mean, R.cf == 0 and 0 or 100 * R.clamp / R.cf,
      nf - R.ends, b.mean, b.max, near(0.5), near(0.9), ce.n == 0 and "-" or ce.max, ce.n, chk, bad, maxwait, nodone)
    out[#out + 1] = row
    hush.log(row)
    for _, s in ipairs(msgs) do hush.log("  " .. id .. ": " .. s) end
    ::skip::
  end
  hush.log("| room | guard render frames med/p90/max (n) | guard lag px | glow render frames med/p90/max (n) | glow lag px | at clamp | lag frames | SA-1 busy lines/frame mean / max | catch-up (per guard) med/p90/max (n) | rev 5 oracle |")
  hush.log("|---|---|---|---|---|---|---|---|---|---|")
  for _, r in ipairs(out) do hush.log(r) end
  for _, cb in ipairs(cbs) do
    if cb[3] then emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2], emu.cpuType.sa1, emu.memType.sa1Memory)
    else emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  end
  if bad_total > 0 then hush.fail(string.format("%d mismatches in %d checks (%d tiles)", bad_total, chk_total, tiles_total)) return end
  hush.pass(string.format("%d checks, %d tiles, 0 mismatches", chk_total, tiles_total))
end)
