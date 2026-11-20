-- Smoke (stealth meter, criteria 2 and 3): pillars.md:102-104.
--   2. "Forcing one guard Unaware -> Suspicious lowers hush_meter by exactly 4; holding him Suspicious for 60 more frames (no Alert
--      yet) lowers it by 0 more."  (hit table pillars.md:54-56; "once per state transition, never per frame" pillars.md:52)
--   3. "Suspicious -> Alert lowers it by exactly 16 (total 20 from full)."  (pillars.md:57; a big hit is never blocked by a recent
--      small hit, pillars.md:66-68: here the ! comes ~65 frames after the ?)
-- Also pillars.md:47-48: the value is always 0..32 and a multiple of 4 (checked every frame).
-- Link is parked 140 px east of the guard (outside the 80 px dark range, docs/engine_notes.md 11.3), so the forced states are not
-- changed by the AI itself; that is asserted as a precondition.
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

local function sane(where)
  local m = meter.get()
  hush.assert(m <= 32 and m % 4 == 0, where .. ": hush_meter = " .. m .. " (must be 0..32, multiple of 4; pillars.md:47-48)")
end

hush.test("meter_hits: ? costs 4 once, ! costs 16 (criteria 2, 3)", function()
  ai.enter("ai4_dark")
  ai.link_to(0, 140, 0)
  hush.wait(4)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "precondition: guard unaware with Link out of range")
  hush.assert_eq(meter.get(), 32, "full meter in the room before any notice (pillars.md:49, :100)")

  -- criterion 2: Unaware -> Suspicious
  meter.notice(0)
  hush.wait(4)
  hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "precondition: guard held Suspicious")
  hush.assert_eq(meter.get(), 28, "Unaware -> Suspicious lowers hush_meter by exactly 4 (criterion 2, pillars.md:102)")
  for i = 1, 60 do
    hush.wait(1)
    sane("criterion 2 hold frame " .. i)
    hush.assert_eq(ai.state(0), ai.S.SUSPICIOUS, "precondition: still Suspicious at hold frame " .. i)
    hush.assert_eq(meter.get(), 28, "holding Suspicious lowers it by 0 more (criterion 2, pillars.md:103), hold frame " .. i)
  end

  -- criterion 3: Suspicious -> Alert
  meter.alert(0)
  hush.wait(4)
  hush.assert_eq(ai.state(0), ai.S.ALERT, "precondition: guard Alert")
  hush.assert_eq(meter.get(), 12, "Suspicious -> Alert lowers it by exactly 16, total 20 from full (criterion 3, pillars.md:104)")
  for i = 1, 20 do
    hush.wait(1)
    sane("criterion 3 hold frame " .. i)
    hush.assert_eq(meter.get(), 12, "holding Alert costs nothing more (pillars.md:52), frame " .. i)
  end
  hush.assert(not ai.caught(), "precondition: Link was never caught")
  hush.pass("? = -4 once, ! = -16 once (32 -> 28 -> 12)")
end)
