-- Smoke (stealth meter, criterion 6): pillars.md:110 "Two guards turning Suspicious in the same frame lower it by 8."
-- (pillars.md:68-70: the cooldown is per guard slot; different guards always hit independently.) Room ai8_crowd (8 still guards in
-- column 4, rows 3-10, facing east, lit: range 128 px, docs/engine_notes.md 11.3); Link parked 160 px east of them = out of range.
-- @rom dev
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

hush.test("meter_two_guards: two ? in one frame = -8 (criterion 6)", function()
  ai.enter("ai8_crowd")
  ai.link_to(0, 160, 0)
  hush.wait(4)
  hush.assert_eq(hush.read("spr_type", 0), 0x41, "precondition: slot 0 is a guard")
  hush.assert_eq(hush.read("spr_type", 1), 0x41, "precondition: slot 1 is a guard")
  hush.assert(ai.state(0) == 0 and ai.state(1) == 0, "precondition: both unaware")
  hush.assert_eq(meter.get(), 32, "full meter (pillars.md:100)")
  meter.notice(0); meter.notice(1)         -- the same frame boundary
  local trace = {}
  for f = 1, 6 do hush.wait(1); trace[#trace + 1] = tostring(meter.get()) end
  hush.log("meter after the double notice: " .. table.concat(trace, " "))
  hush.assert(ai.state(0) == 1 and ai.state(1) == 1, "precondition: both Suspicious")
  hush.assert_eq(meter.get(), 24, "two guards turning Suspicious in the same frame lower it by 8 (criterion 6, pillars.md:110)")
  hush.pass("two notices in one frame: -8")
end)
