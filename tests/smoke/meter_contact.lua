-- Smoke (stealth meter, criterion 4): pillars.md:105-106 "Contact with an Unaware guard lowers it by exactly 16 (not 20) before the
-- catch restart."  (hit table pillars.md:58: Unaware -> Alert directly = big only). Contact makes an unaware guard Alert at once and
-- the next frame is a catch (docs/engine_notes.md 11.2, tests/smoke/ai_caught.lua), so the meter is sampled every frame from the
-- touch to the restart (hush_retries +1).
-- @rom dev
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

hush.test("meter_contact: touching an unaware guard costs 16, not 20, before the restart (criterion 4)", function()
  ai.enter("ai4_dark")
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "precondition: guard unaware")
  hush.assert_eq(meter.get(), 32, "full meter before the touch (pillars.md:100)")
  local r0 = hush.read("hush_retries")
  ai.link_to(0, -10, 0)                    -- from behind: he never saw Link, so the only transition is the contact 0 -> 2
  local seen, path = {}, {}
  local restart_f
  for f = 1, 12 do
    hush.wait(1)
    local m, a, r = meter.get(), ai.state(0), hush.read("hush_retries")
    path[#path + 1] = string.format("f%d m=%d a=%d c=%d r=%d", f, m, a, hush.read("hush_caught"), r)
    if r ~= r0 then restart_f = f; break end
    seen[m] = true
    hush.assert(a ~= ai.S.SUSPICIOUS, "precondition: no '?' step in between (it would be a legal 4 + 16), frame " .. f)
  end
  hush.log("contact trace: " .. table.concat(path, " | "))
  hush.assert(restart_f ~= nil, "precondition: the contact ended in the catch restart (docs/engine_notes.md 11.2)")
  hush.assert(seen[16], "hush_meter showed 16 (32 - 16) before the catch restart (criterion 4, pillars.md:105); trace " .. table.concat(path, " | "))
  hush.assert(not seen[12], "it never showed 12: contact is big only, not 4 + 16 (criterion 4 'not 20', pillars.md:58)")
  hush.assert_eq(meter.get(), 32, "refilled by the restart (pillars.md:49)")
  hush.pass("contact with an unaware guard: 32 -> 16, then the restart")
end)
