-- Dev probe (engine, L3 C5; measurement only, not a test): per room r01..r20 + final, while walking left / up / right / down 75 frames
-- each: guards, region renders per second, per carrier class (guards 0-7 / glow 8) frames between re-renders while it moves and the mean
-- |wanted - rendered| light position in px, spare light lines, lag frames, region size (lattice points) and cycles per region.
--   .venv/bin/python tools/run_test.py src/dev/c5_probe.lua
-- Definitions:
--   wanted W = the carrier centre as Hush_L3Want sees it, unclamped: guard (x - $E2, y - $E8) from $0D10/$0D30, $0D00/$0D20; glow
--     ($22 - $E2, $20 + 8 - $E8). Rendered R = (16cx + RDX, 16cy + RDY) snapshotted when Hush_L3List runs (pick of a non-empty region,
--     CELL / RDX / RDY just set) and made "drawn" when that region ends (RegStep `.end`: LDA #$FF : STA.l L3_RC, found by byte scan).
--   lag px = Euclidean |W - R| per frame per carrier with a lattice (CELL != $FF), averaged over carrier-frames.
--   re-render interval = frames between two region ends of the same carrier, kept only if the carrier moved (W changed) in between; the
--     open interval from the walk start / to the walk end is included when it moved (a lower bound).
--   region cycles = Hush_L3Pick entry -> unit end (the pick unit) + Hush_L3RegStep .row -> unit end for each of its row units.
-- @timeout 1500
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local SNES = emu.memType.snesMemory
local VMAX, LEG = 200, tonumber(os.getenv("LEG") or "75")
local DBG = false                                -- per-carrier end-of-walk dump

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
local function find_jsr(from, to, target)
  for p = from, to - 3 do if rd(p) == 0x20 and rdw(p + 1) == (target & 0xFFFF) then return p end end
  error(string.format("no JSR %06X in %06X-%06X", target, from, to))
end
local function find_bytes(from, to, bytes)
  for p = from, to - #bytes do
    local ok = true
    for k, b in ipairs(bytes) do if rd(p + k - 1) ~= b then ok = false; break end end
    if ok then return p end
  end
  error(string.format("pattern not found in %06X-%06X", from, to))
end
local function stats(t)
  if #t == 0 then return { n = 0, mean = 0, med = 0, p90 = 0, max = 0, min = 0 } end
  local s, sum = {}, 0
  for i, v in ipairs(t) do s[i] = v; sum = sum + v end
  table.sort(s)
  return { n = #s, mean = sum / #s, med = s[#s // 2 + 1], p90 = s[math.min(#s, math.floor(#s * 0.9) + 1)], max = s[#s], min = s[1] }
end

local CELL, RDX, RDY, RC = 0x7FC700, 0x7FC710, 0x7FC720, 0x7FC7E0
local RI0, RI1, RJA, RJB = RC + 2, RC + 3, RC + 4, RC + 5

hush.test("c5 probe", function()
  local LW, LW_UNIT, LW_OUT = sym("Hush_LightWork"), sym("Hush_LightWork_unit"), sym("Hush_LightWork_out")
  local UNIT, REG_ROW, PICK, LIST = sym("Hush_L3Unit"), sym("Hush_L3RegStep_row"), sym("Hush_L3Pick"), sym("Hush_L3List")
  local UNIT_RET = find_jsr(LW_UNIT, LW_UNIT + 8, UNIT) + 3
  local REG_END = find_bytes(REG_ROW, REG_ROW + 0x100, { 0xA9, 0xFF, 0x8F, RC & 0xFF, (RC >> 8) & 0xFF, RC >> 16 })
  hush.log(string.format("points: unit ret %06X, regstep .row %06X, region end %06X, pick %06X, list %06X", UNIT_RET, REG_ROW, REG_END, PICK, LIST))

  local function now() local s = emu.getState(); return s["cpu.cycleCount"], s["ppu.scanline"] end
  local function wanted(c)
    local ex, ey = rdw(0x7E00E2), rdw(0x7E00E8)
    if c == 8 then return sw((rdw(0x7E0022) - ex) & 0xFFFF), sw((rdw(0x7E0020) + 8 - ey) & 0xFFFF) end
    local x = rd(0x7E0D10 + c) + 256 * rd(0x7E0D30 + c)
    local y = rd(0x7E0D00 + c) + 256 * rd(0x7E0D20 + c)
    return sw((x - ex) & 0xFFFF), sw((y - ey) & 0xFFFF)
  end
  local function snap(c)                           -- rendered position implied by CELL / RDX / RDY now; nil without a lattice
    local cell = rd(CELL + c)
    if cell == 0xFF then return nil end
    return { x = 16 * (cell & 15) + sb(rd(RDX + c)), y = 16 * (cell >> 4) + sb(rd(RDY + c)) }
  end

  local on_ = false               -- measuring
  local R, unit, cur
  local cbs = {}
  local function on(addr, f) cbs[#cbs + 1] = { emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr), addr } end

  on(LW, function() if on_ then local _, l = now(); R.entry[#R.entry + 1] = l end end)
  on(LW_OUT, function() if on_ then R.lframes = R.lframes + 1 end end)
  on(LW_UNIT, function() unit = {} end)
  on(PICK, function() if unit then unit.p0 = now() end end)
  on(REG_ROW, function() if unit then unit.r0 = now() end end)
  on(LIST, function()
    local c = rd(RC)
    cur = { c = c, pos = snap(c), pts = (rd(RI1) - rd(RI0) + 1) * (rd(RJB) - rd(RJA) + 1), cyc = 0 }
    if unit then unit.listed = true end
  end)
  on(REG_END, function() if cur then cur.ending = true end end)
  on(UNIT_RET, function()
    if not unit then return end
    local c = now()
    if cur then
      if unit.listed and unit.p0 then cur.cyc = cur.cyc + (c - unit.p0)
      elseif unit.r0 then cur.cyc = cur.cyc + (c - unit.r0) end
      if cur.ending then
        if on_ then
          R.nreg = R.nreg + 1
          R.pts[#R.pts + 1] = cur.pts
          R.cyc[#R.cyc + 1] = cur.cyc
          local k = cur.c
          if cur.pos then R.drawn[k] = cur.pos end
          local t = (k == 8) and R.ivg or R.ivgd
          if R.moved[k] then t[#t + 1] = hush.frame() - R.last[k] end
          R.last[k] = hush.frame(); R.moved[k] = false
        end
        cur = nil
      end
    end
    unit = nil
  end)

  local m = bot.rooms()
  bot.start_new_game()
  local rows = {}
  local only = os.getenv("ROOMS")                -- optional 0-based index list, default all
  for ri = 1, m.count do
    local id = m.rooms[ri].id
    if only and not ("," .. only .. ","):find("," .. (ri - 1) .. ",", 1, true) then goto skip end
    on_ = false
    bot.jump_to_room(ri - 1)
    hush.wait(30)
    R = { entry = {}, lframes = 0, nreg = 0, pts = {}, cyc = {}, drawn = {}, last = {}, moved = {}, prevw = {},
      ivg = {}, ivgd = {}, lagg = {}, lagl = {}, gfr = 0, undrawn = 0 }
    for c = 0, 8 do R.drawn[c] = snap(c); R.last[c] = hush.frame(); R.moved[c] = false end
    -- a region already running when the walk starts: its snapshot is unknown, so it is not counted
    cur = nil
    local f0 = hush.frame()
    on_ = true
    local function sample()
      for c = 0, 8 do
        local wx, wy = wanted(c)
        local p = R.prevw[c]
        if p and (p[1] ~= wx or p[2] ~= wy) then R.moved[c] = true end
        R.prevw[c] = { wx, wy }
        local d = R.drawn[c]
        if rd(CELL + c) ~= 0xFF and (c == 8 or rd(0x7E0DD0 + c) == 9) then
          if c < 8 then R.gfr = R.gfr + 1 end
          if d then
            local t = (c == 8) and R.lagl or R.lagg
            t[#t + 1] = math.sqrt((wx - d.x) ^ 2 + (wy - d.y) ^ 2)
          elseif c < 8 then
            R.undrawn = R.undrawn + 1                -- lattice built, no region of it has ended yet: its light is not on screen
          end
        end
      end
    end
    for _, b in ipairs({ "left", "up", "right", "down" }) do
      for _ = 1, LEG do hush.hold({ b }, 1); sample() end
    end
    on_ = false
    local nf = hush.frame() - f0
    for c = 0, 8 do                              -- open intervals at the walk end (lower bounds)
      if R.moved[c] and rd(CELL + c) ~= 0xFF and (c == 8 or rd(0x7E0DD0 + c) == 9) then local t = (c == 8) and R.ivg or R.ivgd; t[#t + 1] = hush.frame() - R.last[c] end
    end
    if DBG then
      for c = 0, 8 do
        local wx, wy = wanted(c)
        local d = R.drawn[c]
        hush.log(string.format("  %s c%d: cell %02X dd0 %d e20 %02X W(%d,%d) drawn %s RD(%d,%d) moved %s last %d", id, c, rd(CELL + c),
          bot.peek(0x7E0DD0 + c), bot.peek(0x7E0E20 + c), wx, wy, d and (d.x .. "," .. d.y) or "nil", sb(rd(RDX + c)), sb(rd(RDY + c)),
          tostring(R.moved[c]), R.last[c] - f0))
      end
    end
    local g = 0
    for s = 0, 15 do if bot.peek(0x7E0DD0 + s) == 9 and bot.peek(0x7E0E20 + s) == 0x41 then g = g + 1 end end
    local ig, il, sp = stats(R.ivgd), stats(R.ivg), {}
    for _, e in ipairs(R.entry) do sp[#sp + 1] = VMAX - e end
    local sps = stats(sp)
    local function iv(s) return s.n == 0 and "-" or string.format("%d / %d / %d", s.med, s.p90, s.max) end
    local function lg(t) return #t == 0 and "-" or string.format("%.1f", stats(t).mean) end
    local row = string.format("| %s | %d | %.1f | %s | %s | %s | %s | %s | %d / %d | %d | %d | %d |", id, g, R.nreg * 60 / nf,
      iv(ig), lg(R.lagg), R.gfr == 0 and "-" or string.format("%d %%", math.floor(100 * R.undrawn / R.gfr + 0.5)),
      iv(il), lg(R.lagl), sps.med, sps.min, nf - R.lframes, stats(R.pts).med, stats(R.cyc).med)
    rows[#rows + 1] = row
    hush.log(row)
    ::skip::
  end
  hush.log("| room | guards | regions / s | guard re-render frames med / p90 / max | guard lag px | guard-frames undrawn | glow re-render frames med / p90 / max | glow lag px | spare lines med / min | lag frames | region points med | region cyc med |")
  hush.log("|---|---|---|---|---|---|---|---|---|---|---|---|")
  for _, r in ipairs(rows) do hush.log(r) end
  for _, cb in ipairs(cbs) do emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  hush.pass()
end)
