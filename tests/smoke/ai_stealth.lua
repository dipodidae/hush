-- Smoke (E2): the game as a player meets it, with real button presses (no teleport after the first positioning):
--   * sneak up on an unaware guard from behind, stab him with the Shade Knife (B): he dies, never noticed Link;
--   * walk into the guard's view: '?' then '!' then he runs Link down: the room restarts and Link stands at the start again.
-- Room ai4_dark: a still guard faces east at cell (5, 6); Link starts at cell (1, 2).
-- @rom dev
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

hush.test("ai_stealth: stab from behind, walk into view and get caught", function()
  local r = ai.enter("ai4_dark")
  local g = r.guards[1]
  local sx, sy = r.start_x, r.start_y

  -- 1. approach from the west along the guard's row, in its blind side, and stab
  hush.assert(bot.walk_to(sx, g.y - 8, 300), "walk down to the guard's row")
  bot.walk_to(g.x - 44, g.y - 8, 300)      -- 44 px west of the guard (outside the sword's reach, 16 px from his back)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "not noticed while walking up behind him")
  hush.hold({ "right" }, 14)               -- a few steps east: faces east, closes in to ~30 px
  local lx = hush.read("link_x")
  hush.log("Link x = " .. lx .. ", guard x = " .. g.x .. " (dx " .. (lx - g.x) .. ")")
  hush.assert(g.x - lx >= 17, "still outside contact range (" .. (g.x - lx) .. " px)")
  hush.press({ "b" }, 2, 1)
  local died = ai.watch(20, function() return not ai.alive(0) end)
  hush.assert(died ~= nil, "the knife kills the unaware guard from behind")
  hush.screenshot("stabbed")
  hush.assert(not ai.caught(), "nobody caught Link")

  -- 2. restart (guard back), now walk into his view from the north side and wait for the chase
  ai.restart(); hush.wait(10); bot.wait_control()
  hush.assert(ai.alive(0), "the guard is back")
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "unaware again")
  bot.walk_to(g.x + 48, g.y - 8 - 48, 300)   -- far enough from the cone: (dx 48, dy -48) is exactly on its edge, walk on:
  bot.walk_to(g.x + 48, g.y - 8, 300)         -- into the cone, in front of him
  hush.assert(ai.state(0) >= 1, "he noticed Link in his cone")
  local caught_at
  for f = 1, 240 do
    hush.wait(1)
    if hush.read("link_x") == sx and hush.read("link_y") == sy and ai.state(0) == ai.S.UNAWARE then caught_at = f; break end
  end
  hush.assert(caught_at ~= nil, "the guard caught Link and the room restarted (Link at the start, guard unaware)")
  hush.log("restart seen " .. caught_at .. " frames after Link was noticed")
  hush.assert_eq(hush.read("health"), 0x18, "full health")
  hush.assert_eq(hush.read("game_mode"), 0x07, "no game over, no room reload screen")
  hush.pass("stab from behind; noticed -> chased -> caught -> restart")
end)
