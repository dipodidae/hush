-- Smoke (stealth meter, criterion 10, HUD): pillars.md:118-120 "HUD (BG3 tilemap row 3, cols 20-27): at 32 all 8 cells show the
-- filled tile; at 20 exactly 5 filled + 3 drained; at 8 or less the filled cells change palette every 16 frames."
-- Also pillars.md:86-96: 1 cell = 4 units; hit flash = the lost cells amber for 16 frames, then drained; never amber at full or
-- healthy meter (so at 32 and 20 the cells do not change).
-- Tile numbers are the engine's / art's choice and are NOT hardcoded: the test compares cells with each other.
-- Read from the HUD buffer ($7EC768 + 2*i, docs/gfx/hud_map.md:12,37; tests/lib/meter.lua) and checked against the BG3 tilemap in VRAM.
-- The meter is lowered by real hits: 3 guards of ai8_crowd noticing at once = -12 (32 -> 20), 3 more = -12 (20 -> 8).
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

local BLANK = 0x207F                         -- the HUD blank cell (tests/smoke/hud.lua)

local function same_as_vram(what)
  local b, v = meter.cells(), meter.vram_cells()
  for i = 0, 7 do
    hush.assert_eq(v[i], b[i], string.format("%s: VRAM cell (%d,3) shows the HUD buffer word", what, 20 + i))
  end
end

local function steady(frames, what)
  local c0 = meter.cells()
  for f = 1, frames do
    hush.wait(1)
    local c = meter.cells()
    for i = 0, 7 do
      hush.assert_eq(c[i], c0[i], string.format("%s: cell %d unchanged for %d frames (no amber at a healthy meter, pillars.md:95), frame %d", what, i, frames, f))
    end
  end
end

hush.test("meter_hud: 8 filled at 32, 5+3 at 20, blinking at 8 (criterion 10)", function()
  ai.enter("ai8_crowd")
  ai.link_to(0, 160, 0)
  hush.wait(20)
  hush.assert_eq(meter.get(), 32, "full meter (pillars.md:100)")

  -- 32: eight identical, non-blank cells
  local c = meter.cells()
  hush.log("HUD at 32: " .. meter.fmt(c))
  hush.assert(c[0] ~= BLANK, "at 32 cell 0 is not blank (pillars.md:86-89)")
  for i = 1, 7 do
    hush.assert_eq(c[i], c[0], "at 32 all 8 cells show the same filled tile: cell " .. i .. " vs cell 0 (criterion 10, pillars.md:118)")
  end
  local FILLED = c[0]
  same_as_vram("at 32")
  steady(40, "at 32")

  -- 32 -> 20 (three ? at once)
  meter.notice(0); meter.notice(1); meter.notice(2)
  hush.wait(3)
  hush.assert_eq(meter.get(), 20, "precondition: three notices = -12 (criteria 2, 6)")
  local fl = meter.cells()
  hush.log("HUD during the hit flash: " .. meter.fmt(fl) .. " mflash=" .. hush.read("hush_mflash") .. " mlost=" .. hush.read("hush_mlost"))
  hush.wait(30)                              -- the 16-frame flash is over (pillars.md:92)
  c = meter.cells()
  hush.log("HUD at 20: " .. meter.fmt(c))
  for i = 0, 4 do hush.assert_eq(c[i], FILLED, "at 20 cell " .. i .. " is filled (criterion 10, pillars.md:119)") end
  local DRAINED = c[5]
  hush.assert(DRAINED ~= FILLED, "at 20 cell 5 differs from the filled cells (drained, criterion 10)")
  hush.assert(DRAINED ~= BLANK, "the drained cell is an empty container, not blank (pillars.md:90-91)")
  for i = 6, 7 do hush.assert_eq(c[i], DRAINED, "at 20 cell " .. i .. " is drained like cell 5 (criterion 10)") end
  for i = 5, 7 do
    hush.assert(fl[i] ~= DRAINED and fl[i] ~= FILLED, "during the hit flash the lost cell " .. i .. " is neither filled nor drained (amber, pillars.md:92)")
  end
  same_as_vram("at 20")
  steady(40, "at 20")

  -- 20 -> 8 (three more ?): low meter
  meter.notice(3); meter.notice(4); meter.notice(5)
  hush.wait(3)
  hush.assert_eq(meter.get(), 8, "precondition: three more notices = -12")
  hush.wait(20)                              -- past the hit flash
  local pals, changes, last = {}, {}, nil
  for f = 1, 64 do
    hush.wait(1)
    c = meter.cells()
    hush.assert_eq(c[0] & 0xE3FF, FILLED & 0xE3FF, "at 8 cell 0 keeps the filled tile (only the palette alternates), frame " .. f)
    hush.assert_eq(c[1], c[0], "at 8 cells 0 and 1 (the 2 filled) look the same, frame " .. f)
    for i = 2, 7 do hush.assert_eq(c[i], DRAINED, "at 8 cell " .. i .. " is drained, frame " .. f) end
    local p = meter.pal(c[0])
    pals[#pals + 1] = p
    if last ~= nil and p ~= last then changes[#changes + 1] = f end
    last = p
  end
  hush.log("palette of the filled cells at 8, 64 frames: " .. table.concat(pals, "") .. "; changes at " .. table.concat(changes, ","))
  hush.assert(#changes >= 1 and changes[1] <= 32, "at 8 the filled cells change palette within 32 frames (criterion 10, pillars.md:120)")
  for k = 2, #changes do
    local d = changes[k] - changes[k - 1]
    hush.assert(d >= 15 and d <= 17, "the filled cells alternate every 16 frames (pillars.md:93-94), interval " .. d)
  end
  hush.assert(not ai.caught(), "precondition: never caught")
  hush.pass("HUD: 8 filled at 32, 5 + 3 at 20, filled cells blink every 16 frames at 8")
end)
