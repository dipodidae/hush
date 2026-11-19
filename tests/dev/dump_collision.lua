-- Dev utility (not a test): screenshot + collision map ($7F2000 tile types, hex) of the window of room 1.
--   .venv/bin/python tools/run_test.py tests/dev/dump_collision.lua   (HUSH_ROM=... to dump another ROM)
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam
hush.test("probe coll", function()
  bot.start_new_game()
  hush.wait(30)
  hush.screenshot("room")
  local lines = {}
  for ty = 18, 45 do
    local row = {}
    for tx = 16, 47 do
      local v = emu.read(0x12000 + ty * 64 + tx, W, false)
      row[#row + 1] = v == 0 and "." or string.format("%X", v % 16)
    end
    lines[#lines + 1] = string.format("%02d ", ty) .. table.concat(row)
  end
  print(table.concat(lines, "\n"))
  hush.pass()
end)
