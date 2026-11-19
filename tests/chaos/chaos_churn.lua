-- Chaos (c): churn. (1) 50 rapid room jumps ($7EC901 written at random moments: idle, mid-load, in the item menu, during a restart
-- flash, twice in a row); (2) 50 caught-restarts in the 5-guard room r20 (poke of hush_caught, real contact with a guard, with a
-- bomb / arrow in flight, with the ink cloud up, mid-mash). After every settle the room must look exactly like the first time we saw
-- it (same sprite count, no ancilla, no cloud, same OAM count, Link at the start, full brightness), and the frames it took must stay
-- inside their bounds (restart <= 40, full load <= 700 frames). The per-frame invariants of chaos.lua (free RAM, stack, slots) run all along.
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")
local rd, rd16 = C.rd, C.rd16

local RESTART_MAX, LOAD_MAX = 40, 700

local function signature(run)
  local anc = 0
  for i = 0, 9 do if rd(0xC4A + i) ~= 0 then anc = anc + 1 end end
  local alive = 0
  for s = 0, 15 do if rd(0xDD0 + s) ~= 0 then alive = alive + 1 end end
  return { alive = alive, anc = anc, ink = rd16(0xC90C), oam = C.oam_visible(), x = rd16(0x22), y = rd16(0x20),
    bright = rd(0x13), flash = rd(0xC903), caught = rd(0xC902), room = rd(0xC900) }
end

local baselines = {}
-- Compare a settled room to the first time of the same kind ("load" or "restart") and to the absolute rules.
local function expect_clean(run, kind)
  local s = signature(run)
  hush.assert_eq(s.anc, 0, "ancilla slots in use after " .. kind)
  hush.assert_eq(s.ink, 0, "ink cloud still up after " .. kind)
  hush.assert_eq(s.alive, run.ng, "live sprites after " .. kind .. " (room has " .. run.ng .. " guards)")
  hush.assert_eq(s.bright, 0x0F, "screen brightness after " .. kind)
  hush.assert_eq(s.flash, 0, "hush_flash after " .. kind)
  hush.assert_eq(s.caught, 0, "hush_caught after " .. kind)
  local key = kind .. ":" .. s.room
  local b = baselines[key]
  if not b then baselines[key] = s
  else
    hush.assert_eq(s.x, b.x, key .. ": Link x differs from the first " .. kind)
    hush.assert_eq(s.y, b.y, key .. ": Link y differs from the first " .. kind)
    hush.assert_eq(s.oam, b.oam, key .. ": visible OAM entries differ from the first " .. kind .. " (leak?)")
  end
end

local function select_item(run, which)
  if which == "bombs" then run:poke(0x7E0202, 4); run:poke(0x7E0303, 1) else run:poke(0x7E0202, 1); run:poke(0x7E0303, 3) end
end

