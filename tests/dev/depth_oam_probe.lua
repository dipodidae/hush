-- Dev utility (QA, not a test): OAM entries near Link and near each guard, with their priority bits (attr bits 4-5), for the
-- depth rule (design/tiles.md 2.1 rule 3). Used to pin how tests/smoke/depth_oam.lua identifies Link's entries.
--   .venv/bin/python tools/run_test.py tests/dev/depth_oam_probe.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("depth oam probe", function()
  bot.start_new_game()
  local m = bot.rooms()
  local idx
  for i, r in ipairs(m.rooms) do if r.id == "r14" then idx = i - 1 end end
  bot.jump_to_room(idx)
  hush.wait(20)
  for s = 0, 15 do
    if hush.read("spr_type", s) == 0x41 and hush.read("spr_state", s) == 9 then
      bot.poke(0x7E0D80 + s, 1); hush.write("hush_aprev", 1, s); bot.poke(0x7E0E10 + s, 250)
    end
  end
  hush.wait(2)
  local lx, ly = hush.read("link_x") - bot.peek(0x7E00E2) - 256 * bot.peek(0x7E00E3), hush.read("link_y") - bot.peek(0x7E00E8) - 256 * bot.peek(0x7E00E9)
  hush.log(string.format("link screen (%d,%d)", lx, ly))
  for s = 0, 7 do
    local sp = hush.sprite(s)
    if sp.type == 0x41 then hush.log(string.format("guard slot %d screen (%d,%d) aware %d", s, sp.x - bot.peek(0x7E00E2) - 256 * bot.peek(0x7E00E3), sp.y - bot.peek(0x7E00E8) - 256 * bot.peek(0x7E00E9), bot.peek(0x7E0D80 + s))) end
  end
  for i = 0, 127 do
    local b = 0x7E0800 + i * 4
    local x, y, t, a = bot.peek(b), bot.peek(b + 1), bot.peek(b + 2), bot.peek(b + 3)
    local bits = bot.peek(0x7E0A20 + i) & 3
    if y < 0xE0 then
      hush.log(string.format("oam %3d tile=%02X attr=%02X prio=%d pal=%d nt=%d x=%3d%s y=%3d %s", i, t, a, (a >> 4) & 3, (a >> 1) & 7, a & 1, x,
        (bits & 1) ~= 0 and "+256" or "", y, (bits & 2) ~= 0 and "16x16" or "8x8"))
    end
  end
  hush.screenshot("probe")
  hush.pass()
end)
