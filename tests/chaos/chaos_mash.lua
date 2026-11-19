-- Chaos (a): random button mashing. 22 seeds over 16 rooms (all the guard counts: 1..6, dark and lit, every tool), each ~2000 frames
-- of seeded random input on all 12 buttons from a fresh entry of the room. After every frame tests/chaos/lib/chaos.lua checks the
-- invariants (module, camera, Link inside the window and never in a wall, health, sprite slots, awareness transitions, ancillae, free
-- RAM, stack, hang watchdog). A failing seed writes tests/chaos/repros/mash_<seed>.inputs and the run goes on with the next seed.
-- Env: HUSH_CHAOS_SEED=k (new inputs), HUSH_CHAOS_SCALE=f (shorter / longer), HUSH_CHAOS_STRICT=1 (B-002 fails instead of being tolerated).
-- @timeout 330
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")

-- { room, seed [, item] }: item = the tool preselected before the mashing starts (nil = whatever the room load left)
local RUNS = {
  { "r01", 1 }, { "r01", 2 }, { "r02", 3 }, { "r03", 4, "knife" }, { "r03", 5, "knife" }, { "r04", 6 },
  { "r05", 7 }, { "r05", 8 }, { "r06", 9 }, { "r07", 10, "bow" }, { "r08", 11 }, { "r10", 12, "bombs" },
  { "r11", 13 }, { "r12", 14 }, { "r12", 15, "bow" }, { "r14", 16, "bombs" }, { "r17", 17, "bow" }, { "r19", 18, "bombs" },
  { "r20", 19 }, { "r20", 20, "bow" }, { "final", 21, "bombs" }, { "final", 22, "bow" },
}
local ITEM = { bow = { 1, 3 }, bombs = { 4, 1 } }   -- HUD slot ($0202), equipped id ($0303): docs/engine_notes.md 11.5

hush.test("chaos mash: random buttons on 22 seeds, invariants every frame", function()
  C.boot()
  for _, r in ipairs(RUNS) do
    local seed = C.seed(r[2])
    local run = C.enter("mash", seed, r[1])
    local rng = C.rng(seed)
    C.guard(run, function()
      if r[3] and ITEM[r[3]] then run:poke(0x7E0202, ITEM[r[3]][1]); run:poke(0x7E0303, ITEM[r[3]][2]) end
      C.mash(run, rng, C.frames(2000), C.RATES_ALL)
      -- performance: more than 15 % of the play frames lost to lag would be a regression of B-001
      hush.assert(run.stats.lagged <= run.n * 0.15, "frame lag: " .. run.stats.lagged .. " of " .. run.n .. " frames lost")
    end)
  end
  C.finish("22 seeds")
end)
