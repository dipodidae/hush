-- Dev probe wrapper (engine, E rev5): src/dev/sa1_probe.lua (NMI end line, rows per NMI, lag) on r13 / r15 / r19 / r20 / final.
--   .venv/bin/python tools/run_test.py src/dev/e5_nmi.lua
-- @timeout 900
HUSH_PROBE_CFG = { ROOMS = "12,14,18,19,20" }
dofile(os.getenv("HUSH_ROOT") .. "/src/dev/sa1_probe.lua")
