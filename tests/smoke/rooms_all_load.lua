-- Smoke (E1): every compiled room loads through the debug jump (hush_room_req), is in module 7 / submodule 0 with the
-- right room id, start position, camera and guards, and survives 120 frames. One screenshot per room.
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("rooms_all_load: every room loads", function()
  local m = bot.rooms()
  bot.start_new_game()
  for i = 1, m.count do
    local r = m.rooms[i]
    bot.jump_to_room(i - 1)
    hush.wait(120)
    hush.assert_eq(hush.read("game_mode"), 0x07, r.id .. ": module")
    hush.assert_eq(hush.read("room_id"), r.room_id, r.id .. ": room id")
    hush.assert_eq(hush.read("hush_room"), i - 1, r.id .. ": hush_room")
    hush.assert_eq(hush.read("bg1_x"), r.base_x + m.win_x, r.id .. ": camera x")
    hush.assert_eq(hush.read("bg1_y"), r.base_y + m.win_y, r.id .. ": camera y")
    hush.assert_eq(hush.read("health"), 0x18, r.id .. ": health")
    local guards = 0
    for s = 0, 15 do
      local t = hush.read("spr_type", s)
      if hush.read("spr_state", s) ~= 0 and t >= 0x41 and t <= 0x43 then guards = guards + 1 end
    end
    hush.assert(guards >= #r.guards, string.format("%s: %d guard sprite(s), expected >= %d", r.id, guards, #r.guards))
    hush.screenshot(string.format("room%02d_%s", i, r.id))
  end
  -- out-of-range request is ignored
  bot.poke(0x7EC901, m.count + 5)
  hush.wait(5)
  hush.assert_eq(hush.read("room_id"), m.rooms[m.count].room_id, "out-of-range hush_room_req ignored")
  hush.pass(m.count .. " room(s) loaded")
end)
