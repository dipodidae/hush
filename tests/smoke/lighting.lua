-- Smoke (L1, design/lighting.md): lantern light = guard sight.
-- For every real room, while the guards patrol and Link walks, at many frames when the light engine is idle:
--   1. every guard slot's committed light map (GMAP) equals an independent oracle of design/lighting.md section 3 computed from the committed
--      signature (class, facing, cell), the collision map $7F2000 and the ink cloud (shape, range, falloff, cone edge, line of sight, faces);
--   2. the composite equals the max over the guards, the player glow follows design/lighting.md (cell 2, orthogonal neighbours 1, floor only);
--   3. the BG1 tile words equal the steps, and once no row is dirty, the BG1 window in VRAM equals them;
--   4. liveness: every committed signature catches up with the live guard (state, cell, facing) within 90 frames of a check;
--   5. colour math: BG1 on the sub screen ($1D bit 0), CGWSEL $02, CGADSUB $22; light colours in BG row 2.
-- @timeout 600
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W, V = emu.memType.snesWorkRam, emu.memType.snesVideoRam
local function rd(a) return emu.read(a, W, false) end            -- WRAM offset (bank $7E = 0..$FFFF, $7F = +$10000)
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local L = { SOL = 0xCA00, GMAP = 0xD180, COMP = 0xD880, VIO = 0xD960, TILES = 0xDA40, WORDS = 0xE714, ON = 0xE740, DIRTY = 0xE742,
            SIGC = 0xE748, JOB = 0xE770, LCELL = 0xE77E }   -- docs/ram_map.md "HUSH lighting"
local STEPS = { [5] = { 6, 6, 5, 4, 3, 2, 1 }, [8] = { 6, 6, 6, 5, 5, 4, 3, 3, 2, 1 } }   -- design/lighting.md section 3, index d + 1 (d = R + 1: the fringe)

local function step(cls, R, d, edge)
  local v = STEPS[R][d + 1] or 0
  if cls == 2 then v = math.min(v, 4) elseif cls == 3 and v > 0 then v = math.min(v + 1, 6) end
  if edge then v = v - 1 end
  return v
end
local function rnd(q)                    -- round half toward zero
  if q < 0 then return -rnd(-q) end
  local f = math.floor(q)
  return (q - f > 0.5) and f + 1 or f
end

