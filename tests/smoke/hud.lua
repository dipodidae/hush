-- Smoke (E6): HUD cleanup. The gem counter is never shown; the ink pot / dart counters (icon + digits) only once the room's cumulative tool
-- mask has the tool (bit 2 / bit 1). Read from the BG3 tilemap in VRAM (HUD row r of the screen = word $6000 + 32 r + col, docs/gfx/hud_map.md section 2):
-- gem icon (9,2), digits (8..10,3); ink icon (12,2) (13,2), digits (12,3) (13,3); dart icon (15,2) (16,2), digits (15,3) (16,3). Hearts at (20.., 3) and the item box stay.
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local V = emu.memType.snesVideoRam
local function cell(col, row) return emu.read16((0x6000 + 32 * row + col) * 2, V, false) end
local BLANK = 0x207F
local function all_blank(cells)
  for _, c in ipairs(cells) do if cell(c[1], c[2]) ~= BLANK then return false, c end end
  return true
end
local GEM  = { { 9, 2 }, { 8, 3 }, { 9, 3 }, { 10, 3 } }
local INK  = { { 12, 2 }, { 13, 2 }, { 12, 3 }, { 13, 3 } }
local DART = { { 15, 2 }, { 16, 2 }, { 15, 3 }, { 16, 3 } }
local function any_visible(cells)
  for _, c in ipairs(cells) do if cell(c[1], c[2]) ~= BLANK then return true end end
  return false
end

hush.test("hud: no gems; ink / dart counters only with the tool", function()
  local m = bot.rooms()
  bot.start_new_game()
  for _, case in ipairs({ { 0, "r01", false, false }, { 2, "r03", false, false }, { 6, "r07", true, false }, { 9, "r10", true, true }, { m.count - 1, "final", true, true } }) do
    local idx, name, darts, ink = case[1], case[2], case[3], case[4]
    bot.jump_to_room(idx)
    hush.wait(12)
    local r = m.rooms[idx + 1]
    hush.assert_eq((r.tools & 2) ~= 0, darts, name .. ": table says darts " .. tostring(darts))
    hush.assert_eq((r.tools & 4) ~= 0, ink, name .. ": table says ink " .. tostring(ink))
    local ok, c = all_blank(GEM)
    hush.assert(ok, name .. ": gem counter blank (cell " .. tostring(c and c[1]) .. "," .. tostring(c and c[2]) .. " = " .. string.format("%04X", c and cell(c[1], c[2]) or 0) .. ")")
    hush.assert_eq(any_visible(DART), darts, name .. ": dart counter visible = " .. tostring(darts))
    hush.assert_eq(any_visible(INK), ink, name .. ": ink counter visible = " .. tostring(ink))
    -- hearts (20..22, 3) and the item box corners stay
    hush.assert(cell(20, 3) ~= BLANK and cell(21, 3) ~= BLANK and cell(22, 3) ~= BLANK, name .. ": three hearts")
    hush.assert(cell(4, 2) ~= BLANK and cell(7, 2) ~= BLANK, name .. ": item box")
    hush.screenshot("hud_" .. name)
  end
  -- also during the fade-in after a load (no flash of the old HUD): sample the first frame of submodule $0F
  bot.poke(0x7EC901, 1); local seen = false
  for _ = 1, 60 do
    hush.wait(1)
    if hush.read("submodule") == 0x0F and bot.peek(0x7E0013) < 0x80 then
      seen = true
      hush.wait(1)       -- the pass that sets the first non-blank brightness is displayed one frame later, together with the clean HUD upload
      hush.assert(hush.read("submodule") == 0x0F and bot.peek(0x7E0013) < 0x80, "still fading in")
      hush.assert(all_blank(GEM), "gem counter blank on the first visible fade-in frame")
      break
    end
  end
  hush.assert(seen, "saw the fade-in")
  hush.pass("gem counter never shown; ink / dart counters follow the tools")
end)
