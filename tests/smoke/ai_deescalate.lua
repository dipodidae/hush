-- Smoke (E2): awareness timers. Suspicious guard that loses Link: unaware after 120 frames. Alert guard that loses Link: unaware
-- after 180 frames (he stays where he is). Link is made "lost" by distance (out of the 80 px dark range) or by a pillar.
-- @rom dev
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

hush.test("ai_deescalate: suspicious 120 frames, alert 180 frames", function()
  ai.enter("ai4_dark")
  -- suspicious: see Link for 10 frames, then Link jumps out of range
  ai.link_to(0, 48, 0)
  hush.wait(10)
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "noticed")
  ai.link_to(0, 140, 0)                  -- out of range (dark: 80 px)
  hush.wait(100)
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "still suspicious 100 frames after losing Link")
  local f = ai.watch(40, function() return ai.state(0) == ai.S.UNAWARE end)
  hush.assert(f ~= nil, "back to unaware")
  hush.log("suspicious -> unaware " .. (100 + f) .. " frames after Link was lost")
  hush.assert(100 + f >= 115 and 100 + f <= 128, "120 frames to unaware, got " .. (100 + f))

  -- alert guard stuck behind the pillar (ai6_cover): Link directly behind it, not visible, unreachable by the straight chase
  ai.enter("ai6_cover")
  local gx0 = ai.pos(0)
  bot.poke(0x7E0D80, 2); bot.poke(0x7E0E10, 180)
  ai.link_to(0, 64, 0)                   -- behind the pillar
  hush.wait(150)
  hush.assert_eq(ai.state(0), ai.S.ALERT, "alert guard, Link hidden: still alert after 150 frames")
  local gx1 = ai.pos(0)
  hush.assert(gx1 > gx0, "he chased towards Link until the pillar stopped him")
  hush.assert(gx1 - gx0 <= 40, "the pillar stops him (at most 40 px)")
  local f2 = ai.watch(60, function() return ai.state(0) == ai.S.UNAWARE end)
  hush.assert(f2 ~= nil, "alert -> unaware")
  hush.log("alert -> unaware " .. (150 + f2) .. " frames after Link was hidden")
  hush.assert(150 + f2 >= 175 and 150 + f2 <= 190, "180 frames to unaware, got " .. (150 + f2))
  local gx2 = ai.pos(0)
  hush.wait(30)
  hush.assert_eq(ai.pos(0), gx2, "a still guard stays where he is after calming down")
  hush.assert(not ai.caught(), "never caught")
  hush.pass("suspicious 120, alert 180")
end)
