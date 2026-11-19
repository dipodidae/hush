-- Dev utility (E6): does the item menu (START) leave VRAM as it found it? The fast room load assumes the room graphics in VRAM are intact.
--   .venv/bin/python tools/run_test.py tests/dev/menu_vram.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local V = emu.memType.snesVideoRam
local function vram()
  local t = {}
  for i = 0, 0xFFFF do t[i] = emu.read(i, V, false) end
  return t
end
local function ndiff(a, b)
  local n, first, lastw = 0, nil, nil
  local regions = {}
  for i = 0, 0xFFFF do
    if a[i] ~= b[i] then
      n = n + 1
      local r = (i >> 11) << 11
      regions[r] = (regions[r] or 0) + 1
    end
  end
  local l = {}
  for r, c in pairs(regions) do l[#l + 1] = string.format("$%04X:%d", r, c) end
  table.sort(l)
  return n, table.concat(l, " ")
end
hush.test("menu vram", function()
  bot.start_new_game()
  bot.jump_to_room(6)       -- darts room: the item menu has something to show
  hush.wait(30)
  local a = vram()
  hush.press({ "start" }, 3, 1)
  hush.wait(90)
  hush.log("module in menu: " .. string.format("%02X", hush.read("game_mode")))
  hush.screenshot("menu_open")
  local m = vram()
  hush.log("VRAM bytes changed while the menu is open: " .. ndiff(a, m))
  hush.press({ "start" }, 3, 1)
  hush.wait(90)
  hush.assert_eq(hush.read("game_mode"), 7, "back in the room")
  local b = vram()
  local n, regs = ndiff(a, b)
  hush.log("VRAM bytes changed after closing the menu: " .. n .. "  (2 KiB regions: " .. regs .. ")")
  hush.screenshot("menu_closed")
  hush.pass()
end)
