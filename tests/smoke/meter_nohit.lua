-- Smoke (stealth meter, criterion 11): pillars.md:121-122 "Asleep / killed / ink-calmed transitions and dart hits on aware guards
-- leave hush_meter unchanged." (hit table pillars.md:59: -> Unaware, -> Asleep, Asleep -> Unaware, kill = 0; pillars.md:76-78: ink
-- makes guards Unaware with no hit and no refund; a dart on a Suspicious / Alert guard does nothing to guard or meter.)
-- Real tools where the E2 tests use them: dart (tests/smoke/ai_darts.lua set-up), knife (tests/smoke/ai_caught.lua case 3), ink cloud
-- (hush_ink_* pokes, tests/smoke/ai_ink.lua). Each case starts from a restart (meter 32) and compares the meter before / after.
-- @rom dev
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local meter = require("meter")

local function fresh(dx)
  ai.restart(); hush.wait(8); bot.wait_control()
  hush.assert_eq(meter.get(), 32, "meter 32 after the restart (criterion 1)")
  ai.link_to(0, dx, 0)
  bot.poke(0x7E002F, 6)                       -- facing east (link_dir, docs/ram_map.md)
  hush.wait(2)
end

local function bow()
  bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3)   -- bow selected (docs/engine_notes.md 11.5 item-selection pitfall)
end

local function hold_meter(n, v, what)
  for f = 1, n do
    hush.wait(1)
    hush.assert_eq(meter.get(), v, what .. " leaves hush_meter unchanged (criterion 11, pillars.md:121), frame " .. f)
  end
end

local function cloud(cx, cy, t)
  hush.write("hush_ink_x", cx); hush.write("hush_ink_y", cy); hush.write("hush_ink_t", t)
end

hush.test("meter_nohit: sleep, wake, kill, ink, darts on aware guards cost nothing (criterion 11)", function()
  ai.enter("ai4_dark")
  hush.assert_eq(meter.get(), 32, "full meter on entry (criterion 1)")

  -- a. dart on an unaware guard: Unaware -> Asleep; then Asleep -> Unaware
  fresh(-60); bow()
  hush.press({ "y" }, 3, 1)
  local f = ai.watch(40, function() return ai.state(0) == ai.S.ASLEEP or meter.get() ~= 32 end)
  hush.assert(f ~= nil and ai.state(0) == ai.S.ASLEEP, "precondition: the dart put him to sleep")
  hold_meter(30, 32, "Unaware -> Asleep (dart)")
  hush.write("spr_aware", 0, 0)               -- wake him (Asleep -> Unaware) without waiting 480 frames
  hold_meter(10, 32, "Asleep -> Unaware")

  -- b. knife kill of an unaware guard
  fresh(-26)
  hush.hold({ "b" }, 2); hush.wait(8)
  hush.assert(not ai.alive(0), "precondition: the guard was stabbed")
  hold_meter(20, 32, "a knife kill")

  -- c. ink-calmed: an Alert guard (-16) made Unaware by the cloud: no refund, no hit
  fresh(140)
  meter.alert(0); hush.wait(4)
  local v = meter.get()
  hush.assert(v < 32, "precondition: the alert was a hit (the meter is live, criterion 3); meter " .. v)
  local gx, gy = ai.pos(0)
  cloud(gx + 8, gy + 8, 300)
  f = ai.watch(8, function() return ai.state(0) == ai.S.UNAWARE end)
  hush.assert(f ~= nil, "precondition: the cloud calmed him")
  hold_meter(20, v, "Alert -> Unaware by ink (no refund, pillars.md:77)")
  cloud(0, 0, 0)

  -- d. dart on a Suspicious guard
  fresh(-60); bow()
  meter.notice(0); hush.wait(4)
  v = meter.get()
  hush.assert(v < 32, "precondition: the notice was a hit (criterion 2); meter " .. v)
  hush.press({ "y" }, 3, 1)
  hold_meter(30, v, "a dart on a Suspicious guard")
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "precondition: the dart did nothing to him (pillars.md:78)")

  -- e. dart on an Alert guard (he charges: only 15 frames, then restart)
  fresh(-60); bow()
  meter.alert(0); hush.wait(4)
  v = meter.get()
  hush.assert(v < 32, "precondition: the alert was a hit (criterion 3); meter " .. v)
  hush.press({ "y" }, 3, 1)
  hold_meter(12, v, "a dart on an Alert guard")
  hush.assert_eq(ai.state(0), ai.S.ALERT, "precondition: the dart did nothing to him (pillars.md:78)")
  hush.assert(not ai.caught(), "precondition: not caught during the dart cases")
  hush.pass("sleep, wake, kill, ink-calm, darts on aware guards: meter unchanged")
end)
