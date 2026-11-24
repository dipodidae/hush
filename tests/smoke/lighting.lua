-- Smoke (L1, design/lighting.md revision 4): lantern light = guard sight.
-- @timeout 900
-- For every real room, Link walks 24 legs of 10 frames; after each leg he stands still and the test waits (frame by frame) for the
-- engine's "render complete" flag light_done == 1 (ram_map `light_done`: no region, no job, nothing marked, wanted d = rendered d,
-- light_dirty 0). That wait is NOT a liveness bound (section 5 "Catch-up": "all light idle" is not required); it only fails if
-- light_done stays 0 for WAIT_HARD gameplay frames (the light never settles). The max wait is reported per room. On that frame:
--   1. every guard slot's committed light map (GMAP) equals an independent oracle of section 3 computed from the committed signature
--      (class, facing, cell), the collision map $7F2000 and the ink cloud (shape, range, falloff, cone edge, line of sight, faces)   [5 bullet 1];
--   2. the composite equals the max over the guards; the player glow follows section 3 (cell 2, orthogonal neighbours 1, floor only);
--   3. AMBER (section 5 "Amber (revision 2 rule)", 4.5 item 4 "Composite"): corners = the undisplaced 4.1 lattice of the composite,
--      Q(v) = floor(v (N-1)/6 + 1/2); a tile with any amber corner > 0 must show light.lut_amber[corners] (up to H/V flip), and its one
--      cell-centre corner must show exactly Q(step) of that cell;
--   4. VIOLET (section 5 "Violet (4.5 rule)", 4.5 items 1-3): l_v = the 4.1/4.3 lattice of the glow map (NV = 3, Qv(v) = floor(v + 1/2):
--      4.1 with the violet maximum 2), displaced by carrier 8's RENDERED (dx, dy) (ram_map `light_l3car` +16 / +32, signed) with the
--      separable rounded lerp of item 3 (outside indices 0); a tile with no amber corner > 0 and any violet corner > 0 must show
--      light.lut_violet[corners] (incl. substitutes); else the empty tile (4.3 "amber wins");
--   5. DISPLACEMENT (section 5 "qa also checks that displacement follows 4.5 item 2"): carrier 8's cell (`light_l3car` +8) = Link's glow
--      cell, which is the cell of Link's centre (x + 8, y + 16) (Hush_LightAura, the point "the engine uses to pick the carrier's cell");
--      rendered dx = q(clamp(px - (16 cx + 8), -16, 16)), dy likewise, q = round toward zero to D = 1 (reported, L3_REPORT.md A3);
--   6. the BG1 window in VRAM equals light_tiles (light_dirty = 0 is part of light_done);
--   7. CATCH-UP (section 5 "Catch-up (guard light liveness)", every gameplay frame of the walk, legs and waits): per guard slot, every
--      change of its live signature (class, facing, cell; live_sig) to S opens its own episode for S; it closes on the first frame where
--      the slot's committed signature (`light_sigc`) is S or a signature that appeared after S in that slot's sequence, no job runs for
--      that slot (`light_job` + 8 != slot) and the committed amber is in VRAM: no lattice row (`light_l3lpr`) and no tile row
--      (`light_l3adb`) pending and `light_dirty` bits 0-13 = 0 (all open episodes up to that signature close at once). (The amber
--      pipeline check is global, so it is stricter than "its tiles"; other
--      guards' running jobs, the glow and light_done are NOT required.) Per room: median <= 15, p90 <= 40, max <= 90 frames
--      (nearest rank); an episode still open when the room ends counts with its age if that exceeds 90. Room-entry staleness is not
--      an episode (no signature change); frames outside gameplay (restart / transition) drop open episodes (counted, logged);
--   8. colour math: BG1 on the sub screen ($1D bit 0), CGWSEL $02, CGADSUB $22; the exported ramp colours are in CGRAM (4.2 "Ramp", 4.3).
--
-- ENGINE EXPORT (build/rooms_gen.lua `light`, from tools/autotile.py; Python side: tests/unit/test_light_tiles.py):
--   light = { n, k, nv, kv, amber_cols = {...}, violet_cols = {...}, tiles = { { tile_id, kind 0/1/2, a, b, c, d }, ... },
--             lut_amber = { word per ((a*n + b)*n + c)*n + d }, lut_violet = { word per ((a*nv + b)*nv + c)*nv + d } }   (section 5)
-- RAM (docs/ram_map.md names via hush.ram): light_tiles, light_comp, light_vio, light_gmap, light_dirty, light_sigc, light_job (+8 job
-- slot, +22 Link's glow cell), light_done, light_l3car. BG1 tilemap at VRAM word $1000 (2 x 2 screens).
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
        DONE = ram("light_done"), LPR = ram("light_l3lpr"), ADB = ram("light_l3adb"),
        CELL8 = ram("light_l3car") + 8, RDX8 = ram("light_l3car") + 16 + 8, RDY8 = ram("light_l3car") + 32 + 8 }
        -- light_l3car: 13 arrays x 16 bytes by carrier; [0] cell, [1] rendered dx, [2] rendered dy (ram_map row); carrier 8 = the glow
end
local WAIT_HARD = 1200 -- light_done must become 1 within this many still gameplay frames (only "the light never settles" fails)
local CU_MED, CU_P90, CU_MAX = 15, 40, 90   -- design/lighting.md section 5 "Catch-up": per room median / p90 / max, frames
local D = 1            -- 4.5 item 2 quantization step reported by the engine (src/dev/L3_REPORT.md A3: "D = 1")
local function s8(v) return v >= 128 and v - 256 or v end
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

-- 7. catch-up tracker (section 5 "Catch-up": an episode for signature S runs from the frame the guard's signature changes to S to the
-- first frame the light drawn in VRAM for that guard is S "or any later signature of that guard"). Per slot, cu.open[s] is the ordered
-- list of open episodes { t0, sig }, one per signature change (oldest first). On a frame where the slot's committed signature is drawn
-- (committed, no job for the slot, amber pipeline idle), find the LATEST open episode k whose sig equals it: the drawn light is S_k,
-- which is S_k itself for episode k and a later signature for every episode before k, so episodes 1..k close (a repeated signature
-- matches its latest occurrence: the drawn light is then correct for that later change). new_cu() per room, cu_tick(cu) every frame.
local function new_cu()
  local cu = { open = {}, last = {}, epi = {}, drops = 0, frames = 0 }
  for s = 0, 7 do cu.last[s] = { -1, -1, -1 }; cu.open[s] = {} end
  return cu
end
local function amber_shown()
  return rd(L.LPR) == 0xFF and rd(L.ADB) == 0xFF and (rd16(L.DIRTY) & 0x3FFF) == 0
end
local function cu_tick(cu)
  if rd(0x10) ~= 7 or rd(0x11) ~= 0 or rd(L.ON) ~= 1 then
    for s = 0, 7 do cu.drops = cu.drops + #cu.open[s]; cu.open[s] = {}; cu.last[s] = { -1, -1, -1 } end
    return
  end
  cu.frames = cu.frames + 1
  local now, shown, job = hush.frame(), amber_shown(), rd(L.JOB)
  for s = 0, 7 do
    local lv = live_sig(s)
    local list = cu.open[s]
    if not same(lv, cu.last[s]) then
      if cu.last[s][1] ~= -1 then                -- a real change (not the first gameplay frame of the room / after a skip)
        list[#list + 1] = { t0 = now, sig = lv }
      end
      cu.last[s] = lv
    end
    if #list > 0 and job ~= s then
      local sc = sigc(s)
      local k = 0
      for i = #list, 1, -1 do if same(sc, list[i].sig) then k = i; break end end
      if k > 0 then
        for i = 1, k do if not list[i].tc then list[i].tc = now end end   -- informational: committed (S or later), maybe not yet shown
        if shown then
          for i = 1, k do
            local o = list[i]
            cu.epi[#cu.epi + 1] = now - o.t0
            cu.cmax = math.max(cu.cmax or 0, o.tc - o.t0)
            cu.smax = math.max(cu.smax or 0, now - o.tc)
          end
          local rest = {}
          for i = k + 1, #list do rest[#rest + 1] = list[i] end
          cu.open[s] = rest
        end
      end
    end
  end
end
local function nearest(sorted, p) if #sorted == 0 then return nil end; return sorted[math.max(1, math.ceil(p * #sorted))] end

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

-- the engine's tile table: tile id -> { kind, a, b, c, d } (stored, unflipped)
local function tile_table(lt)
  local t = {}
  for _, e in ipairs(lt.tiles) do t[e[1]] = { e[2], e[3], e[4], e[5], e[6] } end
  return t
end
-- word -> kind, shown corners (H flip swaps a<->b, c<->d; V flip a<->c, b<->d); nil if the tile id is not a light tile
local function decode(ttab, w)
  local e = ttab[w & 0x3FF]
  if not e then return nil end
  local a, b, c, d = e[2], e[3], e[4], e[5]
  if w & 0x4000 ~= 0 then a, b, c, d = b, a, d, c end
  if w & 0x8000 ~= 0 then a, b, c, d = c, d, a, b end
  return e[1], a, b, c, d
end
local function cs(a, b, c, d) return string.format("(%d,%d,%d,%d)", a, b, c, d) end

-- 4.5 item 3: displaced lattice, separable, rounded; l indexed j * 33 + i, outside i 0..32 / j 0..28 = 0
local function displace(l, dx, dy)
  if dx == 0 and dy == 0 then return l end
  local H, V = {}, {}
  for j = 0, 28 do
    local row = j * 33
    for i = 0, 32 do
      local X = 8 * i - dx
      local i0, t = X // 8, X % 8
      local a = (i0 >= 0 and i0 <= 32) and l[row + i0] or 0
      local b = (i0 + 1 >= 0 and i0 + 1 <= 32) and l[row + i0 + 1] or 0
      H[row + i] = ((8 - t) * a + t * b + 4) // 8
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
-- 4.5 item 2: clamp to +-16, then round toward zero to a multiple of D
local function want_d(v)
  v = math.max(-16, math.min(16, v))
  local q = (math.abs(v) // D) * D
  return v < 0 and -q or q
end

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

hush.test("lighting: lantern light = guard sight (design/lighting.md rev 4)", function()
  local m = bot.rooms()
  init_L()
  local lt = m.light
  hush.assert(lt and lt.tiles and lt.lut_amber and lt.lut_violet,
    "build/rooms_gen.lua has no `light` table with tiles / lut_amber / lut_violet (section 5 'exported corner LUTs')")
  hush.assert_eq(#lt.lut_amber, lt.n * lt.n * lt.n * lt.n, "lut_amber size n^4")
  hush.assert_eq(#lt.lut_violet, lt.nv * lt.nv * lt.nv * lt.nv, "lut_violet size nv^4")
  local ttab, n_amber, n_violet = tile_table(lt), lt.n, lt.nv
  bot.start_new_game()
  local checks, cells, lit_cells, vram_checks, ink_checks = 0, 0, 0, 0, 0
  local inked = false
  local moves = { { "left" }, { "up" }, { "right" }, { "down" } }
  local smooth = { tiles = 0, amber = 0, violet = 0, grad = 0, vsub = 0, vdisp = 0, bad = 0, msgs = {} }
  local disp = { n = 0, nz = 0, clamp = 0, maxabs = 0 }
  local waits = { max = 0, maxroom = "-", n = 0, sum = 0, per = {} }
  local cu_rows, cu_bad, cu_total = {}, {}, 0  -- 7. catch-up: per-room "id med/p90/max (n)", violations, episode count
  for ri = 1, m.count do
    local r = m.rooms[ri]
    bot.jump_to_room(ri - 1)
    local cu = new_cu()
    local function tick(buttons, n)          -- n frames (buttons held), the catch-up tracker sampled after each
      for _ = 1, n do hush.hold(buttons, 1); cu_tick(cu) end
    end
    tick({}, 40)
    hush.assert_eq(rd(L.ON), 1, r.id .. ": light on")
    check_ramp(r.id, lt)                     -- 8. ramp colours (uploaded before the first fade-in frame)
    local rmax = 0
    for t = 1, 24 do
      tick(moves[(t // 6) % 4 + 1], 10)
      if r.id == "r05" and t == 8 then       -- an ink cloud 40 px in front of the (left-facing) guard: its cells must go dark and block light
        local gx, gy = rd(0x0D10) + 256 * rd(0x0D30), rd(0x0D00) + 256 * rd(0x0D20)
        bot.poke(0x7EC908, (gx - 40) & 0xFF); bot.poke(0x7EC909, (gx - 40) >> 8)
        bot.poke(0x7EC90A, (gy + 8) & 0xFF); bot.poke(0x7EC90B, (gy + 8) >> 8)
        bot.poke(0x7EC90C, 200); bot.poke(0x7EC90D, 0)
        inked = true
        tick({}, 2)                           -- the worker sees the cloud at the end of the next frame
      end
      -- wait for light_done == 1 (Link stands still; gameplay frames only, a restart / transition restarts the count). Not a liveness
      -- bound (section 5 "Catch-up"); fails only past WAIT_HARD (the light never settles).
      local w0 = hush.frame()
      while not (rd(0x10) == 7 and rd(0x11) == 0 and rd(L.DONE) == 1) do
        if rd(0x10) ~= 7 or rd(0x11) ~= 0 then w0 = hush.frame() end
        if hush.frame() - w0 > WAIT_HARD then
          hush.fail(string.format("%s t=%d: light_done never became 1 within %d gameplay frames of Link stopping (job slot $%02X, dirty $%04X, glow cell %d, rendered d (%d,%d)); the light never settles",
            r.id, t, WAIT_HARD, rd(L.JOB), rd16(L.DIRTY), rd(L.CELL8), s8(rd(L.RDX8)), s8(rd(L.RDY8))))
          return
        end
        tick({}, 1)
      end
      local wf = hush.frame() - w0
      if wf > rmax then rmax = wf end
      if wf > waits.max then waits.max, waits.maxroom = wf, r.id end
      waits.n, waits.sum = waits.n + 1, waits.sum + wf
      do
        -- 8. colour math shadows
        hush.assert(rd(0x1D) & 1 == 1, r.id .. ": BG1 on the sub screen")
        if rd(0xC903) == 0 then
          hush.assert_eq(rd(0x99), 0x02, r.id .. ": CGWSEL"); hush.assert_eq(rd(0x9A), 0x22, r.id .. ": CGADSUB")
        end
        hush.assert_eq(rd(L.JOB), 0xFF, r.id .. ": light_done = 1 but a guard job runs (ram_map light_done)")
        hush.assert_eq(rd16(L.DIRTY), 0, r.id .. ": light_done = 1 but light_dirty != 0 (ram_map light_done)")
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
        -- 5. displacement of the glow carrier (4.5 item 2; section 5 "qa also checks that displacement follows 4.5 item 2")
        local c8, rdx, rdy = rd(L.CELL8), s8(rd(L.RDX8)), s8(rd(L.RDY8))
        hush.assert_eq(c8, lc < 224 and lc or 0xFF, string.format("%s t=%d: glow carrier 8 cell vs Link's glow cell (light_job+22)", r.id, t))
        local px, py = rd16(0x22) + 8 - rd16(0xE2), rd16(0x20) + 16 - rd16(0xE8)
        if px >= 0 and px < 256 and py >= 0 and py < 224 then
          hush.assert_eq(lc, (py // 16) * 16 + px // 16, string.format("%s t=%d: Link's glow cell vs his centre (%d,%d)", r.id, t, px, py))
        end
        if c8 ~= 0xFF then
          local ex, ey = want_d(px - (16 * (c8 % 16) + 8)), want_d(py - (16 * (c8 // 16) + 8))
          if rdx ~= ex or rdy ~= ey then
            hush.fail(string.format("%s t=%d: glow rendered d = (%d,%d), 4.5 item 2 says (%d,%d) (Link centre (%d,%d), glow cell (%d,%d), D = %d)",
              r.id, t, rdx, rdy, ex, ey, px, py, c8 % 16, c8 // 16, D))
            return
          end
          disp.n = disp.n + 1
          if rdx ~= 0 or rdy ~= 0 then disp.nz = disp.nz + 1 end
          if math.abs(rdx) == 16 or math.abs(rdy) == 16 then disp.clamp = disp.clamp + 1 end
          disp.maxabs = math.max(disp.maxabs, math.abs(rdx), math.abs(rdy))
        else
          rdx, rdy = 0, 0                     -- no glow lattice: the violet lattice is all 0 anyway
        end
        -- 3 + 4. every 8x8 tile word vs the LUT oracle: amber undisplaced (rev 2 rule), violet displaced by the rendered d (4.5)
        local amb = lattice(comp, 6, n_amber)
        local vlt = displace(lattice(vio, 2, n_violet), rdx, rdy)
        local LA, LV = lt.lut_amber, lt.lut_violet
        for ty = 0, 27 do for tx = 0, 31 do
          local w = rd16(L.TILES + ty * 64 + tx * 2)
          local p = ty * 33 + tx
          local wa, wb, wc, wd, want_kind = amb[p], amb[p + 1], amb[p + 33], amb[p + 34], 1
          local ew
          if wa + wb + wc + wd > 0 then
            ew = LA[((wa * n_amber + wb) * n_amber + wc) * n_amber + wd + 1]
            smooth.amber = smooth.amber + 1
          else
            wa, wb, wc, wd, want_kind = vlt[p], vlt[p + 1], vlt[p + 33], vlt[p + 34], 2
            if wa + wb + wc + wd == 0 then want_kind = 0 end
            ew = LV[((wa * n_violet + wb) * n_violet + wc) * n_violet + wd + 1]
            if want_kind == 2 then smooth.violet = smooth.violet + 1; if rdx ~= 0 or rdy ~= 0 then smooth.vdisp = smooth.vdisp + 1 end end
          end
          if want_kind > 0 and (wa ~= wb or wa ~= wc or wa ~= wd) then smooth.grad = smooth.grad + 1 end
          local ek, ea, eb, ec, ed = decode(ttab, ew)
          local gk, ga, gb, gc, gd = decode(ttab, w)
          if want_kind == 2 and ek and (ea ~= wa or eb ~= wb or ec ~= wc or ed ~= wd) then smooth.vsub = smooth.vsub + 1 end
          -- match up to H/V flip: same word, or the same kind and shown corners
          local ok = gk ~= nil and ek ~= nil and (w == ew or (gk == ek and ga == ea and gb == eb and gc == ec and gd == ed))
          local why = "LUT"
          if ok and want_kind == 1 then        -- section 5: the cell-centre point (i odd, j odd) shows exactly Q(step) = step (N = 7)
            local cen = (tx % 2 == 1) and ((ty % 2 == 1) and ga or gc) or ((ty % 2 == 1) and gb or gd)
            local want = (tx % 2 == 1) and ((ty % 2 == 1) and wa or wc) or ((ty % 2 == 1) and wb or wd)
            if cen ~= want then ok, why = false, "cell-centre level" end
          end
          smooth.tiles = smooth.tiles + 1
          if not ok then
            smooth.bad = smooth.bad + 1
            if #smooth.msgs < 8 then
              smooth.msgs[#smooth.msgs + 1] = string.format("%s t=%d tile (%d,%d) cell (%d,%d): word $%04X shows %s %s, oracle (%s) wants %s corners %s -> word $%04X showing %s; glow d (%d,%d)",
                r.id, t, tx, ty, tx // 2, ty // 2, w, gk and KIND[gk] or "unknown tile", gk and cs(ga, gb, gc, gd) or "-", why, KIND[want_kind],
                cs(wa, wb, wc, wd), ew, ek and cs(ea, eb, ec, ed) or "-", rdx, rdy)
            end
          end
        end end
        -- 6. VRAM = buffer (light_dirty = 0 asserted above)
        for trow = 0, 27 do for tcol = 0, 31 do
          hush.assert_eq(vram_bg1(trow, tcol), rd16(L.TILES + trow * 64 + tcol * 2), string.format("%s: BG1 VRAM tile (%d,%d)", r.id, tcol, trow))
        end end
        vram_checks = vram_checks + 1
        checks = checks + 1
      end
    end
    waits.per[#waits.per + 1] = r.id .. " " .. rmax
    -- 7. catch-up per room (section 5): open episodes at the room's end count with their age only if that already breaks the max
    local ep = {}
    for _, v in ipairs(cu.epi) do ep[#ep + 1] = v end
    local oldest = 0
    for s = 0, 7 do if cu.open[s][1] then oldest = math.max(oldest, hush.frame() - cu.open[s][1].t0) end end
    if oldest > CU_MAX then ep[#ep + 1] = oldest end
    table.sort(ep)
    cu_total = cu_total + #ep
    local med, p90, mx = nearest(ep, 0.5), nearest(ep, 0.9), ep[#ep]
    cu_rows[#cu_rows + 1] = string.format("%s %s/%s/%s (n=%d, drops %d; max to commit %d, max commit to VRAM %d)", r.id, med or "-", p90 or "-", mx or "-", #ep, cu.drops,
      cu.cmax or 0, cu.smax or 0)
    if #ep > 0 and (med > CU_MED or p90 > CU_P90 or mx > CU_MAX) then
      cu_bad[#cu_bad + 1] = string.format("%s median %d (<= %d) p90 %d (<= %d) max %d (<= %d)%s", r.id, med, CU_MED, p90, CU_P90, mx, CU_MAX,
        oldest > CU_MAX and string.format(", open at end %d", oldest) or "")
    end
    hush.log(string.format("%s done: %d checks so far, %d tile mismatches, max wait for light_done %d frames, catch-up med/p90/max %s/%s/%s over %d episodes (%d gameplay frames), cpu %.0f s",
      r.id, checks, smooth.bad, rmax, med or "-", p90 or "-", mx or "-", #ep, cu.frames, os.clock()))
  end
  hush.log("light_done max wait per room (frames, informational): " .. table.concat(waits.per, ", "))
  hush.log("catch-up per room, stale episodes median/p90/max (frames): " .. table.concat(cu_rows, ", "))
  hush.assert_gt(checks, m.count * 4, "enough render-complete checks")
  hush.assert_gt(lit_cells, 100, "some light exists")
  hush.assert_gt(vram_checks, m.count, "VRAM compared")
  hush.assert(inked and ink_checks > 0, "the ink cloud case was checked")
  hush.assert_gt(smooth.grad, 100, "tiles with a gradient (corners not all equal) were checked")
  hush.assert_gt(disp.nz, 20, "glow checks with a non-zero rendered displacement (4.5 exercised)")
  hush.assert_gt(smooth.vdisp, 100, "violet tiles checked under a non-zero displacement")
  hush.assert_gt(cu_total, 200, "stale episodes measured (catch-up exercised)")
  local summary = string.format("%d checks (%d with ink), %d guard-cells vs rules, %d lit cells, %d VRAM compares; tiles: %d words (%d amber, %d violet, %d violet displaced, %d violet substitutes, %d gradient), %d wrong; glow d: %d checks, %d non-zero, %d at clamp, max |d| %d; light_done wait max %d frames (%s), mean %.1f; catch-up: %d episodes, every room within %d/%d/%d",
    checks, ink_checks, cells, lit_cells, vram_checks, smooth.tiles, smooth.amber, smooth.violet, smooth.vdisp, smooth.vsub, smooth.grad, smooth.bad,
    disp.n, disp.nz, disp.clamp, disp.maxabs, waits.max, waits.maxroom, waits.sum / math.max(1, waits.n), cu_total, CU_MED, CU_P90, CU_MAX)
  if smooth.bad > 0 then
    for _, s in ipairs(smooth.msgs) do hush.log("SMOOTH: " .. s) end
    hush.fail(string.format("%d of %d tile words differ from the section 5 oracle (amber rev 2 lattice / violet 4.5 displaced lattice via the LUTs); first: %s",
      smooth.bad, smooth.tiles, smooth.msgs[1]))
    return
  end
  if #cu_bad > 0 then
    hush.fail(string.format("catch-up (lighting.md section 5): %d room(s) over the limits: %s", #cu_bad, table.concat(cu_bad, "; ")))
    return
  end
  hush.pass(summary)
end)
