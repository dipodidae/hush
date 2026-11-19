-- tools/art/dump_rooms.lua : dump VRAM/CGRAM/OAM/PPU of every HUSH room (research helper for docs/gfx/art_map.md).
--   .venv/bin/python tools/run_test.py tools/art/dump_rooms.lua      (output: build/test-results/tools_art_dump_rooms or dump_rooms)
-- For each room N: room_NN.{vram,cgram,oam,ppu.txt,png} + room_NN.wram (the gfx-set bytes $0AA0-$0AA7 and $7EC2F8-FB)
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

hush.test("art dump: every room", function()
  bot.start_new_game()
  local n = #bot.rooms().rooms
  local W = emu.memType.snesWorkRam
  for i = 0, n - 1 do
    bot.jump_to_room(i)
    hush.wait(50)
    local name = string.format("room_%02d", i)
    gfx.snap(name)
    local f = assert(io.open(hush.OUT .. "/" .. name .. ".wram", "w"))
    local function row(label, base, len)
      local t = {}
      for k = 0, len - 1 do t[#t + 1] = string.format("%02X", emu.read(base + k, W, false)) end
      f:write(label .. "=" .. table.concat(t, " ") .. "\n")
    end
    row("0AA0", 0x0AA0, 8)
    row("C2F8", 0xC2F8, 8)
    row("0AB0", 0x0AB0, 8)
    f:close()
  end
  hush.pass("dumped " .. n .. " rooms")
end)
