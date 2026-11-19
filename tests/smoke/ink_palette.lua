-- Smoke (E6): the ink cloud palette (OBJ row 1 = CGRAM 144-159, asm Hush_PalInk): colours 6 and 7 are teal-cyan ($6B6B = 5ED8D0, $77D3 = 9CF0E8),
-- the smoke colours 1-5 stay indigo / violet. Screenshots of the real cloud (throw an ink pot) go to the result directory.
-- Rooms with ink pots: r10 (index 9).
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local C = emu.memType.snesCgRam
local function col(row, i) return emu.read16((128 + 16 * row + i) * 2, C, false) end

hush.test("ink palette: teal-cyan specks", function()
  bot.start_new_game()
  bot.jump_to_room(9)
  hush.wait(20)
  hush.assert_eq(col(1, 6), 0x6B6B, "ink row colour 6 = 5ED8D0")
  hush.assert_eq(col(1, 7), 0x77D3, "ink row colour 7 = 9CF0E8")
  hush.assert_eq(col(1, 4), 0x30A5, "colour 4 (smoke) stays indigo")
  hush.assert_eq(col(1, 5), 0x4CE9, "colour 5 (rim) stays violet")
  hush.assert(bot.peek(0x7EF343) > 0, "Link has ink pots")
  bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1)
  hush.press({ "y" }, 3, 1)
  hush.wait(190)
  hush.screenshot("ink_cloud")
  hush.wait(8)
  hush.screenshot("ink_cloud2")
  hush.pass("ink row colours 6 / 7 = 5ED8D0 / 9CF0E8")
end)