-- world model from vanilla collision + HUSH ink variables (not from the light engine's own SOL)
local function world()
  local solid = {}
  for cy = 0, 13 do for cx = 0, 15 do
    solid[cy * 16 + cx] = rd(0x12000 + (18 + 2 * cy) * 64 + 16 + 2 * cx) ~= 0
  end end
  local ink = {}
  if rd16(0xC90C) > 0 then
    local x, y = rd16(0xC908) - rd16(0xE2), rd16(0xC90A) - rd16(0xE8)
    if x >= 0 and x < 256 and y >= 0 and y < 224 then
      local icx, icy = x // 16, y // 16
      for dy = -1, 1 do for dx = -1, 1 do ink[(icy + dy) * 16 + icx + dx] = true end end
    end
  end
  return solid, ink
end

local ROT = { [0] = function(d, b) return d, b end, [1] = function(d, b) return -d, b end,
              [2] = function(d, b) return b, d end, [3] = function(d, b) return b, -d end }

local function oracle(sig, solid, ink, R)
  local out = {}
  for i = 0, 223 do out[i] = 0 end
  local cls, f, p = sig[1], sig[2], sig[3]
  if cls == 0 then return out end
  local gx, gy = (p % 32) - 8, (p // 32) - 8
  if ink[gy * 16 + gx] then return out end
  local function cell(dx, dy)
    local x, y = gx + dx, gy + dy
    if x < 0 or x > 15 or y < 0 or y > 13 then return nil end
    return y * 16 + x, x, y
  end
  out[gy * 16 + gx] = step(cls, R, 0, false)
  local facings = cls == 1 and { f } or { 0, 1, 2, 3 }
  for _, fc in ipairs(facings) do
    local reach = { ["0,0"] = true }       -- reached AND open (light passes on)
    for d = 1, R + 1 do
      for b = -d, d do
        local pb = rnd(b * (d - 1) / d)
        if reach[(d - 1) .. "," .. pb] then
          local i, x, y = cell(ROT[fc](d, b))
          if i and not ink[i] then
            local face = solid[i] and y < 13 and not solid[i + 16]
            if not solid[i] then reach[d .. "," .. b] = true end
            if not solid[i] or face then
              local v = step(cls, R, d, cls == 1 and math.abs(b) == d)
              if v > out[i] then out[i] = v end
            end
          end
        end
      end
    end
  end
  return out
end

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

local function vram_bg1(trow, tcol)    -- BG1 tilemap at VRAM word $1000, 2 x 2 screens of 32 x 32
  local tx, ty = 16 + tcol, 18 + trow
  local w = 0x1000 + (ty >= 32 and 0x800 or 0) + (tx >= 32 and 0x400 or 0) + (ty % 32) * 32 + (tx % 32)
  return emu.read16(w * 2, V, false)
end

hush.test("lighting: lantern light = guard sight (design/lighting.md)", function()
  local m = bot.rooms()
  bot.start_new_game()
  local checks, cells, lit_cells, vram_checks, ink_checks = 0, 0, 0, 0, 0
  local inked = false
  local moves = { { "left" }, { "up" }, { "right" }, { "down" } }
  for ri = 1, m.count do
    local r = m.rooms[ri]
    bot.jump_to_room(ri - 1)
    hush.wait(40)
    hush.assert_eq(rd(L.ON), 1, r.id .. ": light on")
    -- light colours in BG row 2, colours 9-12 (src/hooks/light.asm Hush_LightCols), uploaded before the first fade-in frame
    for k, want in ipairs({ 0x0045, 0x00AA, 0x0551, 0x2024 }) do
      hush.assert_eq(emu.read16((2 * 16 + 8 + k) * 2, emu.memType.snesCgRam, false), want, r.id .. ": light colour " .. k .. " in CGRAM")
    end
    local pending = {}                      -- slot -> frame a mismatch was first seen (liveness)
    for t = 1, 24 do
      hush.hold(moves[(t // 6) % 4 + 1], 10)
      if r.id == "r05" and t == 8 then       -- an ink cloud 40 px in front of the (left-facing) guard: its cells must go dark and block light
        local gx, gy = rd(0x0D10) + 256 * rd(0x0D30), rd(0x0D00) + 256 * rd(0x0D20)
        bot.poke(0x7EC908, (gx - 40) & 0xFF); bot.poke(0x7EC909, (gx - 40) >> 8)
        bot.poke(0x7EC90A, (gy + 8) & 0xFF); bot.poke(0x7EC90B, (gy + 8) >> 8)
        bot.poke(0x7EC90C, 200); bot.poke(0x7EC90D, 0)
        inked = true
        hush.wait(2)                          -- the worker sees the cloud at the end of the next frame
      end
      if rd(0x10) ~= 7 or rd(0x11) ~= 0 then goto continue end
      -- 5. colour math shadows
      hush.assert(rd(0x1D) & 1 == 1, r.id .. ": BG1 on the sub screen")
      if rd(0xC903) == 0 then
        hush.assert_eq(rd(0x99), 0x02, r.id .. ": CGWSEL"); hush.assert_eq(rd(0x9A), 0x22, r.id .. ": CGADSUB")
      end
      if rd(L.JOB) == 0xFF then
        local solid, ink = world()
        if next(ink) then ink_checks = ink_checks + 1 end
        local R = rd16(0xC906) >= 128 and 8 or 5
        local comp = {}
        for i = 0, 223 do comp[i] = 0 end
        for s = 0, 7 do
          local sg = sigc(s)
          if sg[1] ~= 0xFF then
            local exp = oracle(sg, solid, ink, R)
            for i = 0, 223 do
              local got = rd(L.GMAP + s * 224 + i)
              if got ~= exp[i] then
                hush.fail(string.format("%s t=%d slot %d sig (%d,%d,%d) cell (%d,%d): light %d, rules say %d", r.id, t, s, sg[1], sg[2], sg[3], i % 16, i // 16, got, exp[i]))
              end
              if got > comp[i] then comp[i] = got end
              cells = cells + 1
            end
          else
            for i = 0, 223 do local got = rd(L.GMAP + s * 224 + i); if got > comp[i] then comp[i] = got end end
          end
          -- 4. liveness
          if same(sg, live_sig(s)) then pending[s] = nil
          elseif not pending[s] then pending[s] = hush.frame()
          else hush.assert(hush.frame() - pending[s] <= 90, string.format("%s: slot %d light lags its guard > 90 frames", r.id, s)) end
        end
        -- 2. composite + glow
        local lc = rd16(L.LCELL)
        for i = 0, 223 do
          hush.assert_eq(rd(L.COMP + i), comp[i], string.format("%s: composite of cell (%d,%d)", r.id, i % 16, i // 16))
          if comp[i] > 0 then lit_cells = lit_cells + 1 end
          local ev = 0
          if lc < 224 and not solid[i] then
            if i == lc then ev = 2
            elseif (math.abs(i % 16 - lc % 16) + math.abs(i // 16 - lc // 16)) == 1 then ev = 1 end
          end
          hush.assert_eq(rd(L.VIO + i), ev, string.format("%s: player glow of cell (%d,%d), Link cell %d", r.id, i % 16, i // 16, lc))
          -- 3. tile words
          local wi = comp[i] > 0 and comp[i] or (ev > 0 and 6 + ev or 0)
          local want = rd16(L.WORDS + 2 * wi)
          local off = L.TILES + ((i // 16) * 128) + (i % 16) * 4
          for _, o in ipairs({ 0, 2, 64, 66 }) do
            hush.assert_eq(rd16(off + o), want, string.format("%s: tile word of cell (%d,%d)", r.id, i % 16, i // 16))
          end
        end
        if rd16(L.DIRTY) == 0 then
          for trow = 0, 27 do for tcol = 0, 31 do
            hush.assert_eq(vram_bg1(trow, tcol), rd16(L.TILES + trow * 64 + tcol * 2), string.format("%s: BG1 VRAM tile (%d,%d)", r.id, tcol, trow))
          end end
          vram_checks = vram_checks + 1
        end
        checks = checks + 1
      end
      ::continue::
    end
  end
  hush.assert_gt(checks, m.count * 4, "enough idle checks")
  hush.assert_gt(lit_cells, 100, "some light exists")
  hush.assert_gt(vram_checks, m.count, "VRAM compared")
  hush.assert(inked and ink_checks > 0, "the ink cloud case was checked")
  hush.pass(string.format("%d checks (%d with ink), %d guard-cells vs the rules, %d lit composite cells, %d VRAM compares", checks, ink_checks, cells, lit_cells, vram_checks))
end)
