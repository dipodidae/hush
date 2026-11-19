-- Smoke (E1): touching an exit cell of room 1 loads room 2 ($129); touching the exit of the last room returns to the
-- title screen; Hush_RestartRoom/same-room request reloads the room and restores killed guards.
-- Teleports Link into the exit rect (bot.exit_pos); the walking version is smoke/walk_exit.lua.
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("room_advance: exit cell -> next room", function()
  local m = bot.rooms()
  bot.start_new_game()
  hush.assert_eq(hush.read("room_id"), m.first_id, "starts in room 1")
  hush.screenshot("room1")

  -- advance through every room except the last by teleporting onto the exit
  for i = 1, m.count - 1 do
    local r = m.rooms[i]
    hush.assert_eq(hush.read("room_id"), r.room_id, "in room " .. i)
    local x, y = bot.exit_pos(r.exits[1])
    bot.teleport(x, y)
    local f0 = hush.frame()
    local t = 0
    while hush.read("room_id") ~= m.rooms[i + 1].room_id do
      hush.wait(1); t = t + 1
      hush.assert(t < 120, string.format("room %d: exit touched but room id stayed $%03X", i, hush.read("room_id")))
    end
    bot.wait_control()
    hush.log(string.format("room %d -> %d: new id after %d frames, Link controllable after %d frames", i, i + 1, t, hush.frame() - f0))
    hush.assert_eq(hush.read("hush_room"), i, "hush_room index after advance")
    hush.assert_eq(hush.read("link_x"), m.rooms[i + 1].start_x, "start x of next room")
    hush.assert_eq(hush.read("link_y"), m.rooms[i + 1].start_y, "start y of next room")
    hush.assert_eq(hush.read("health"), 0x18, "full health")
    hush.wait(10)
    hush.screenshot(string.format("room%d", i + 1))
  end

  -- cumulative tools in the last room
  local last = m.rooms[m.count]
  if last.tools & 1 ~= 0 then hush.assert_eq(bot.peek(0x7EF359), 1, "sword in last room") end
  if last.tools & 2 ~= 0 then hush.assert_eq(bot.peek(0x7EF340), 2, "bow in last room"); hush.assert_eq(bot.peek(0x7EF377), 8, "arrows") end
  if last.tools & 4 ~= 0 then hush.assert_eq(bot.peek(0x7EF343), 8, "bombs (ink pots)") end

  -- restart: request the current room; killed-guard flags of the room are cleared, Link is back at the start
  local rid = hush.read("room_id")
  local idx = hush.read("hush_room")
  local flag_addr = 0x7FDF80 + 2 * rid
  emu.write(flag_addr - 0x7E0000, 0xFF, emu.memType.snesWorkRam)   -- pretend every guard of the room was killed
  bot.teleport(last.start_x + 48, last.start_y)
  bot.jump_to_room(idx)
  hush.assert_eq(hush.read("room_id"), rid, "same room after restart")
  hush.assert_eq(hush.read("link_x"), last.start_x, "restart: Link back at start x")
  hush.assert_eq(bot.peek(flag_addr), 0, "restart: sprite death flags cleared")
  hush.screenshot("restart")

  -- the last exit ends the game: back to the title (module 0 / submodule 8), and a new game starts again
  local x, y = bot.exit_pos(last.exits[1])
  bot.teleport(x, y)
  local t = 0
  while not (hush.read("game_mode") == 0x00 and hush.read("submodule") == 0x08) do
    hush.wait(1); t = t + 1
    hush.assert(t < 900, string.format("ending: title not reached (mode=%02X sub=%02X)", hush.read("game_mode"), hush.read("submodule")))
  end
  hush.log("title again after " .. t .. " frames")
  hush.screenshot("ending_title")
  hush.wait(10)
  hush.press({ "start" }, 4, 4)
  bot.wait_control()
  hush.assert_eq(hush.read("room_id"), m.first_id, "second game starts in room 1 again")
  hush.assert_eq(hush.read("health"), 0x18, "second game: full health")
  hush.pass(m.count .. " rooms advanced, restart ok, ending -> title -> new game ok")
end)
