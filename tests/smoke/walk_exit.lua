-- Smoke (E1): the bot walks (real button presses) from S to the nearest exit cell of the first guard-free room
-- and the controller advances to the next room.
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("walk_exit: walking to the exit loads the next room", function()
  local m = bot.rooms()
  local pick
  for i = 1, m.count - 1 do
    if #m.rooms[i].guards == 0 then pick = i; break end
  end
  if not pick then hush.pass("no guard-free room before the last one: nothing to walk"); return end
  bot.start_new_game()
  bot.jump_to_room(pick - 1)
  hush.wait(10)
  local r = m.rooms[pick]
  hush.assert_eq(hush.read("link_x"), r.start_x, "at start")
  bot.walk_exit(r)
  local t = 0
  while hush.read("room_id") ~= m.rooms[pick + 1].room_id do
    hush.wait(1); t = t + 1
    hush.assert(t < 120, string.format("walked the path of %s but the room did not change (link=%d,%d)", r.id, hush.read("link_x"), hush.read("link_y")))
  end
  hush.pass(r.id .. " -> next room by walking")
end)
