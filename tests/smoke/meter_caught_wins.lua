-- Smoke (stealth meter, criterion 8): pillars.md:113-114 "With hush_meter = 32, an Alert guard touching Link restarts the room (meter
-- value irrelevant)." pillars.md:74-75 "Caught still wins: an Alert guard touching Link restarts the room at once, whatever the meter
-- shows." Two cases: meter 32 and meter 4 (an already-Alert guard touching is not a new transition, so no hit; one restart only,
-- and the restart refills: pillars.md:49).
-- The guard is made Alert while Link is far away (that costs 16, criterion 3), then the meter is set to the case value and Link is put
-- against the guard.
-- @rom dev
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local meter = require("meter")

local function case(r, value)
  ai.link_to(0, 140, 0); hush.wait(4)
  meter.alert(0)
  hush.wait(4)
  hush.assert_eq(ai.state(0), ai.S.ALERT, "precondition: guard Alert")
  meter.set(value)
  hush.wait(1)
  hush.assert_eq(meter.get(), value, "precondition: an Alert guard that stays Alert causes no further hit (pillars.md:52)")
  local r0 = hush.read("hush_retries")
  ai.link_to(0, -10, 0)
  local caught_seen = false
  local f = meter.watch(6, function()
    if hush.read("hush_caught") ~= 0 then caught_seen = true end
    return hush.read("hush_retries") ~= r0
  end)
  hush.assert(f ~= nil, string.format("meter %d: an Alert guard touching Link restarts the room (criterion 8, pillars.md:74-75, :113)", value))
  hush.log(string.format("meter %d: restart %d frame(s) after the touch, hush_caught seen %s", value, f, tostring(caught_seen)))
  hush.assert(f <= 2, "at once: within 2 frames of the touch (docs/engine_notes.md 11.6), took " .. f)
  hush.assert_eq(meter.get(), 32, string.format("meter %d: refilled to 32 by the restart (pillars.md:49)", value))
  hush.assert_eq(hush.read("link_x"), r.start_x, "Link back at the start")
  hush.wait(3)
  hush.assert_eq(hush.read("hush_retries"), r0 + 1, "exactly one restart")
  bot.wait_control(); hush.wait(5)
end

hush.test("meter_caught_wins: an Alert guard's touch restarts whatever the meter shows (criterion 8)", function()
  local r = ai.enter("ai4_dark")
  case(r, 32)
  case(r, 4)
  hush.pass("touch by an Alert guard restarts at meter 32 and at meter 4; refilled; one restart")
end)
