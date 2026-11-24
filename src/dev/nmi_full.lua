-- Dev probe (engine, SA-1 step 5a; measurement only): sa1_probe.lua in the final room (index 20) with FULL=1: every light NMI that finds
-- nothing published gets a full 28-row window, i.e. a full-window upload every frame (the vblank budget test). @timeout as sa1_probe.
--   .venv/bin/python tools/run_test.py src/dev/nmi_full.lua
-- @timeout 600
HUSH_PROBE_CFG = { FULL = "1", ROOMS = "20" }
dofile(os.getenv("HUSH_ROOT") .. "/src/dev/sa1_probe.lua")
