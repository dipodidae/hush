-- Smoke (E3 + E5): the visual variety of the room tiles is really on screen and changes NOTHING about collision.
--   * for every real room (design/rooms, build/hush.sfc) the BG2 tilemap buffer ($7E2000, the "upper layer" list-1 objects draw to; $7E4000 = BG1 holds only the floor) AND the BG2 tilemap in VRAM hold, for every cell
--     of the 16x14 window, exactly the tile words the grid predicts (floor, wall top, wall face, pillar, exit marker) -- or, for a cell that
--     tools/roomgen.py decorated (E5: rooms_gen.lua `variants` {cx, cy, name} + `variant_words`/`variant_kind`), the words of that variant. A variant
--     is only legal on a cell of its own base kind (floor variants only on a plain '.', never S/X/guard cells, except the wall contact shadow which also covers S/guard cells; wall-top variants only on `ceil`; face variants only on `face`);
--   * the collision map $7F2000 equals the grid: `#` and `p` solid ($01 on all four 8x8 tiles), everything else (incl. `X`) floor ($00);
--   * the palette set follows floor / lighting (CGRAM BG rows differ between sets, the OBJ half of CGRAM is identical in every room).
-- Expected words (docs/gfx/art_map.md section 3.1, src/hooks/room_visuals.asm); order TL TR / BL BR:
--   floor  0CEC 0CED / 0CFC 0CFD        wall top 3C15 x4          wall face 3C15 3C15 / 3824 3825 (a `#` with floor below)
--   pillar 142C 142D / 143C 143D        exit     10C0 10C1 / 10D0 10D1
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W, V, C = emu.memType.snesWorkRam, emu.memType.snesVideoRam, emu.memType.snesCgRam
local WIN_TX, WIN_TY = 16, 18          -- window origin in 8x8 tiles (tools/roomgen.py WIN_X/8, WIN_Y/8)

local WORDS = {
  floor  = { 0x0CEC, 0x0CED, 0x0CFC, 0x0CFD },
  ceil   = { 0x3C15, 0x3C15, 0x3C15, 0x3C15 },
  face   = { 0x3C15, 0x3C15, 0x3824, 0x3825 },
  pillar = { 0x142C, 0x142D, 0x143C, 0x143D },
  exit   = { 0x10C0, 0x10C1, 0x10D0, 0x10D1 },
}

local function kind_of(grid, r, c)
  local ch = grid[r + 1]:sub(c + 1, c + 1)
  if ch == "#" then
    local below = grid[r + 2] and grid[r + 2]:sub(c + 1, c + 1)
    if below and below ~= "#" and below ~= "p" then return "face" end
    return "ceil"
  elseif ch == "p" then return "pillar"
  elseif ch == "X" then return "exit" end
  return "floor"
end

-- BG2 tilemap in VRAM: 64x64 entries = four 32x32 screens (SC0 TL, SC1 TR, SC2 BL, SC3 BR), 0x400 words each, at VRAM byte $0000.
local function vram_word(tx, ty)
  local screen = (ty >= 32 and 2 or 0) + (tx >= 32 and 1 or 0)
  return emu.read16(((screen * 0x400) + (ty % 32) * 32 + (tx % 32)) * 2, V, false)
end
local function wram_word(tx, ty) return emu.read16(0x2000 + (ty * 64 + tx) * 2, W, false) end
local function col_byte(tx, ty) return emu.read(0x12000 + ty * 64 + tx, W, false) end   -- $7F2000 = WRAM offset $12000 (64x64 bytes)

