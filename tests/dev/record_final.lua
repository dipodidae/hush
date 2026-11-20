-- Dev utility (QA, not a test): runs tests/dev/record_room.lua with fixed paths, because tools/run_test.py passes no extra env:
--   plan   tests/dev/plans/final_qa.plan     (hand-timed from design/rooms/final.yaml intended_solution, lines 80-91)
--   output build/test-results/dev_record_final/final.inputs  (tests/dev/final_probe.lua replays it; copy it to
--          tests/solutions/final.inputs once the probe shows no "?" and meter 32)
--   .venv/bin/python tools/run_test.py tests/dev/record_final.lua
-- @timeout 300
local getenv = os.getenv
local fixed = { HUSH_PLAN = "tests/dev/plans/final_qa.plan", HUSH_REC_OUT = getenv("HUSH_OUT") .. "/final.inputs" }
os.getenv = function(k) if fixed[k] then return fixed[k] end return getenv(k) end
dofile(getenv("HUSH_ROOT") .. "/tests/dev/record_room.lua")