hush.test("chaos churn: 50 room jumps, 50 caught-restarts, no leaks", function()
  C.boot()
  local max_load, max_restart = 0, 0

  -- ---- 1. rapid room jumps -------------------------------------------------------------------------------------------------------
  do
    local seed = C.seed(201)
    local run = C.enter("churn_jump", seed, "r10")
    local rng = C.rng(seed)
    C.guard(run, function()
      for i = 1, 50 do
        local target = rng.int(run.nrooms)
        local mode = rng.int(5)
        if mode == 1 then run:idle(rng.int(10)); run:step({ "start" }); run:idle(rng.int(30))          -- jump while the item menu is opening
        elseif mode == 2 then run:poke(0x7EC902, 1); run:idle(rng.int(4))                              -- jump right after a caught restart began
        end
        local f0 = run.n
        run:jump(target)
        if mode == 3 then                                                                               -- a second jump while the first one loads
          run:idle(1 + rng.int(60))
          local t2 = rng.int(run.nrooms)
          run:jump(t2); target = t2
        else
          run:idle(rng.int(8))
        end
        -- the menu may still be open (mode 1) or the load running: bounded wait for control; a pending request fires once the menu closes
        local waited = 0
        while not (rd(0x10) == 0x07 and rd(0x11) == 0 and rd(0xC900) == target and rd(0xC903) == 0) do
          waited = waited + 1
          if waited > LOAD_MAX then run:fail("jump to room " .. target .. " did not finish in " .. LOAD_MAX .. " frames") end
          run:step(rd(0x10) == 0x0E and ((waited % 30) < 3 and { "start" } or {}) or {})
        end
        run:settle(60)
        run:clear_expect()
        run:idle(20)
        local took = run.n - f0
        if took > max_load then max_load = took end
        expect_clean(run, "load")
        -- some random play before the next jump
        local nx = C.masher(rng, C.RATES_ALL)
        for _ = 1, rng.int(60) do run:step(nx()) end
        if run.ending then run:resume_after_ending(target) end
      end
    end)
  end

  -- ---- 2. caught-restart loops in the 5-guard room -----------------------------------------------------------------------------------
  do
    local seed = C.seed(202)
    local run = C.enter("churn_restart", seed, "r20")
    local rng = C.rng(seed)
    C.guard(run, function()
      run:idle(30)
      expect_clean(run, "load")
      for i = 1, 50 do
        local action = rng.int(5)
        if action == 1 then                                         -- a pot in flight, then caught
          select_item(run, "bombs"); run:poke(0x7EF343, 8)
          run:step({ "y" }); run:idle(2 + rng.int(40))
        elseif action == 2 then                                     -- an arrow in flight
          select_item(run, "bow"); run:poke(0x7EF377, 8)
          run:step({ "y" }); run:idle(2 + rng.int(20))
        elseif action == 3 then                                     -- the cloud is up (placed ~157 frames before it opens)
          select_item(run, "bombs"); run:poke(0x7EF343, 8)
          run:step({ "y" }); run:idle(2)
          for _ = 1, 190 do if C.rd16(0xC90C) > 0 then break end; run:step({}) end
          run:idle(rng.int(20))
        elseif action == 4 then                                     -- random play first
          local nx = C.masher(rng, C.RATES_ALL)
          for _ = 1, 10 + rng.int(80) do run:step(nx()) end
        end
        if run.ending then run:resume_after_ending(run.idx) end
        -- the game is paused in a menu: no guard can catch Link there (and the poke would wait), so close it like a player would
        for f = 1, 400 do
          if rd(0x10) == 0x07 and rd(0x11) == 0 then break end
          run:step((f % 40) < 3 and { (f % 80) < 40 and "start" or "a" } or {})
        end
        run:settle(400)
        local before = run.stats.restarts
        local f0 = run.n
        if rng.chance(1, 2) and rd(0xDD0) ~= 0 then
          -- a real catch: Link stands on guard 0 (he turns alert on contact, the next frame is the catch)
          local gx = rd(0xD30) * 256 + rd(0xD10)
          local gy = rd(0xD20) * 256 + rd(0xD00)
          run:teleport(gx, gy - 8)
          for _ = 1, 8 do run:step({}); if run.stats.restarts > before then break end end
        end
        if run.stats.restarts == before and rd(0xC903) == 0 then
          -- no real catch (the guard was asleep, or died to a sword swing in progress): ask for it, like the AI does
          run:poke(0x7EC902, 1)
          run:step({})
        end
        local waited = 0
        while not (rd(0x10) == 0x07 and rd(0x11) == 0 and rd(0xC903) == 0 and rd(0xC902) == 0 and run.stats.restarts > before) do
          waited = waited + 1
          if waited > RESTART_MAX + 20 then run:fail("restart " .. i .. " (action " .. action .. ") did not finish in " .. (RESTART_MAX + 20) .. " frames") end
          run:step({})
        end
        local took = run.n - f0
        if took > max_restart then max_restart = took end
        hush.assert(took <= RESTART_MAX, "restart " .. i .. " took " .. took .. " frames (bound " .. RESTART_MAX .. ")")
        run:idle(20)
        expect_clean(run, "restart")
      end
    end)
  end

  hush.log(string.format("longest full load %d frames (bound %d), longest restart %d frames (bound %d)", max_load, LOAD_MAX, max_restart, RESTART_MAX))
  C.finish(string.format("longest load %d, longest restart %d frames", max_load, max_restart))
end)
