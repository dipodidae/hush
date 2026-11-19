-- Chaos (f): frame-offset edges (the "planned fuzz targets" of tests/chaos/README.md that the real mechanics allow).
--   1. Attack on the frame a guard turns: in r05 (still guard, dark) Link appears in the guard's cone 24 px in front of him at frame T
--      and swings the knife / fires a dart at T + k, k = -6 .. +8. Whatever k is, the awareness rules must hold (chaos.lua: only an
--      UNAWARE guard dies, only an UNAWARE guard falls asleep, a Suspicious / Alert guard never takes damage).
--   2. Two guards alerting at once (r14: c and d see the corridor cell (7,4) / (8,4) in the same frame): both end Alert, the catch restarts
--      the room exactly once, the guards are unaware again afterwards.
--   3. Exit versus catch (r02): hush_caught is set k frames before / after Link is teleported onto the exit cell, k = -4 .. +4. Either
--      the room restarts or the next room loads, never both, never a half state: the settled room is clean (no ancilla, no cloud, all
--      guards alive, full brightness) and the game stays under control.
-- @timeout 200
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local C = require("chaos")
local rd, rd16 = C.rd, C.rd16

local function px(run, cx, cy) return run.room.base_x + run.m.win_x + 16 * cx, run.room.base_y + run.m.win_y + 16 * cy - 8 end

local function clean(run, what)
  local anc = 0
  for i = 0, 9 do if rd(0xC4A + i) ~= 0 then anc = anc + 1 end end
  local alive = 0
  for s = 0, 15 do if rd(0xDD0 + s) ~= 0 then alive = alive + 1 end end
  hush.assert_eq(anc, 0, what .. ": ancilla slots in use")
  hush.assert_eq(rd16(0xC90C), 0, what .. ": ink cloud up")
  hush.assert_eq(alive, run.ng, what .. ": live sprites (room has " .. run.ng .. " guards)")
  hush.assert_eq(rd(0x13), 0x0F, what .. ": screen brightness")
  hush.assert_eq(rd(0xC903), 0, what .. ": hush_flash")
  hush.assert_eq(rd(0xC902), 0, what .. ": hush_caught")
end

hush.test("chaos edge: attack on the turn, simultaneous alert, exit vs catch", function()
  C.boot()

  -- ---- 1. attack on the turn ----------------------------------------------------------------------------------------------------------
  for _, weapon in ipairs({ "knife", "dart" }) do
    for k = -6, 8 do
      local seed = C.seed(500 + (weapon == "dart" and 100 or 0) + k + 6)
      local run = C.enter("edge_turn_" .. weapon, seed, "r05")
      C.guard(run, function()
        run:idle(3)
        if weapon == "dart" then run:poke(0x7E0202, 1); run:poke(0x7E0303, 3) end
        local g = { x = rd(0xD30) * 256 + rd(0xD10), y = rd(0xD20) * 256 + rd(0xD00) }     -- guard a, (13,7), facing west
        local hidden_x = g.x - 16                                                              -- south-west of him (cell (12,9)), outside his 90-degree cone
        run:teleport(hidden_x, g.y + 32 - 8)
        run:poke(0x7E002F, 4)
        run:idle(6)
        -- appear in front of him: 24 px west (knife reach) / 64 px west (dart); the guard notices within 2 frames
        local vx = g.x - (weapon == "knife" and 24 or 64)
        local t0 = run.n
        local appear_at, swing_at = (k >= 0) and 0 or -k, (k >= 0) and k or 0      -- the swing is k frames after the guard could first see Link
        for rel = 0, 39 do
          if rel == appear_at then run:teleport(vx, g.y - 8); run:poke(0x7E002F, 6) end
          local swing = rel >= swing_at and rel < swing_at + 3
          run:step(swing and { weapon == "knife" and "b" or "y" } or {})
        end
        run:idle(30)
      end)
    end
  end

  -- ---- 2. two guards alert at once --------------------------------------------------------------------------------------------------
  for _, cell in ipairs({ { 7, 4 }, { 8, 4 } }) do
    local seed = C.seed(700 + cell[1])
    local run = C.enter("edge_two", seed, "r14")
    C.guard(run, function()
      run:idle(3)
      local x, y = px(run, cell[1], cell[2])
      run:teleport(x, y)
      local r0 = run.stats.restarts
      local both
      for f = 1, 300 do
        run:step({})
        if rd(0xD80) == 2 and rd(0xD81) == 2 then both = f end
        if run.stats.restarts > r0 then break end
      end
      hush.assert(both ~= nil or run.stats.restarts > r0, "neither both guards turned Alert nor was Link caught within 300 frames")
      for f = 1, 120 do run:step({}) end
      hush.assert_eq(run.stats.restarts, r0 + 1, "the catch must restart the room exactly once")
      run:settle(60)
      run:idle(10)
      for s = 0, run.ng - 1 do hush.assert_eq(rd(0xD80 + s), 0, "guard " .. s .. " unaware after the restart") end
      clean(run, "after the double alert")
    end)
  end

  -- ---- 3. exit versus catch ----------------------------------------------------------------------------------------------------------
  for k = -4, 4 do
    local seed = C.seed(800 + k + 4)
    local run = C.enter("edge_exit", seed, "r02")
    C.guard(run, function()
      run:idle(3)
      local ex, ey = px(run, 13, 2)
      local sx, sy = rd16(0x22), rd16(0x20)
      local t0 = run.n
      for f = 0, 12 do
        local rel = run.n - t0
        if rel == math.max(0, -k) then run:teleport(ex, ey) end        -- onto the exit cell
        if rel == math.max(0, k) then run:poke(0x7EC902, 1) end                                 -- hush_caught
        run:step({})
      end
      run:clear_expect()
      -- whatever happened: bounded wait for control, then the room we are in must be clean
      local w = 0
      while not (rd(0x10) == 0x07 and rd(0x11) == 0 and rd(0xC903) == 0 and rd(0xC902) == 0) do
        w = w + 1
        if w > 700 then run:fail("no control 700 frames after the exit / catch race (k=" .. k .. ")") end
        run:step({})
      end
      run:idle(30)
      local room = rd(0xC900)
      hush.assert(room == 1 or room == 2, "ended in room " .. room .. " (expected r02 = 1 or r03 = 2)")
      run.ng = #run.m.rooms[room + 1].guards
      clean(run, "after the race (room " .. room .. ")")
      hush.log(string.format("exit vs catch k=%d: ended in room %d", k, room))
    end)
  end

  C.finish("edges")
end)
