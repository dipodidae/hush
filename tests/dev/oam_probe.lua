-- Dev utility: list the visible OAM entries of a dev room (tile, attr, x, y, size) and the guard sprite variables.
--   HUSH_PROBE_ROOM=ai7_patrol .venv/bin/python tools/run_test.py tests/dev/oam_probe.lua
-- @rom dev
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
hush.test("oam probe", function()
  ai.enter(os.getenv("HUSH_PROBE_ROOM") or "ai7_patrol")
  hush.wait(60)
  local n = 0
  for i = 0, 127 do
    local b = 0x7E0800 + i * 4
    local x, y, t, a = bot.peek(b), bot.peek(b + 1), bot.peek(b + 2), bot.peek(b + 3)
    local bits = bot.peek(0x7E0A20 + i) & 3   -- unpacked high table: one byte per entry ($92),Y with Y = offset / 4
    if y < 0xE0 then
      n = n + 1
      hush.log(string.format("oam %3d tile=%02X attr=%02X x=%3d%s y=%3d %s", i, t, a, x, (bits & 1) ~= 0 and "+256" or "", y, (bits & 2) ~= 0 and "16x16" or "8x8"))
    end
  end
  hush.log("visible entries: " .. n)
  for s = 0, 3 do hush.log(string.format("slot %d type=%02X state=%d aware=%d dir=%d x=%d y=%d e40=%02X", s, bot.peek(0x7E0E20 + s), bot.peek(0x7E0DD0 + s), bot.peek(0x7E0D80 + s), bot.peek(0x7E0DE0 + s), hush.sprite(s).x, hush.sprite(s).y, bot.peek(0x7E0E40 + s))) end
  hush.screenshot("probe")
  hush.pass()
end)
