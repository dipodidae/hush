-- Smoke (E2): conditional sword damage. Link's Shade Knife (the fighter sword slot) kills an UNAWARE or ASLEEP guard and does
-- nothing to a SUSPICIOUS or ALERT one (no damage, the guard stays alive). Link stands left of a guard that faces east
-- (behind it, so it does not see him) at 26 px, inside the sword's reach (the reach sweep tests/dev/ai_probe2.lua: dx -32..-16 hits).
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

-- Swing the knife at the guard from `dx` (east-facing Link), return the frame the guard died (nil = alive after 14 frames).
local function swing(dx, pre)
  ai.restart(); hush.wait(8); bot.wait_control()
  if pre then pre() end
  ai.link_to(0, dx, 0)
  bot.poke(0x7E002F, 6)                -- Link faces east
  hush.wait(1)
  hush.hold({ "b" }, 2)
  return ai.watch(14, function() return not ai.alive(0) end)
end

hush.test("ai_sword: knife kills unaware / asleep, ignores suspicious / alert", function()
  ai.enter("ai4_dark")
  hush.assert_eq(bot.peek(0x7EF359), 1, "Link has the fighter sword (Shade Knife)")

  local f = swing(-26)
  hush.assert(f ~= nil, "unaware guard hit from behind must die")
  hush.assert_eq(ai.state(0), 0, "it was unaware")
  hush.wait(30)
  hush.assert(not ai.alive(0), "a dead guard stays dead")
  hush.screenshot("dead")

  hush.assert(swing(-60) == nil, "out of reach: the guard survives")

  -- suspicious (frozen there: both timers 255, Link at 26 px behind him senses him but cannot be caught: contact is < 16 px)
  local function suspicious()
    bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0E10, 255)
  end
  hush.assert(swing(-26, suspicious) == nil, "suspicious guard ignores the sword")
  hush.assert_eq(ai.state(0), 1, "still suspicious")
  hush.assert_eq(bot.peek(0x7E0EF0), 0, "no hit flash / damage timer on the guard")

  -- alert: he walks towards Link (1.1 px/frame, 26 -> 16 px takes ~9 frames, the swing's hit frames are 2-3): still alive then
  local function alert()
    bot.poke(0x7E0D80, 2); bot.poke(0x7E0E10, 180)
  end
  ai.restart(); hush.wait(8); bot.wait_control(); alert()
  ai.link_to(0, -26, 0); bot.poke(0x7E002F, 6); hush.wait(1); hush.hold({ "b" }, 2)
  local died = ai.watch(6, function() return not ai.alive(0) end)
  hush.assert(died == nil, "alert guard ignores the sword")
  hush.assert_eq(ai.state(0), 2, "still alert")
  hush.assert_eq(hush.read("health"), 0x18, "Link is never hurt")

  -- asleep: dies
  hush.assert(swing(-26, function() bot.poke(0x7E0D80, 3); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0D90, 1) end) ~= nil, "asleep guard dies")

  -- a guard that SEES Link (Link in front) is already suspicious when the knife arrives: safe
  ai.restart(); hush.wait(8); bot.wait_control()
  ai.link_to(0, 26, 0); bot.poke(0x7E002F, 4)       -- in front of the guard, facing west
  hush.wait(1); hush.hold({ "b" }, 2)
  hush.assert(ai.watch(10, function() return not ai.alive(0) end) == nil, "a guard that has noticed Link cannot be stabbed")
  hush.pass("unaware/asleep die, suspicious/alert/noticed survive")
end)
