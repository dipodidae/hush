-- Dev utility (E7, B-006): does a change to the bomb / ancilla code leave the picture and the ancilla state identical?
-- Throws an ink pot in r10 (and, after it, shoots an arrow), then writes one line per frame to HUSH_OAM_OUT (default build/pot_oam.txt):
-- frame, CRC of the OAM buffer $0800-$0A1F, CRC of the ancilla arrays $0BF0-$0CFF, hush_ink_t, ancilla types. Run it on two ROMs (HUSH_ROM=...) and diff the files.
--   HUSH_OAM_OUT=/tmp/a.txt HUSH_ROM=/tmp/old.sfc .venv/bin/python tools/run_test.py tests/dev/pot_oam_diff.lua
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")
local bot = require("bot")

hush.test("pot oam diff", function()
  C.NO_REPRO = true
  C.boot()
  local run = C.enter("potoam", 1, os.getenv("HUSH_POT_ROOM") or "r10")
  local out = io.open(os.getenv("HUSH_OAM_OUT") or (hush.ROOT .. "/build/pot_oam.txt"), "w")
  local function crc(a, n)
    local h = 5381
    for i = 0, n - 1 do h = (h * 33 + C.rd(a + i)) % 4294967296 end
    return h
  end
  local function rec(tag)
    local t = {}
    for i = 0, 9 do local v = C.rd(0xC4A + i); if v ~= 0 then t[#t + 1] = string.format("%02X", v) end end
    if os.getenv("HUSH_DUMP_FRAME") and tonumber(os.getenv("HUSH_DUMP_FRAME")) == run.n then
      local h = {}
      for i = 0, 0x10F do h[#h + 1] = string.format("%02X", C.rd(0xBF0 + i)) end
      out:write("DUMP " .. table.concat(h, " ") .. "\n")
    end
    out:write(string.format("%4d %s oam=%08X anc=%08X ink=%d [%s] 39f=%d,%d\n", run.n, tag, crc(0x800, 0x220), crc(0xBF0, 0x110), C.rd16(0xC90C), table.concat(t, ","), C.rd(0x39F), C.rd(0x3A0)))
  end
  run:poke(0x7EF343, 8); run:poke(0x7E0202, 4); run:poke(0x7E0303, 1)
  run:step({ "up" }); run:step({})
  run:step({ "y" })
  for _ = 1, 3 do run:step({}); end
  for k = 1, 380 do
    run:step({})
    rec("pot")
  end
  run:poke(0x7EF340, 2); run:poke(0x7EF377, 8); run:poke(0x7E0202, 1); run:poke(0x7E0303, 3)
  run:step({ "y" })
  for k = 1, 60 do run:step({}); rec("arr") end
  out:close()
  hush.pass()
end)
