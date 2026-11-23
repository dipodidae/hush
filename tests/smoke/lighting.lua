-- Smoke (L1, design/lighting.md): lantern light = guard sight.
-- @timeout 600
-- For every real room, while the guards patrol and Link walks, at many frames when the light engine is idle:
--   1. every guard slot's committed light map (GMAP) equals an independent oracle of design/lighting.md section 3 computed from the committed
--      signature (class, facing, cell), the collision map $7F2000 and the ink cloud (shape, range, falloff, cone edge, line of sight, faces);
--   2. the composite equals the max over the guards, the player glow follows design/lighting.md (cell 2, orthogonal neighbours 1, floor only);
--   3. SMOOTH LOOK (lighting.md revision 2, sections 4.1-4.3 and the section 5 "Smooth look" / "In-emulator" sentences): from the per-cell
--      composite (checked in 1-2) and glow, a Lua oracle computes the 33 x 29 lattice (centre = the cell's step, edge midpoint = average of
--      2 cells, corner = average of 4, outside cells 0), quantizes it with Q(v) = floor(v (N-1)/6 + 1/2), and for every 8x8 tile of the
--      32 x 28 window takes the corner levels (a TL, b TR, c BL, d BR). The tile word in the WRAM light buffer must decode (tile id + H/V
--      flips, through the engine's exported tile table) to: the amber tile with exactly those corners if any amber corner > 0 (4.3 "amber
--      wins"), else the violet tile with the violet corners (violet lattice of the glow cells, Qv(v) = floor(v (NV-1)/2 + 1/2): ASSUMPTION,
--      4.3 gives no violet formula, this is 4.1 with the violet maximum 2), else an all-zero tile. Once no row is dirty, the BG1 window in
--      VRAM equals the buffer;
--   4. liveness: every committed signature catches up with the live guard (state, cell, facing) within 90 frames of a check;
--   5. colour math: BG1 on the sub screen ($1D bit 0), CGWSEL $02, CGADSUB $22; the exported ramp colours are in CGRAM: K-1 >= 4 amber
--      colours, non-zero, warm (red >= blue), brightness (R+G+B) non-decreasing from the edge to the core, the core brighter than the edge
--      (4.2 "Ramp"); KV-1 >= 2 violet colours, non-zero, blue > green (4.3).
--
-- EXPECTED ENGINE EXPORT (build/rooms_gen.lua, a top-level field of the returned table, next to `rooms`; written by tools/roomgen.py from
-- tools/autotile.py, see tests/unit/test_light_tiles.py for the Python side). Plain nested arrays (tools/solve_rooms.py parses this file):
--   light = { n = N, k = K, nv = NV, kv = KV,
--             amber_cols = { CGRAM colour index of r1, ..., r(K-1) },      -- 0..255 (row * 16 + colour)
--             violet_cols = { CGRAM colour index of v1, ..., v(KV-1) },
--             tiles = { { tile_id, kind, a, b, c, d }, ... } },            -- one per stored (unflipped) BG1 light tile; tile_id = word & $3FF,
--                                                                          -- kind 0 empty, 1 amber, 2 violet; a b c d = its corner levels
-- RAM (docs/ram_map.md names, read through hush.ram so a move only needs the ram_map row): `light_tiles` = the BG1 window tile words,
-- 32 x 28 words row-major (row stride 64 bytes), `light_comp`, `light_vio`, `light_gmap`, `light_dirty` (0 = the VRAM window equals
-- `light_tiles`), `light_job` (+8 = job slot, $FF idle; +22 = Link's glow cell). BG1 tilemap at VRAM word $1000 (2 x 2 screens).
-- Without the export (the per-cell build), section 3 decodes the old 9-word table Hush_LightWords as N = 7 per-cell blocks, so the test
-- still fails on the visible behaviour (block edges where the smooth look needs a gradient), and then on the missing export.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W, V = emu.memType.snesWorkRam, emu.memType.snesVideoRam
local function rd(a) return emu.read(a, W, false) end            -- WRAM offset (bank $7E = 0..$FFFF, $7F = +$10000)
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local L = {}   -- filled by init_L() inside the test (hush.test loads docs/ram_map.md)
local function init_L()
  local function ram(name) local e = hush.ram[name]; if not e then hush.fail("docs/ram_map.md has no row " .. name) end; return e.addr end
  L = { GMAP = ram("light_gmap"), COMP = ram("light_comp"), VIO = ram("light_vio"), TILES = ram("light_tiles"), ON = ram("light_on"),
        DIRTY = ram("light_dirty"), SIGC = ram("light_sigc"), JOB = ram("light_job") + 8, LCELL = ram("light_job") + 22,
        OLD_WORDS = 0xE714 }   -- docs/ram_map.md "HUSH lighting"; OLD_WORDS = light_tab + 1284 (Hush_LightWords, fallback decoder only)
end
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

-- ---- section 3 oracle: lighting.md 4.1 lattice + Q, 4.3 amber wins -------------------------------------------------------------------
-- level of lattice point (i, j), i = 0..32, j = 0..28, from a per-cell map (0..223, cell values 0..vmax), n levels:
-- Q(v) = floor(v (n-1)/vmax + 1/2) with v = sum/den, in exact integers: floor((2 sum (n-1) + vmax den) / (2 vmax den))
-- PTS[p] = { den, cell indices inside the grid... } (outside cells count 0, so they are simply left out of the sum)
local PTS = {}
do
  local function add(t, cx, cy) if cx >= 0 and cx <= 15 and cy >= 0 and cy <= 13 then t[#t + 1] = cy * 16 + cx end end
  for j = 0, 28 do for i = 0, 32 do
    local t
    if i % 2 == 1 and j % 2 == 1 then t = { 1 }; add(t, (i - 1) // 2, (j - 1) // 2)                                    -- cell centre
    elseif i % 2 == 1 then t = { 2 }; add(t, (i - 1) // 2, j // 2 - 1); add(t, (i - 1) // 2, j // 2)                    -- horizontal edge
    elseif j % 2 == 1 then t = { 2 }; add(t, i // 2 - 1, (j - 1) // 2); add(t, i // 2, (j - 1) // 2)                    -- vertical edge
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
local KIND = { [0] = "empty", [1] = "amber", [2] = "violet" }

-- the engine's tile table: tile id -> { kind, a, b, c, d }; plus n / nv. Fallback without the export: the per-cell build's 9 words.
local function tile_table(m)
  if m.light then
    local t = {}
    for _, e in ipairs(m.light.tiles) do t[e[1]] = { e[2], e[3], e[4], e[5], e[6] } end
    return t, m.light.n, m.light.nv, true
  end
  local t = {}
  for wi = 0, 8 do
    local id = rd16(L.OLD_WORDS + 2 * wi) & 0x3FF
    if wi <= 6 then t[id] = { wi == 0 and 0 or 1, wi, wi, wi, wi } else t[id] = { 2, wi - 6, wi - 6, wi - 6, wi - 6 } end
  end
  return t, 7, 3, false
end
-- word -> shown corners: H flip swaps a<->b, c<->d; V flip a<->c, b<->d (done inline in the check loop for speed)
local function cs(c) return string.format("(%d,%d,%d,%d)", c[1], c[2], c[3], c[4]) end

-- 5. ramp colours (lighting.md 4.2 "Ramp", 4.3)
local function bgr(i) local v = emu.read16(i * 2, emu.memType.snesCgRam, false); return v & 31, (v >> 5) & 31, (v >> 10) & 31 end
local function check_ramp(id, lt)
  hush.assert(#lt.amber_cols == lt.k - 1 and lt.k - 1 >= 4, id .. ": amber ramp needs K-1 >= 4 colours (4.2), export has " .. #lt.amber_cols)
  hush.assert(#lt.violet_cols == lt.kv - 1 and lt.kv - 1 >= 2, id .. ": violet ramp needs >= 2 colours (4.3), export has " .. #lt.violet_cols)
  local prev
  for i, ci in ipairs(lt.amber_cols) do
    local r, g, b = bgr(ci)
    hush.assert(r + g + b > 0, string.format("%s: amber r%d (CGRAM %d) is black", id, i, ci))
    hush.assert(r >= b, string.format("%s: amber r%d (CGRAM %d) = (%d,%d,%d) is not warm (red < blue)", id, i, ci, r, g, b))
    if prev then hush.assert(r + g + b >= prev, string.format("%s: amber r%d darker than r%d (4.2 monotone)", id, i, i - 1)) end
    prev = r + g + b
  end
  local r1, g1, b1 = bgr(lt.amber_cols[1])
  hush.assert(prev > r1 + g1 + b1, id .. ": the amber core is not brighter than the edge (4.2)")
  for i, ci in ipairs(lt.violet_cols) do
    local r, g, b = bgr(ci)
    hush.assert(r + g + b > 0 and b > g, string.format("%s: violet v%d (CGRAM %d) = (%d,%d,%d) is not a violet", id, i, ci, r, g, b))
  end
end

hush.test("lighting: lantern light = guard sight (design/lighting.md)", function()
  local m = bot.rooms()
  init_L()
  bot.start_new_game()
  local checks, cells, lit_cells, vram_checks, ink_checks = 0, 0, 0, 0, 0
  local inked = false
  local moves = { { "left" }, { "up" }, { "right" }, { "down" } }
  local ttab, n_amber, n_violet, exported
  local smooth = { tiles = 0, lit = 0, grad = 0, bad = 0, msgs = {} }
  for ri = 1, m.count do
    local r = m.rooms[ri]
    bot.jump_to_room(ri - 1)
    hush.wait(40)
    hush.assert_eq(rd(L.ON), 1, r.id .. ": light on")
    if not ttab then ttab, n_amber, n_violet, exported = tile_table(m) end
    -- 5. ramp colours (uploaded before the first fade-in frame); only with the export (the CGRAM indices are the engine's choice)
    if exported then check_ramp(r.id, m.light) end
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
        local vio = {}
        for i = 0, 223 do
          hush.assert_eq(rd(L.COMP + i), comp[i], string.format("%s: composite of cell (%d,%d)", r.id, i % 16, i // 16))
          if comp[i] > 0 then lit_cells = lit_cells + 1 end
          local ev = 0
          if lc < 224 and not solid[i] then
            if i == lc then ev = 2
            elseif (math.abs(i % 16 - lc % 16) + math.abs(i // 16 - lc // 16)) == 1 then ev = 1 end
          end
          hush.assert_eq(rd(L.VIO + i), ev, string.format("%s: player glow of cell (%d,%d), Link cell %d", r.id, i % 16, i // 16, lc))
          vio[i] = ev
        end
        -- 3. smooth look: every 8x8 tile word vs the lattice oracle (lighting.md 4.1-4.3, section 5)
        local amb, vlt = lattice(comp, 6, n_amber), lattice(vio, 2, n_violet)
        for ty = 0, 27 do for tx = 0, 31 do
          local w = rd16(L.TILES + ty * 64 + tx * 2)
          local p = ty * 33 + tx
          local wa, wb, wc, wd, want_kind = amb[p], amb[p + 1], amb[p + 33], amb[p + 34], 1
          if wa + wb + wc + wd == 0 then
            wa, wb, wc, wd, want_kind = vlt[p], vlt[p + 1], vlt[p + 33], vlt[p + 34], 2
            if wa + wb + wc + wd == 0 then want_kind = 0 end
          end
          local e = ttab[w & 0x3FF]
          local ok = false
          local ga, gb, gc, gd
          if e then
            ga, gb, gc, gd = e[2], e[3], e[4], e[5]
            if w & 0x4000 ~= 0 then ga, gb, gc, gd = gb, ga, gd, gc end
            if w & 0x8000 ~= 0 then ga, gb, gc, gd = gc, gd, ga, gb end
            ok = ga == wa and gb == wb and gc == wc and gd == wd and (e[1] == want_kind or want_kind == 0)
          end
          if want_kind > 0 then
            smooth.lit = smooth.lit + 1
            if wa ~= wb or wa ~= wc or wa ~= wd then smooth.grad = smooth.grad + 1 end
          end
          smooth.tiles = smooth.tiles + 1
          if not ok then
            smooth.bad = smooth.bad + 1
            if #smooth.msgs < 8 then
              smooth.msgs[#smooth.msgs + 1] = string.format("%s t=%d tile (%d,%d) cell (%d,%d): word $%04X shows %s %s, lattice says %s (%d,%d,%d,%d)",
                r.id, t, tx, ty, tx // 2, ty // 2, w, e and KIND[e[1]] or "unknown tile", e and cs({ ga, gb, gc, gd }) or "-", KIND[want_kind], wa, wb, wc, wd)
            end
          end
        end end
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
    hush.log(string.format("%s done: %d checks so far, %d smooth mismatches, cpu %.0f s", r.id, checks, smooth.bad, os.clock()))
  end
  hush.assert_gt(checks, m.count * 4, "enough idle checks")
  hush.assert_gt(lit_cells, 100, "some light exists")
  hush.assert_gt(vram_checks, m.count, "VRAM compared")
  hush.assert(inked and ink_checks > 0, "the ink cloud case was checked")
  hush.assert_gt(smooth.grad, 100, "tiles with a gradient (corners not all equal) were checked")
  local summary = string.format("%d checks (%d with ink), %d guard-cells vs the rules, %d lit composite cells, %d VRAM compares; smooth look: %d tile words (%d lit, %d with a gradient) vs the lattice, %d wrong",
    checks, ink_checks, cells, lit_cells, vram_checks, smooth.tiles, smooth.lit, smooth.grad, smooth.bad)
  if smooth.bad > 0 then
    for _, s in ipairs(smooth.msgs) do hush.log("SMOOTH: " .. s) end
    hush.fail(string.format("%d of %d tile words do not show the lighting.md 4.1-4.3 corner levels (%s); first: %s",
      smooth.bad, smooth.tiles, exported and "engine tile table" or "NO EXPORT: decoded as the old per-cell tiles", smooth.msgs[1]))
  end
  hush.assert(exported, "build/rooms_gen.lua has no `light` table (the engine export this test needs, see the header)")
  hush.pass(summary)
end)
