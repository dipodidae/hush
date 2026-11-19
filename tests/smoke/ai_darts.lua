-- Smoke (E2): conditional arrow damage (Hush Darts = the bow slot). An arrow on an UNAWARE guard puts it to sleep for
-- 480 frames (state 3, 240 + 240) and is consumed; on a suspicious / alert / asleep guard it does nothing to the guard
-- (the arrow still stops). Link stands behind the east-facing guard (unseen) and shoots east.
-- @rom dev
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

local function arrows() return bot.peek(0x7EF377) end
local function ancillae()      -- flying arrows: ancilla type $09 in the 10 ancilla slots ($0C4A); the stuck arrow is type $0A
  local n = 0
  for i = 0, 9 do if bot.peek(0x7E0C4A + i) == 0x09 then n = n + 1 end end
  return n
end

local function fresh()
  ai.restart(); hush.wait(8); bot.wait_control()
  bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3)   -- selected item: bow (HUD index 1; equipped id 3, MenuToEquipID bank_0D.asm:17015)
  ai.link_to(0, -60, 0)                 -- behind the guard, 60 px away
  bot.poke(0x7E002F, 6)                 -- facing east
  hush.wait(2)
end

local function shoot()
  hush.press({ "y" }, 3, 1)
end

hush.test("ai_darts: arrow = 8 s sleep on an unaware guard only", function()
  ai.enter("ai4_dark")
  hush.assert_eq(bot.peek(0x7EF340), 2, "Link has the bow")
  local n0 = arrows()
  hush.assert(n0 >= 1, "arrows in the quiver")

  -- unaware guard, shot in the back
  fresh()
  shoot()
  local f = ai.watch(40, function() return ai.state(0) == ai.S.ASLEEP end)
  hush.assert(f ~= nil, "the arrow puts the unaware guard to sleep")
  hush.assert_eq(arrows(), n0 - 1, "one arrow used")
  hush.assert(ancillae() == 0 or ai.watch(20, function() return ancillae() == 0 end) ~= nil, "the arrow is consumed (no flying arrow left)")
  hush.screenshot("asleep")
  hush.assert(ai.alive(0), "an arrow does not kill")

  -- how long: from the hit to waking up
  local t = 0
  while ai.state(0) == ai.S.ASLEEP and t < 600 do hush.wait(1); t = t + 1 end
  hush.log("slept " .. t .. " frames after the hit was seen")
  hush.assert(t >= 470 and t <= 490, "sleep lasts about 480 frames (8 s), got " .. t)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "wakes up unaware")

  -- a sleeping guard is a solid obstacle: Link cannot walk through him
  fresh()
  bot.poke(0x7E0D80, 3); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0D90, 1)
  ai.link_to(0, -40, 0)
  hush.hold({ "right" }, 60)
  do
    local gx, gy = ai.pos(0)
    local lx = hush.read("link_x")
    hush.log("walked east into the sleeper: Link x " .. lx .. ", guard x " .. gx)
    hush.assert(lx <= gx - 14, "Link stops at the sleeping guard (x " .. lx .. " vs " .. gx .. ")")
    hush.assert_eq(ai.state(0), ai.S.ASLEEP, "and does not wake him")
    hush.assert(not ai.caught(), "touching a sleeper is no catch")
  end

  -- an asleep guard ignores Link, even standing right in front of him; a second arrow changes nothing
  fresh()
  shoot()
  ai.wait_state(0, ai.S.ASLEEP, 40)
  ai.link_to(0, 40, 0)
  hush.wait(60)
  hush.assert_eq(ai.state(0), ai.S.ASLEEP, "asleep: Link in front at 40 px is ignored")
  fresh(); ai.link_to(0, -60, 0)       -- (fresh restarts the room: back to unaware, so shoot a sleeper explicitly)
  bot.poke(0x7E0D80, 3); bot.poke(0x7E0DF0, 200); bot.poke(0x7E0D90, 0)
  local before = bot.peek(0x7E0DF0)
  shoot(); hush.wait(30)
  hush.assert_eq(ai.state(0), ai.S.ASLEEP, "asleep guard hit by an arrow: still asleep")
  hush.assert(ai.alive(0), "and alive")

  -- suspicious and alert guards: no effect (they cannot be put to sleep)
  fresh()
  bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0E10, 255)
  shoot(); hush.wait(40)
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "suspicious guard: the arrow does nothing")
  hush.assert(ai.alive(0), "and does not kill him")
  hush.assert(ancillae() == 0, "the arrow stopped at the guard")
  fresh()
  bot.poke(0x7E0D80, 2); bot.poke(0x7E0E10, 180)
  shoot()
  local asleep = ai.watch(25, function() return ai.state(0) == ai.S.ASLEEP end)
  hush.assert(asleep == nil, "alert guard: the arrow does not put him to sleep")
  hush.assert(ai.alive(0), "alert guard unhurt")
  hush.pass("arrow: unaware -> asleep 480 frames; others unaffected; arrow consumed")
end)
