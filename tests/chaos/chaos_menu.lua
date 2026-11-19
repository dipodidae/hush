-- Chaos (b): item-menu mashing. START / SELECT / Y / X (and a few d-pad taps) at random in four rooms. The player must never be left
-- stuck: after the mashing every button is released and a human-style recovery (B, A, START taps, 40 frames apart) must give control
-- back within 600 frames; then the d-pad must move Link (or a guard must catch him: restart). The vanilla SELECT dialog needs A/B
-- (START does not close it: a quirk the recovery covers); "Save and Quit" (B-002) is tolerated unless HUSH_CHAOS_STRICT=1.
-- @timeout 200
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")

local RUNS = { { "r01", 101 }, { "r03", 102 }, { "r10", 103 }, { "r14", 104 }, { "r12", 105 }, { "r20", 106 } }

-- Give control back like a human: tap B, A, START in turn. Returns the number of frames it took.
local function recover(run)
  local f = 0
  local seq = { "b", "a", "start" }
  while (C.rd(0x10) ~= 0x07 or C.rd(0x11) ~= 0 or C.rd(0xC903) ~= 0) do
    if run.ending then run:resume_after_ending(run.idx); break end
    f = f + 1
    if f > 600 then run:fail("player stuck: no control 600 frames after the mashing stopped (module " .. string.format("%02X/%02X", C.rd(0x10), C.rd(0x11)) .. ")") end
    local k = (f // 40) % 3 + 1
    run:step((f % 40) < 3 and { seq[k] } or {})
  end
  return f
end

hush.test("chaos menu: START/SELECT/Y/X mashing never leaves the player stuck", function()
  C.boot()
  for _, r in ipairs(RUNS) do
    local seed = C.seed(r[2])
    local run = C.enter("menu", seed, r[1], { menu_limit = 4000 })
    local rng = C.rng(seed)
    C.guard(run, function()
      local nx = C.masher(rng, C.RATES_MENU)
      local longest, cur = 0, 0
      for _ = 1, C.frames(1200) do
        if run.ending then run:resume_after_ending(run.idx) else run:step(nx()) end
        if C.rd(0x10) == 0x0E then cur = cur + 1; if cur > longest then longest = cur end else cur = 0 end
      end
      local took = recover(run)
      hush.log(string.format("menu %s seed %d: longest menu stay %d frames, recovery %d frames", r[1], seed, longest, took))
      run:settle(300)
      -- Link answers the d-pad again: 4 x 30 frames of one direction each; he must move, or a guard restarts the room
      local x0, y0, restarts0 = C.rd16(0x22), C.rd16(0x20), run.stats.restarts
      local moved = false
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        for _ = 1, 30 do run:step({ d }) end
        if C.rd16(0x22) ~= x0 or C.rd16(0x20) ~= y0 or run.stats.restarts ~= restarts0 then moved = true; break end
      end
      hush.assert(moved, "Link does not react to the d-pad after the menu mashing")
      -- the item selection is sane: the HUD slot is a real slot and START opens / closes the menu cleanly
      hush.assert(C.rd(0x0202) <= 0x14, string.format("selected item slot $0202 = %02X", C.rd(0x0202)))
      run:settle(200)
      for _ = 1, 4 do run:step({ "start" }) end
      local opened = false
      for _ = 1, 60 do run:step({}); if C.rd(0x10) == 0x0E then opened = true; break end end
      hush.assert(opened, "START does not open the item menu")
      for _ = 1, 60 do run:step({}) end
      local closed = false
      for f = 1, 90 do run:step((f % 20) < 3 and { "start" } or {}); if C.rd(0x10) == 0x07 and C.rd(0x11) == 0 then closed = true; break end end
      hush.assert(closed, "START does not close the item menu again")
    end)
  end
  C.finish("6 seeds")
end)
