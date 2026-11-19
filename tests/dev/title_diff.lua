-- Dev utility (E6): the title screen after a cold boot vs after the ending screen: direct page, PPU state, VRAM BG tilemap words.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam
local function snap()
  local dp = {}
  for i = 0, 0xFF do dp[i] = emu.read(i, W, false) end
  local st = emu.getState()
  local keys = { "bgMode", "mainScreenLayers", "subScreenLayers", "mosaicSize", "colorMathEnabled", "windowMaskMain", "forcedBlank", "screenBrightness",
    "layers[0].hscroll", "layers[0].vscroll", "layers[1].hscroll", "layers[1].vscroll", "layers[2].hscroll", "layers[2].vscroll", "layers[0].tilemapAddress", "layers[1].tilemapAddress", "layers[2].tilemapAddress", "layers[0].chrAddress", "layers[2].chrAddress", "layers[0].doubleWidth", "layers[0].doubleHeight" }
  local ppu = {}
  for _, k in ipairs(keys) do ppu[k] = tostring(st["ppu." .. k]) end
  return dp, ppu
end
hush.test("title diff", function()
  bot.wait_title(); hush.wait(60)
  local dp1, ppu1 = snap()
  hush.screenshot("title_cold")
  hush.press({ "start" }, 4, 4); bot.wait_control()
  local m = bot.rooms()
  bot.jump_to_room(m.count - 1); hush.wait(20)
  local x, y = bot.exit_pos(m.rooms[m.count].exits[1]); bot.teleport(x, y)
  hush.wait(130); hush.press({ "start" }, 3, 1)
  bot.wait_title(); hush.wait(60)
  local dp2, ppu2 = snap()
  hush.screenshot("title_after")
  local l = {}
  for i = 0, 0xFF do if dp1[i] ~= dp2[i] then l[#l + 1] = string.format("$%02X:%02X/%02X", i, dp1[i], dp2[i]) end end
  hush.log("dp diffs (cold/after): " .. table.concat(l, " "))
  for k, v in pairs(ppu1) do if v ~= ppu2[k] then hush.log("ppu " .. k .. ": " .. v .. " vs " .. ppu2[k]) end end
  hush.pass()
end)
