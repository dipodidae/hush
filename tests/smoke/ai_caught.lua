-- Smoke (E2): caught -> instant restart. An ALERT guard that touches Link restarts the room: Link back at the start, the
-- guard back to its spawn and unaware, tools refilled, screen back within 20 frames. Touching an UNAWARE guard only alerts him.
-- Also measures the restart (docs/engine_notes.md): frames from the contact frame to the first frame at full brightness.
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

hush.test("ai_caught: contact with an alert guard restarts the room fast", function()
  local r = ai.enter("ai4_dark")
  local g = r.guards[1]
  local gx0, gy0 = ai.pos(0)

  -- 1. touching an unaware guard (from behind, so he never saw Link) alerts him; it is not a catch
  ai.link_to(0, -10, 0)
  hush.wait(1)
  hush.assert_eq(ai.state(0), ai.S.ALERT, "touching an unaware guard makes him alert at once")
  hush.assert(not ai.caught(), "not caught yet (he was unaware); the next frame he is alert AND touching: caught")
  hush.assert_eq(hush.read("health"), 0x18, "no damage")

  -- 1b. touching a SUSPICIOUS guard alerts him as well
  ai.restart(); hush.wait(8)
  bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0E10, 255)
  ai.link_to(0, -10, 0)
  hush.wait(1)
  hush.assert_eq(ai.state(0), ai.S.ALERT, "touching a suspicious guard makes him alert at once")
  ai.restart(); hush.wait(8)
  ai.link_to(0, -10, 0)
  hush.wait(1)

  -- 2. the alert guard touches Link on the next frames: caught -> restart
  local frame_caught, frame_full
  for f = 1, 60 do
    hush.wait(1)
    if not frame_caught and (ai.caught() or hush.read("hush_flash") ~= 0) then frame_caught = f end
    if frame_caught and hush.read("hush_flash") == 0 and bot.peek(0x7E0013) == 0x0F and not ai.caught() then frame_full = f; break end
  end
  hush.assert(frame_caught ~= nil, "contact with the alert guard = caught")
  hush.assert(frame_full ~= nil, "the screen came back")
  local n = frame_full - frame_caught
  hush.log(string.format("RESTART: caught flag seen at frame +%d, full brightness at +%d: %d frames", frame_caught, frame_full, n))
  hush.assert(n <= 20, "restart takes at most 20 frames, took " .. n)

  hush.assert_eq(hush.read("game_mode"), 0x07, "still in the room module (no room reload)")
  hush.assert_eq(hush.read("link_x"), r.start_x, "Link back at the start (x)")
  hush.assert_eq(hush.read("link_y"), r.start_y, "Link back at the start (y)")
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "the guard is unaware again")
  hush.assert(ai.alive(0), "and present")
  local gx, gy = ai.pos(0)
  hush.assert(gx == gx0 and gy == gy0, "at its spawn position")
  hush.assert_eq(ai.dir(0), 0, "facing east again")
  hush.assert_eq(hush.read("health"), 0x18, "full health")
  hush.screenshot("after_restart")

  -- Link is controllable immediately
  local x0 = hush.read("link_x")
  hush.hold({ "down" }, 10)
  hush.assert(hush.read("link_y") > r.start_y, "Link walks after the restart")

  -- 3. a killed guard comes back with the restart
  ai.restart(); hush.wait(8)
  ai.link_to(0, -26, 0); bot.poke(0x7E002F, 6); hush.wait(1); hush.hold({ "b" }, 2); hush.wait(8)
  hush.assert(not ai.alive(0), "the guard was stabbed")
  ai.restart(); hush.wait(8)
  hush.assert(ai.alive(0), "a restart brings a killed guard back")
  hush.pass(string.format("caught -> restart in %d frames", n))
end)