hush.test("visual_tiles: tilemap tile ids, collision unchanged, palette sets", function()
  local m = bot.rooms()
  bot.start_new_game()
  local seen = { floor = 0, ceil = 0, face = 0, pillar = 0, exit = 0 }
  local vseen, vcount = { floor = 0, ceil = 0, face = 0 }, 0
  local torches_lit, torches_dark = 0, 0
  local obj_ref, bg_by_set = nil, {}
  for i = 1, m.count do
    local r = m.rooms[i]
    bot.jump_to_room(i - 1)
    hush.wait(60)
    local vmap = {}
    for _, v in ipairs(r.variants) do
      local key = v[1] .. "," .. v[2]
      hush.assert(vmap[key] == nil, string.format("%s: two variants on cell (%d,%d)", r.id, v[1], v[2]))
      vmap[key] = v[3]
    end
    for cy = 0, 13 do
      for cx = 0, 15 do
        local k = kind_of(r.grid, cy, cx)
        seen[k] = seen[k] + 1
        local solid = (k == "ceil" or k == "face" or k == "pillar") and 1 or 0
        local vname = vmap[cx .. "," .. cy]
        local words = WORDS[k]
        if vname then
          local vw = m.variant_words[vname]
          hush.assert(vw ~= nil, r.id .. ": unknown variant " .. tostring(vname))
          local ch = r.grid[cy + 1]:sub(cx + 1, cx + 1)
          hush.assert_eq(m.variant_kind[vname], k, string.format("%s cell (%d,%d) '%s': variant %s is for another kind of cell", r.id, cx, cy, ch, vname))
          if k == "floor" and vname ~= "f_shadow" then hush.assert_eq(ch, ".", string.format("%s cell (%d,%d): floor variant %s on a special cell (S/X/guard)", r.id, cx, cy, vname)) end
          if vname == "f_shadow" then hush.assert(ch ~= "X", r.id .. ": shadow on an exit cell") end
          words = vw
          vseen[k] = vseen[k] + 1
          vcount = vcount + 1
          if vname == "fc_torch" then torches_lit = torches_lit + 1 end
          if vname == "fc_sconce" then torches_dark = torches_dark + 1 end
          if vname == "fc_torch" then hush.assert(r.lit, r.id .. ": a lit torch in a dark room") end
        end
        for q = 0, 3 do
          local tx, ty = WIN_TX + cx * 2 + (q % 2), WIN_TY + cy * 2 + (q // 2)
          local want = words[q + 1]
          local gw, gv = wram_word(tx, ty), vram_word(tx, ty)
          local where = string.format("%s cell (%d,%d) '%s' [%s] tile (%d,%d)", r.id, cx, cy, r.grid[cy + 1]:sub(cx + 1, cx + 1), k, tx, ty)
          hush.assert_eq(gw, want, where .. ": $7E2000 tilemap word")
          hush.assert_eq(gv, want, where .. ": VRAM tilemap word")
          hush.assert_eq(col_byte(tx, ty), solid, where .. ": collision $7F2000")
        end
      end
    end
    -- palette set: BG rows (CGRAM $20-$FF) identical within a set, different between sets; OBJ half ($100-$1FF) identical everywhere
    local bg, obj = {}, {}
    for a = 0x20, 0xFF do bg[#bg + 1] = emu.read(a, C, false) end
    for a = 0x100, 0x1FF do obj[#obj + 1] = emu.read(a, C, false) end
    local bgs, objs = table.concat(bg, ","), table.concat(obj, ",")
    if not obj_ref then obj_ref = objs end
    hush.assert(objs == obj_ref, r.id .. ": OBJ palettes (guards/Link/icons) differ from room 1 (palette set " .. r.pal_set .. ")")
    if bg_by_set[r.pal_set] then
      hush.assert_eq(bgs, bg_by_set[r.pal_set], r.id .. ": BG palette of set " .. r.pal_set)
    else
      for set, other in pairs(bg_by_set) do hush.assert(other ~= bgs, string.format("palette sets %d and %d have identical BG colours", set, r.pal_set)) end
      bg_by_set[r.pal_set] = bgs
    end
    -- floor colour (BG row 3, index 2 -> CGRAM colour 8+2) is what the director tints per floor / lighting
    local fl = emu.read16(0x60 + 10 * 2, C, false)
    hush.log(string.format("%s floor %d %s: palette set %d floor colour BGR555 %04X", r.id, r.floor, r.lit and "lit " or "dark", r.pal_set, fl))
  end
  -- the test only means something if every kind occurs in the real rooms
  for k, n in pairs(seen) do hush.assert(n > 0, "no '" .. k .. "' cell in any room: the test did not exercise it") end
  for k, n in pairs(vseen) do hush.assert(n > 0, "no decorated '" .. k .. "' cell in any room: the variants were not exercised") end
  hush.assert(torches_lit > 0 and torches_dark > 0, "need lit torches and unlit sconces")
  local sets = 0
  for _ in pairs(bg_by_set) do sets = sets + 1 end
  hush.assert(sets >= 2, "need at least a dark and a lit palette set among the rooms, found " .. sets)
  hush.pass(string.format("%d rooms: %d floor, %d wall top, %d wall face, %d pillar, %d exit cells match (%d decorated: %d floor, %d top, %d face; %d torches, %d sconces); %d palette sets",
    m.count, seen.floor, seen.ceil, seen.face, seen.pillar, seen.exit, vcount, vseen.floor, vseen.ceil, vseen.face, torches_lit, torches_dark, sets))
end)
