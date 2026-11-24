-- Dev probe wrapper (engine, E rev5): src/dev/e5_probe.lua on a few rooms (r01, r08, r13, r19, final).
--   .venv/bin/python tools/run_test.py src/dev/e5_quick.lua
-- @timeout 900
HUSH_PROBE_CFG = { ROOMS = "0,7,12,18,20" }
dofile(os.getenv("HUSH_ROOT") .. "/src/dev/e5_probe.lua")
