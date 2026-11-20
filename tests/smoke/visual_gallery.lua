-- Smoke (T0, design/tiles.md section 8): the tile GALLERY room (tests/dev/rooms/gallery.yaml: every wall / floor / pit / water autotile case, doorway, pillar, exit) is on screen exactly as
-- tools/autotile.py computed it (rooms_gen.lua `words`), and its collision equals the grid ('#' 'p' 'O' 'W' solid, 'D' walkable).
-- @rom dev
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W, V = emu.memType.snesWorkRam, emu.memType.snesVideoRam
local WIN_TX, WIN_TY = 16, 18
local function solid_of(ch) return (ch == "#" or ch == "p" or ch == "O" or ch == "W") and 1 or 0 end

-- BG2 tilemap in VRAM: 64x64 entries = four 32x32 screens (SC0 TL, SC1 TR, SC2 BL, SC3 BR), 0x400 words each, at VRAM byte $0000.
local function vram_word(tx, ty)
  local screen = (ty >= 32 and 2 or 0) + (tx >= 32 and 1 or 0)
  return emu.read16(((screen * 0x400) + (ty % 32) * 32 + (tx % 32)) * 2, V, false)
end
local function wram_word(tx, ty) return emu.read16(0x2000 + (ty * 64 + tx) * 2, W, false) end
local function col_byte(tx, ty) return emu.read(0x12000 + ty * 64 + tx, W, false) end   -- $7F2000 = WRAM offset $12000 (64x64 bytes)

hush.test("visual_gallery: gallery room words + collision", function()
  local m = bot.rooms()
  bot.start_new_game()
  local idx
  for i = 1, m.count do if m.rooms[i].id == "gallery" then idx = i end end
  hush.assert(idx ~= nil, "no gallery room in the dev rooms")
  local r = m.rooms[idx]
  bot.jump_to_room(idx - 1)
  hush.wait(60)
  local pits, water = 0, 0
  for ty = 0, 27 do
    for tx = 0, 31 do
      local ch = r.grid[ty // 2 + 1]:sub(tx // 2 + 1, tx // 2 + 1)
      local want = r.words[ty + 1][tx + 1]
      local where = string.format("gallery tile (%d,%d) '%s'", tx, ty, ch)
      hush.assert_eq(wram_word(WIN_TX + tx, WIN_TY + ty), want, where .. ": $7E2000 word")
      hush.assert_eq(vram_word(WIN_TX + tx, WIN_TY + ty), want, where .. ": VRAM word")
      hush.assert_eq(col_byte(WIN_TX + tx, WIN_TY + ty), solid_of(ch), where .. ": collision")
      if ch == "O" then pits = pits + 1 end
      if ch == "W" then water = water + 1 end
    end
  end
  hush.assert(pits > 0 and water > 0, "the gallery needs pit and water cells")
  hush.pass(string.format("gallery: 896 tiles match; %d pit tiles, %d water tiles solid", pits, water))
end)
