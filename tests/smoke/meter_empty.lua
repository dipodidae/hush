-- Smoke (stealth meter, criterion 7): pillars.md:111-112 "With hush_meter = 4, one small hit sets it to 0, hush_caught is set that
-- frame, the room restarts next frame, hush_retries +1, hush_meter = 32." pillars.md:71-73: "the room restarts exactly as if caught:
-- same path (hush_caught), same flash and sound, same timing". The caught path is measured first in the same room (poke hush_caught,
-- what a guard does, docs/ram_map.md) and the meter-empty path must match it (frames to the restart, hush_flash on that frame).
-- The SFX is not compared here (tests/smoke/feedback.lua owns the APU port checks).
-- @rom dev
-- @timeout 90
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local meter = require("meter")

hush.test("meter_empty: 4 -> 0 restarts the room like a catch (criterion 7)", function()
  local r = ai.enter("ai4_dark")

  -- baseline: the caught path
  ai.link_to(0, 140, 0); hush.wait(4)
  local r0 = hush.read("hush_retries")
  hush.write("hush_caught", 1)
  local base_f = meter.watch(10, function() return hush.read("hush_retries") ~= r0 end)
  hush.assert(base_f ~= nil, "precondition: the caught restart runs")
  local base_flash = hush.read("hush_flash")
  hush.log(string.format("baseline caught: restart %d frame(s) after the flag, hush_flash %d on that frame", base_f, base_flash))
  bot.wait_control(); hush.wait(10)

  -- the meter-empty path
  ai.link_to(0, 140, 0); hush.wait(4)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "precondition: guard unaware")
  meter.set(4)
  r0 = hush.read("hush_retries")
  meter.notice(0)
  local zero_f = meter.watch(6, function() return meter.get() == 0 or hush.read("hush_retries") ~= r0 end)
  hush.assert(zero_f ~= nil and hush.read("hush_retries") == r0,
    "one small hit at 4 sets hush_meter to 0, seen on a frame before the restart (criterion 7, pillars.md:111); meter " .. meter.get())
  hush.assert_eq(hush.read("hush_caught"), 1, "hush_caught is set on the frame the meter reaches 0 (criterion 7, pillars.md:111-112)")
  hush.wait(1)
  hush.assert_eq(hush.read("hush_retries"), r0 + 1, "the room restarts the next frame: hush_retries +1 (criterion 7, pillars.md:112)")
  hush.assert_eq(meter.get(), 32, "hush_meter = 32 after the restart (criterion 7, pillars.md:112)")
  hush.assert_eq(hush.read("hush_flash"), base_flash, "same flash as a catch on the restart frame (pillars.md:72-73)")
  hush.assert_eq(base_f, 1, "the caught path itself restarts on the next frame (same timing, pillars.md:73)")
  hush.assert_eq(hush.read("link_x"), r.start_x, "Link back at the start (x)")
  hush.assert_eq(hush.read("link_y"), r.start_y, "Link back at the start (y)")
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "guard unaware again")
  hush.wait(2)
  hush.assert_eq(hush.read("hush_retries"), r0 + 1, "exactly one restart")
  hush.pass("empty meter = the caught restart, retries +1, refilled")
end)
