-- Smoke: the ROM boots and runs 600 frames without crashing, then exit 0.
-- No savestate needed.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

hush.test("boot: 600 frames", function()
  hush.wait(600)
  hush.screenshot("boot_600")
  -- Sanity: the frame counter ($1A) is a live WRAM value; just make sure reads work.
  local fc = hush.read("frame_counter")
  hush.assert(fc >= 0 and fc <= 255, "frame_counter out of range: " .. tostring(fc))
  hush.pass("ran 600 frames, $1A=" .. fc)
end)
