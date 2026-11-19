-- Chaos (e): determinism. The same seed and the same inputs, entered the same way (restore the post-new-game snapshot, synced debug jump),
-- must give the identical game twice: a hash of the HUSH state (Link, sprite / ancilla tables, the HUSH RAM block, tools) every 100
-- frames and the whole 128 KiB of WRAM at the end. Four runs: random mashing in r05, r12, r20 and pot / dart spam in r14.
-- On a mismatch the first diverging checkpoint and the first differing WRAM addresses are reported and the input stream is written to
-- tests/chaos/repros/determinism_<seed>.inputs.
-- @timeout 200
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")
local rd = C.rd

local RUNS = { { "r05", 401, "mash" }, { "r12", 402, "mash" }, { "r20", 403, "mash" }, { "r14", 404, "spam" } }
local N, STEP = C.frames(1500), 100

-- one run: returns the checkpoints and the final WRAM image; `inputs` is recorded so the second run could replay it (the generator
-- is deterministic in the seed, which is exactly what is under test)
local function once(room, seed, kind)
  local run = C.enter("determinism", seed, room, { menu_limit = 4000 })
  local rng = C.rng(seed)
  local cps = {}
  local nx = C.masher(rng, kind == "spam" and { up = 12, down = 12, left = 12, right = 12, y = 3, b = 60, start = 400 } or C.RATES_ALL)
  local ok, err = pcall(function()
    if kind == "spam" then run:poke(0x7E0202, 4); run:poke(0x7E0303, 1) end
    while run.n < N do
      if run.ending then run:resume_after_ending(run.idx) else
        local b = nx()
        if run.menu_run > 200 and (run.menu_run % 40) < 3 then b = { (run.menu_run % 80) < 40 and "start" or "a" } end
        if kind == "spam" and rd(0xF343) == 0 then run:poke(0x7EF343, 8) end
        run:step(b)
      end
      if run.n % STEP == 0 then cps[#cps + 1] = { n = run.n, h = C.hash_state() } end
    end
  end)
  return run, cps, hush.dump_ram(), ok, err
end

hush.test("chaos determinism: same seed + inputs twice -> identical WRAM", function()
  C.boot()
  for _, r in ipairs(RUNS) do
    local seed = C.seed(r[2])
    local a, cpa, ra, oka, erra = once(r[1], seed, r[3])
    local b, cpb, rb, okb, errb = once(r[1], seed, r[3])
    -- a run is reported through C.guard (CHAOS: line, repro on failure); the body re-throws what the comparison finds
    C.guard(a, function()
      if not oka then error(erra, 0) end
      if not okb then error(errb, 0) end
      for i = 1, math.max(#cpa, #cpb) do
        if not cpa[i] or not cpb[i] or cpa[i].h ~= cpb[i].h then
          a:fail(string.format("run 2 diverges from run 1 at frame %d (state hash %08X vs %08X)", (cpa[i] or cpb[i]).n, cpa[i] and cpa[i].h or 0, cpb[i] and cpb[i].h or 0))
        end
      end
      local diff = hush.diff_dumps(ra, rb)
      if diff then a:fail("state hashes agree but WRAM differs at frame " .. N .. ": " .. diff) end
      hush.log(string.format("determinism %s seed %d: %d checkpoints and %d bytes of WRAM identical (%s, final hash %08X)",
        r[1], seed, #cpa, #ra, r[3], cpa[#cpa] and cpa[#cpa].h or 0))
    end)
  end
  C.finish("4 seeds x 2 runs")
end)
