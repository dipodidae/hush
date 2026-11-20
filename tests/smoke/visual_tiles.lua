-- Smoke (T0, design/tiles.md): the autotiled room really is on screen and collision equals the grid.
--   * for every real room (design/rooms, build/hush.sfc) the BG2 tilemap buffer ($7E2000) AND the BG2 tilemap in VRAM hold, for every one of the 32x28 tiles of the
--     window, exactly the word tools/roomgen.py computed (rooms_gen.lua `words`: tools/autotile.py autotile + decoration);
--   * the collision map $7F2000 equals the GRID: `#` `p` `O` `W` solid ($01 on all four 8x8 tiles of the cell), everything else floor ($00). For the 21 shipped rooms this is the
--     same map the pre-T0 build produced (only `#` and `p` occur), so collision cannot have regressed. Also equals rooms_gen.lua `solid`;
--   * the palette set follows floor / lighting (CGRAM BG rows differ between sets, the OBJ half of CGRAM is identical in every room).
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W, V, C = emu.memType.snesWorkRam, emu.memType.snesVideoRam, emu.memType.snesCgRam
local WIN_TX, WIN_TY = 16, 18          -- window origin in 8x8 tiles (tools/roomgen.py WIN_X/8, WIN_Y/8)

local function solid_of(ch) return (ch == "#" or ch == "p" or ch == "O" or ch == "W") and 1 or 0 end

-- BG2 tilemap in VRAM: 64x64 entries = four 32x32 screens (SC0 TL, SC1 TR, SC2 BL, SC3 BR), 0x400 words each, at VRAM byte $0000.
local function vram_word(tx, ty)
  local screen = (ty >= 32 and 2 or 0) + (tx >= 32 and 1 or 0)
  return emu.read16(((screen * 0x400) + (ty % 32) * 32 + (tx % 32)) * 2, V, false)
end
local function wram_word(tx, ty) return emu.read16(0x2000 + (ty * 64 + tx) * 2, W, false) end
local function col_byte(tx, ty) return emu.read(0x12000 + ty * 64 + tx, W, false) end   -- $7F2000 = WRAM offset $12000 (64x64 bytes)

hush.test("visual_tiles: autotiled tilemap words, grid collision, palette sets", function()
  local m = bot.rooms()
  bot.start_new_game()
  local distinct, nwords, nsolid = {}, 0, 0
  local obj_ref, bg_by_set = nil, {}
  for i = 1, m.count do
    local r = m.rooms[i]
    bot.jump_to_room(i - 1)
    hush.wait(60)
    for ty = 0, 27 do
      for tx = 0, 31 do
        local cx, cy = tx // 2, ty // 2
        local ch = r.grid[cy + 1]:sub(cx + 1, cx + 1)
        local want = r.words[ty + 1][tx + 1]
        local where = string.format("%s tile (%d,%d) cell (%d,%d) '%s'", r.id, tx, ty, cx, cy, ch)
        hush.assert_eq(wram_word(WIN_TX + tx, WIN_TY + ty), want, where .. ": $7E2000 tilemap word")
        hush.assert_eq(vram_word(WIN_TX + tx, WIN_TY + ty), want, where .. ": VRAM tilemap word")
        hush.assert_eq(col_byte(WIN_TX + tx, WIN_TY + ty), solid_of(ch), where .. ": collision $7F2000 vs the grid")
        hush.assert_eq(r.solid[ty + 1][tx + 1], solid_of(ch), where .. ": rooms_gen.lua solid vs the grid")
        distinct[want] = true
        nwords = nwords + 1
        nsolid = nsolid + solid_of(ch)
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
  end
  local nd = 0
  for _ in pairs(distinct) do nd = nd + 1 end
  hush.assert(nd >= 20, "only " .. nd .. " distinct tile words over all rooms: the autotile is not exercised")
  local sets = 0
  for _ in pairs(bg_by_set) do sets = sets + 1 end
  hush.assert(sets >= 2, "need at least a dark and a lit palette set among the rooms, found " .. sets)
  hush.pass(string.format("%d rooms: %d tiles match the autotile words (%d distinct), %d solid tiles match the grid; %d palette sets", m.count, nwords, nd, nsolid, sets))
end)
