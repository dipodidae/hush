-- Dev utility (QA, not a test): tests/dev/final_probe.lua on the B-008 repro (r15, Link waits at (5,6)).
--   .venv/bin/python tools/run_test.py tests/dev/b008_probe.lua
-- @timeout 300
PROBE_ROOM = "r15"
PROBE_FILE = "tests/chaos/repros/B-008_r15_seen_at_5_6.inputs"
dofile(os.getenv("HUSH_ROOT") .. "/tests/dev/final_probe.lua")
