-- Smoke (E1): cold boot -> title -> START -> straight into room 1, no file select / name entry / intro.
-- Checks: room $128, module 7 / submodule 0 within 900 frames of START, 3 hearts and full health, tools of
-- room 1, camera locked (bg1 scroll constant while Link walks), Link confined by the grid walls.
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("newgame: title -> START -> room 1", function()
  local m = bot.rooms()
  local r1 = m.rooms[1]
  bot.wait_title()
  hush.wait(10)
  hush.screenshot("00_title")

  hush.press({ "start" }, 4, 4)
  local f = 0
  while not (hush.read("game_mode") == 0x07 and hush.read("submodule") == 0x00) do
    hush.wait(1)
    f = f + 1
    hush.assert(f < 900, string.format("not in the room 900 frames after START (mode=%02X sub=%02X)", hush.read("game_mode"), hush.read("submodule")))
  end
  hush.log("in room after " .. f .. " frames")
  hush.wait(20)
  hush.screenshot("01_room1")

  hush.assert_eq(hush.read("room_id"), m.first_id, "room id")
  hush.assert_eq(hush.read("game_mode"), 0x07, "module")
  hush.assert_eq(hush.read("submodule"), 0x00, "submodule")
  hush.assert_eq(hush.read("hush_room"), 0, "hush_room index")
  hush.assert_eq(hush.read("health_max"), 0x18, "3 hearts")
  hush.assert_eq(hush.read("health"), 0x18, "full health")
  hush.assert_eq(hush.read("link_x"), r1.start_x, "start x")
  hush.assert_eq(hush.read("link_y"), r1.start_y, "start y")
  if r1.tools & 1 ~= 0 then hush.assert_eq(bot.peek(0x7EF359), 1, "sword level (shade_knife)") end

  -- camera is locked to the room window
  local cx, cy = hush.read("bg1_x"), hush.read("bg1_y")
  hush.assert_eq(cx, r1.base_x + m.win_x, "camera x")
  hush.assert_eq(cy, r1.base_y + m.win_y, "camera y")

  -- walk: along the first direction with >= 1 free cell next to S; the camera must not move and Link must stay in the room
  local sx, sy
  for r = 1, 14 do local c = r1.grid[r]:find("S", 1, true); if c then sx, sy = c - 1, r - 1 end end
  local function free(cx2, cy2) local ch = r1.grid[cy2 + 1]:sub(cx2 + 1, cx2 + 1); return ch == "." or ch == "X" end
  local dirs = { { "right", 1, 0 }, { "down", 0, 1 }, { "left", -1, 0 }, { "up", 0, -1 } }
  local moved = false
  for _, d in ipairs(dirs) do
    if free(sx + d[2], sy + d[3]) then
      local x0, y0 = hush.read("link_x"), hush.read("link_y")
      for _ = 1, 8 do
        hush.hold({ d[1] }, 6)
        hush.assert_eq(hush.read("bg1_x"), cx, "camera x while walking")
        hush.assert_eq(hush.read("bg1_y"), cy, "camera y while walking")
        hush.assert_eq(hush.read("game_mode"), 0x07, "still in the room")
        if hush.read("room_id") ~= m.first_id then break end
      end
      moved = (hush.read("link_x") ~= x0) or (hush.read("link_y") ~= y0)
      break
    end
  end
  hush.assert(moved, "Link did not move")
  hush.assert_eq(hush.read("health"), 0x18, "full health after walking")
  hush.screenshot("02_walked")

  -- walls: push into the left border for 3 s; Link must stop inside the window (x >= window left + 16 = grid column 1)
  hush.hold({ "left" }, 180)
  local lx = hush.read("link_x") - r1.base_x - m.win_x
  hush.assert(lx >= 16 or hush.read("room_id") ~= m.first_id, "Link got through the left wall: window x=" .. lx)
  hush.pass(string.format("room $%03X after %d frames; camera (%04X,%04X) locked", hush.read("room_id"), f, cx, cy))
end)
