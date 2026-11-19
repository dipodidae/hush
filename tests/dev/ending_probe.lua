-- Dev utility (E6): look at the ending screen over time (state, registers, palette, frame buffer as PPM).
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local function dump(name)
  local buf = emu.getScreenBuffer()
  local f = io.open(hush.OUT .. "/" .. name .. ".ppm", "wb")
  f:write(string.format("P6 256 %d 255\n", #buf // 256))
  local t = {}
  for i = 1, #buf do local p = buf[i]; t[#t + 1] = string.char((p >> 16) & 255, (p >> 8) & 255, p & 255); if #t > 4096 then f:write(table.concat(t)); t = {} end end
  f:write(table.concat(t)); f:close()
end
hush.test("ending probe", function()
  local m = bot.rooms()
  bot.start_new_game()
  bot.jump_to_room(m.count - 1); hush.wait(20)
  local x, y = bot.exit_pos(m.rooms[m.count].exits[1]); bot.teleport(x, y)
  for f = 1, 200 do
    hush.wait(1)
    if f % 10 == 0 or (f > 20 and f < 40) then
      local st = emu.getState()
      local cg = {}
      for i = 0, 15 do cg[#cg + 1] = string.format("%04X", emu.read16(i * 2, emu.memType.snesCgRam, false)) end
      hush.log(string.format("f%03d mode=%02X B0=%02X $13=%02X TM=%02X etimer=%d bright=%s forced=%s cg=%s", f, hush.read("game_mode"), bot.peek(0x7E00B0), bot.peek(0x7E0013), bot.peek(0x7E001C), bot.peek(0x7EC917), tostring(st["ppu.screenBrightness"]), tostring(st["ppu.forcedBlank"]), table.concat(cg, " ")))
      if f % 20 == 0 then dump(string.format("e%03d", f)) end
    end
  end
  hush.pass()
end)
