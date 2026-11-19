-- Smoke (E2): patrol. Room ai7_patrol (dark): guard 1 `move: patrol` faces east on the south row; it walks (0.75 px/frame),
-- stops when it hits the wall, pauses 60 frames, turns 180 degrees and walks back. Guard 2 `move: still` never moves.
-- Link waits far away at the start (out of both guards' cones).
-- @rom dev
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

hush.test("ai_patrol: patrol turns at the wall after 60 frames, still never moves", function()
  local room = ai.enter("ai7_patrol")
  local x0, y0 = ai.pos(0)
  local bx0, by0 = ai.pos(1)
  hush.assert_eq(ai.dir(0), 0, "patrol guard faces east")
  hush.assert_eq(ai.dir(1), 3, "still guard faces north")
  hush.assert_eq(bot.peek(0x7E0E30), 2, "patrol guard sub-type: facing east (2), not still")
  hush.assert_eq(bot.peek(0x7E0E31), 3 + 8, "still guard sub-type: facing north (3) + still bit (8)")

  -- speed: 60 frames of walking
  hush.wait(60)
  local x60 = ai.pos(0)
  hush.log("patrol: " .. (x60 - x0) .. " px in 60 frames")
  hush.assert(x60 - x0 >= 40 and x60 - x0 <= 50, "about 0.75 px/frame (45 px in 60 frames), got " .. (x60 - x0))
  hush.assert_eq(select(2, ai.pos(0)), y0, "walks straight")

  -- walk to the east wall
  local reached
  for f = 1, 400 do
    hush.wait(1)
    if bot.peek(0x7E0D90) == 1 then reached = f; break end       -- spr_aux = 1: pausing at the wall
  end
  hush.assert(reached ~= nil, "the guard reaches the wall and pauses")
  local xw = ai.pos(0)
  local wall = room.guards[1].x - 32 + 240   -- (spawn x; cell 2 = window x 32) the east wall tile starts at window x 240
  hush.log("reached the wall at x=" .. xw .. ", wall tile at " .. wall .. " (vanilla soldier tile box: stops " .. (wall - xw) .. " px before it)")
  hush.assert(wall - xw >= 10 and wall - xw <= 18, "stops at the wall (x " .. xw .. ", wall " .. wall .. ")")
  hush.assert_eq(ai.dir(0), 0, "still facing east during the pause")
  local paused = 0
  while paused < 120 do
    hush.wait(1)
    if ai.dir(0) ~= 0 then break end             -- the frame it turns, it also takes its first step west
    paused = paused + 1
    hush.assert_eq((ai.pos(0)), xw, "stands still while paused")
  end
  hush.log("pause " .. paused .. " frames")
  hush.assert(paused >= 55 and paused <= 66, "pauses about 60 frames, got " .. paused)
  hush.assert_eq(ai.dir(0), 1, "then faces west")
  hush.wait(40)
  hush.assert(ai.pos(0) < xw - 20, "and walks back west")

  -- the still guard never moved, never turned, never noticed Link
  local bx, by = ai.pos(1)
  hush.assert(bx == bx0 and by == by0, "the still guard did not move")
  hush.assert_eq(ai.dir(1), 3, "and keeps facing north")
  hush.assert_eq(ai.state(1), 0, "unaware")
  hush.assert_eq(ai.state(0), 0, "patrol guard never noticed Link")
  -- a guard that calms down resumes its patrol: suspicious guard that never sees Link goes unaware and walks again
  bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 5); bot.poke(0x7E0E10, 5)
  hush.wait(2)
  local xs = ai.pos(0)
  hush.wait(4)
  hush.assert_eq((ai.pos(0)), xs, "a suspicious guard stands still")
  hush.assert(ai.wait_state(0, ai.S.UNAWARE, 20), "and calms down")
  local xc = ai.pos(0)
  hush.wait(30)
  hush.assert(ai.pos(0) ~= xc, "the calmed guard patrols again")
  hush.pass("patrol and still")
end)
