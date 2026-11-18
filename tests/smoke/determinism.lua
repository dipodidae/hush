-- @requires-state
-- @timeout 120
-- Smoke: from the same savestate, the same inputs must produce identical
-- WRAM twice. If this fails, nothing else in the harness can be trusted.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local STATE = os.getenv("HUSH_STATE")
local INPUTS = {
  { { "right" }, 40 }, { {}, 10 }, { { "down" }, 30 }, { { "b" }, 3 }, { {}, 20 },
  { { "left", "b" }, 25 }, { { "up" }, 30 }, { {}, 30 },
}

local function run_once()
  hush.load_state(STATE)
  for _, step in ipairs(INPUTS) do hush.hold(step[1], step[2]) end
  return hush.dump_ram()
end

-- hush.test already loads HUSH_STATE once before the body; the body then loads
-- it again for each run so both runs start from the identical state.
hush.test("determinism: same state + inputs -> same WRAM", function()
  local a = run_once()
  local b = run_once()
  local diff = hush.diff_dumps(a, b)
  if diff then
    local f = io.open(hush.OUT .. "/wram_run_a.bin", "wb"); f:write(a); f:close()
    f = io.open(hush.OUT .. "/wram_run_b.bin", "wb"); f:write(b); f:close()
    hush.fail("WRAM differs between runs: " .. diff)
  end
  hush.pass(string.format("%d bytes of WRAM identical across 2 runs", #a))
end)
