-- Dev utility (E6): write the real PPU frame buffer (emu.getScreenBuffer, no screenshot lag) of every frame around the caught flash as PPM files.
-- @rom dev
-- @timeout 100
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local function dump(name)
  local buf = emu.getScreenBuffer()
  local w, h = 256, #buf // 256
  local f = io.open(hush.OUT .. "/" .. name .. ".ppm", "wb")
  f:write(string.format("P6 %d %d 255\n", w, h))
  local t, sr, sg, sb = {}, 0, 0, 0
  for i = 1, #buf do
    local p = buf[i]
    local r, g, b = (p >> 16) & 255, (p >> 8) & 255, p & 255
    sr, sg, sb = sr + r, sg + g, sb + b
    t[#t + 1] = string.char(r, g, b)
    if #t > 4096 then f:write(table.concat(t)); t = {} end
  end
  f:write(table.concat(t)); f:close()
  return sr // #buf, sg // #buf, sb // #buf
end
hush.test("flash probe", function()
  ai.enter("ai4_dark")
  ai.link_to(0, 44, 0)
  ai.wait_state(0, ai.S.ALERT, 120)
  local n = 0
  for f = 1, 40 do
    hush.wait(1)
    local fl = hush.read("hush_flash")
    local r, g, b = dump(string.format("f%02d", f))
    local st = emu.getState()
    hush.log(string.format("   ppu: fixed=%s math=%s half=%s addsub=%s sub=%s clip=%s prevent=%s bright=%s main=%s subscr=%s", tostring(st["ppu.fixedColor"]), tostring(st["ppu.colorMathEnabled"]), tostring(st["ppu.colorMathHalveResult"]), tostring(st["ppu.colorMathAddSubscreen"]), tostring(st["ppu.colorMathSubtractMode"]), tostring(st["ppu.colorMathClipMode"]), tostring(st["ppu.colorMathPreventMode"]), tostring(st["ppu.screenBrightness"]), tostring(st["ppu.mainScreenLayers"]), tostring(st["ppu.subScreenLayers"])))
    hush.log(string.format("f%02d flash=%d  $9A=%02X $9C=%02X avg rgb %3d %3d %3d  link_x=%d", f, fl, bot.peek(0x7E009A), bot.peek(0x7E009C), r, g, b, hush.read("link_x")))
  end
  hush.pass()
end)
