-- Dev probe wrapper (engine, E rev5): src/dev/e5_probe.lua on r05 / r12 / r15 (render-interval outliers).
--   .venv/bin/python tools/run_test.py src/dev/e5_out.lua
-- @timeout 900
HUSH_PROBE_CFG = { ROOMS = "4,11,14", CHECKS = "2" }
dofile(os.getenv("HUSH_ROOT") .. "/src/dev/e5_probe.lua")
