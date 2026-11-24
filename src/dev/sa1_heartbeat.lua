-- Engine dev probe (NOT a qa test): SA-1 bring-up step 2 (src/hooks/sa1.asm).
-- Checks that the SA-1 runs: status byte = 1 (idle), the heartbeat word in I-RAM keeps increasing,
-- and a command byte written by the "SNES" (here: the probe) is acknowledged (cleared).
--   .venv/bin/python tools/run_test.py src/dev/sa1_heartbeat.lua
-- I-RAM: emu.memType.sa1InternalRam, offset = SNES address - $3000 (docs/ram_map.md "SA-1 memory").
-- The SA-1 is released after the boot-time intro song upload (LoadIntroSongBank, bank_00.asm:33), so poll.
-- @timeout 60
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local IRAM = emu.memType.sa1InternalRam
local function beat() return emu.read16(0x0002, IRAM, false) end

hush.test("sa1 heartbeat", function()
  local f = 0
  while emu.read(0x0001, IRAM, false) ~= 1 and f < 600 do hush.wait(1); f = f + 1 end
  hush.assert_eq(emu.read(0x0001, IRAM, false), 1, "sa1_status after " .. f .. " frames")
  hush.log(string.format("status 1 (idle) at frame %d", hush.frame()))
  local b0 = beat()
  hush.wait(1)
  local b1 = beat()
  hush.wait(1)
  local b2 = beat()
  local d1 = (b1 - b0) & 0xFFFF
  local d2 = (b2 - b1) & 0xFFFF
  hush.log(string.format("heartbeat %d -> %d -> %d (+%d, +%d per frame)", b0, b1, b2, d1, d2))
  hush.assert_gt(d1, 0, "heartbeat increases (frame 1)")
  hush.assert_gt(d2, 0, "heartbeat increases (frame 2)")
  emu.write(0x0000, 0x5A, IRAM)
  hush.wait(1)
  hush.assert_eq(emu.read(0x0000, IRAM, false), 0, "sa1_cmd acknowledged")
  hush.pass(string.format("SA-1 alive: status 1, heartbeat +%d/frame, command acked", d2))
end)
