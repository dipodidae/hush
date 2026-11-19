package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("p", function()
  bot.start_new_game(); hush.wait(30)
  local V = emu.memType.snesVideoRam
  for i = 1, 5 do
    hush.log(string.format("$16=%02X buf750=%04X buf712=%04X vram(8,3)=%04X vram(9,2)=%04X  dma-dest $0219=%04X", bot.peek(0x7E0016), emu.read16(0xC750, emu.memType.snesWorkRam, false), emu.read16(0xC712, emu.memType.snesWorkRam, false), emu.read16((0x6000+32*3+8)*2, V, false), emu.read16((0x6000+32*2+9)*2, V, false), emu.read16(0x219, emu.memType.snesWorkRam, false)))
    hush.wait(10)
  end
  hush.pass()
end)
