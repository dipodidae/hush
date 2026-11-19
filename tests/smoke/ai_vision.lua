-- Smoke (E2): guard vision. A still guard faces east (dev room ai4_dark, dark; ai5_lit, lit).
--   * 90-degree cone in FRONT of the guard, range 5 cells = 80 px dark / 8 cells = 128 px lit (max(|dx|,|dy|), centre to centre)
--   * behind the guard is blind
--   * unaware -> suspicious ('?', stops, 60 frames) -> alert
-- Sub-tests re-use the room through the fast restart (hush_caught), which also resets the guard.
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

-- Is Link at (dx, dy) from the guard centre noticed within 12 frames (state leaves 0)?
local function seen_at(dx, dy)
  ai.link_to(0, dx, dy)
  local f = ai.watch(12, function() return ai.state(0) ~= ai.S.UNAWARE end)
  local seen = f ~= nil
  ai.restart()                         -- next sub-test starts from a fresh room (guard unaware, Link at the start)
  hush.wait(8)
  return seen
end

hush.test("ai_vision: cone, range, blind behind, lit range", function()
  ai.enter("ai4_dark")
  hush.assert_eq(ai.state(0), 0, "guard starts unaware")
  hush.assert_eq(ai.dir(0), 0, "guard faces east (0)")

  -- cone and blind side (dark room, range 80)
  hush.assert(seen_at(48, 0), "straight in front at 48 px must be seen")
  hush.assert(seen_at(80, 0), "front, exactly at the range (80)")
  hush.assert(not seen_at(88, 0), "front, beyond the dark range (88 > 80) must NOT be seen")
  hush.assert(seen_at(48, 40), "inside the 45-degree edge (dx 48, dy 40)")
  hush.assert(seen_at(48, -40), "inside the 45-degree edge, other side (dx 48, dy -40)")
  hush.assert(not seen_at(40, 60), "outside the cone (dx 40, dy 60) must NOT be seen")
  hush.assert(not seen_at(40, -60), "outside the cone, other side (dx 40, dy -60)")
  hush.assert(not seen_at(-48, 0), "directly behind the guard is blind")
  hush.assert(not seen_at(-16, 8), "right behind the guard (dx -16, dy 8) is blind")
  hush.assert(not seen_at(0, 48), "to the side (south, 90 degrees off) must NOT be seen")

  -- lit room: range 128
  ai.enter("ai5_lit")
  hush.assert(seen_at(120, 0), "lit room: 120 px in front is seen")
  hush.assert(seen_at(128, 0), "lit room: exactly 128")
  hush.assert(not seen_at(136, 0), "lit room: beyond 128 is not seen")
  hush.assert(not seen_at(-48, 0), "lit room: behind is still blind")
  ai.enter("ai4_dark")
  hush.assert(not seen_at(120, 0), "dark room: 120 px is out of range")

  -- unaware -> suspicious -> alert timing
  ai.link_to(0, 40, 0)
  hush.wait(2)
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "noticed: suspicious")
  local gx, gy = ai.pos(0)
  hush.wait(30)
  local x2, y2 = ai.pos(0)
  hush.assert(gx == x2 and gy == y2, "a suspicious guard stands still")
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "still suspicious after 30 frames")
  hush.screenshot("suspicious")
  hush.assert(ai.wait_state(0, ai.S.ALERT, 50), "Link still in view after the 60 frames: alert")
  hush.wait(2)
  hush.screenshot("alert")
  hush.assert_eq(bot.peek(0x7E0F50), 0x0D, "an alert guard is drawn with palette row 6 (amber)")
  hush.pass("cone, range, blind side, lit range, suspicious -> alert")
end)
