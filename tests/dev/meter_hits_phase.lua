-- Dev (not a test suite member): is smoke/meter_hits.lua sensitive to the frame phase ($1A) at which the pokes land?
-- Runs the criterion 2 / 3 sequence of meter_hits once per start delay 4..11 (8 phases, covers any 2/4/8-frame AI cadence)
-- and prints one line per phase. Fails if any phase differs from 32 -> 28 -> 12.
--   .venv/bin/python tools/run_test.py tests/dev/meter_hits_phase.lua
-- @rom dev
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

hush.test("meter_hits_phase: criteria 2 and 3 at every frame phase", function()
  local bad = {}
  for d = 4, 11 do
    ai.enter("ai4_dark")
    ai.link_to(0, 140, 0)
    hush.wait(d)
    local phase = hush.read("frame_counter") & 7
    local m0, s0 = meter.get(), ai.state(0)
    meter.notice(0)
    hush.wait(4)
    local m1, s1 = meter.get(), ai.state(0)
    local drift
    for i = 1, 60 do
      hush.wait(1)
      if not drift and (meter.get() ~= m1 or ai.state(0) ~= ai.S.SUSPICIOUS) then
        drift = string.format("hold %d: meter %d state %d", i, meter.get(), ai.state(0))
      end
    end
    meter.alert(0)
    hush.wait(4)
    local m2, s2 = meter.get(), ai.state(0)
    local line = string.format("delay %2d phase %d: state %d/%d/%d meter %d -> %d -> %d%s caught=%s",
      d, phase, s0, s1, s2, m0, m1, m2, drift and (" DRIFT " .. drift) or "", tostring(ai.caught()))
    hush.log(line)
    if m0 ~= 32 or m1 ~= 28 or m2 ~= 12 or drift or s1 ~= ai.S.SUSPICIOUS or s2 ~= ai.S.ALERT then bad[#bad + 1] = line end
  end
  hush.assert(#bad == 0, "phase-dependent result: " .. table.concat(bad, " | "))
  hush.pass("32 -> 28 -> 12 at all 8 start phases")
end)
