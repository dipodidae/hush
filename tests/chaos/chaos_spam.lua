-- Chaos (d): ink pot / dart spam. Y is hit every few frames with the item flipped between the bow and the pots every few frames (never
-- while an item is in use: that is not reachable with a pad), every ~150 frames through the REAL item menu, the
-- ammo is refilled whenever it runs out (so 8 pots, then 8 more ...), Link walks at random and swings the knife now and then, in rooms
-- with 1, 3, 4, 5 and 6 guards. Invariants (chaos.lua) all the time, plus: the ink cloud timer and centre stay sane, only known ancilla
-- types appear, a guard that stands in the cloud is not suspicious / alert for more than a few frames (unless he touches Link).
-- Afterwards the input stops: every ancilla slot must empty and the cloud end within 900 frames, and the OAM count must settle.
-- @timeout 200
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")
local rd, rd16 = C.rd, C.rd16

local RUNS = { { "r10", 301 }, { "r12", 302 }, { "r14", 303 }, { "r20", 304 }, { "final", 305 }, { "r19", 306 } }
-- ancilla ids that may appear: bomb $07, arrow $09, stuck arrow $0A, sword spark / charge sparkle $30 / $3C, plus a few vanilla effects.
-- An id above $3F is garbage and fails; an id outside this list is only reported in the log.
local KNOWN = { [0x00] = true, [0x07] = true, [0x09] = true, [0x0A] = true, [0x05] = true, [0x08] = true, [0x0B] = true, [0x0C] = true,
  [0x13] = true, [0x15] = true, [0x1E] = true, [0x23] = true, [0x30] = true, [0x31] = true, [0x3C] = true }

hush.test("chaos spam: ink pots and darts, 8 at a time, ancilla and cloud logic stable", function()
  C.boot()
  for _, r in ipairs(RUNS) do
    local seed = C.seed(r[2])
    local run = C.enter("spam", seed, r[1])
    local rng = C.rng(seed)
    local types_seen, max_anc, max_ink, pots, shots = {}, 0, 0, 0, 0
    C.guard(run, function()
      local dirs = C.masher(rng, { up = 12, down = 12, left = 12, right = 12, b = 90 })
      local want_item, since_flip = "bombs", 0
      local y_hold, y_gap = 0, 0
      local in_cloud = {}
      -- one cheap extra invariant per frame
      run.hooks[#run.hooks + 1] = function(self)
        local n_anc = 0
        for i = 0, 9 do
          local t = rd(0xC4A + i)
          if t ~= 0 then n_anc = n_anc + 1; if not types_seen[t] then types_seen[t] = self.n end end
          if t > 0x3F then self:fail(string.format("garbage ancilla type $%02X in slot %d", t, i)) end
        end
        if n_anc > max_anc then max_anc = n_anc end
        local t = rd16(0xC90C)
        if t > max_ink then max_ink = t end
        if t > 0 then
          local cx, cy = rd16(0xC908), rd16(0xC90A)
          local wx, wy = self.room.base_x + self.m.win_x, self.room.base_y + self.m.win_y
          if cx < wx - 24 or cx > wx + 280 or cy < wy - 24 or cy > wy + 248 then self:fail(string.format("ink cloud centre (%d,%d) is outside the room window", cx, cy)) end
          local lx, ly = rd16(0x22) + 8, rd16(0x20) + 16
          for s = 0, self.ng - 1 do
            local aw = rd(0xD80 + s)
            if rd(0xDD0 + s) ~= 0 then
              local gx = rd(0xD30 + s) * 256 + rd(0xD10 + s) + 8
              local gy = rd(0xD20 + s) * 256 + rd(0xD00 + s) + 8
              local inside = math.abs(gx - cx) <= 24 and math.abs(gy - cy) <= 24
              local touching = math.abs(gx - lx) < 16 and math.abs(gy - ly) < 16
              if inside and (aw == 1 or aw == 2) and not touching then
                in_cloud[s] = (in_cloud[s] or 0) + 1
                if in_cloud[s] > 6 then self:fail(string.format("guard %d is %s for %d frames inside the ink cloud (centre %d,%d; guard %d,%d)", s, aw == 1 and "SUSPICIOUS" or "ALERT", in_cloud[s], cx, cy, gx, gy)) end
              else in_cloud[s] = 0 end
            end
          end
        else
          in_cloud = {}
        end
      end

      local frames = C.frames(1500)
      while run.n < frames do
        if run.ending then run:resume_after_ending(run.idx) end
        -- keep the ammo coming
        if rd(0x7EF343 - 0x7E0000) == 0 then run:poke(0x7EF343, 8) end
        if rd(0x7EF377 - 0x7E0000) == 0 then run:poke(0x7EF377, 8) end
        -- flip between the two tools every 6..14 frames
        -- (only while no item is in use: flipping $0303 mid-bow-draw is not something a player can do - the menu pauses the game -
        --  and it crashes the vanilla item handler: docs/bugs.md note under B-003)
        since_flip = since_flip - 1
        if since_flip <= 0 and rd(0x0300) == 0 and rd(0x0301) == 0 and rd(0x3C) == 0 and y_hold == 0 then
          since_flip = rng.range(6, 14)
          want_item = (want_item == "bombs") and "bow" or "bombs"
          if want_item == "bombs" then run:poke(0x7E0202, 4); run:poke(0x7E0303, 1) else run:poke(0x7E0202, 1); run:poke(0x7E0303, 3) end
        end
        if run.n % 150 == 149 and rd(0x0300) == 0 and rd(0x0301) == 0 then
          local slot = (want_item == "bombs") and 1 or 4      -- switch to the other tool through the real menu
          run:menu_select(slot)
          want_item = (slot == 4) and "bombs" or "bow"
        end
        local b = dirs()
        if y_hold > 0 then y_hold = y_hold - 1; b[#b + 1] = "y"
        elseif y_gap > 0 then y_gap = y_gap - 1
        else
          y_hold = rng.range(0, 2); y_gap = rng.range(0, 6); b[#b + 1] = "y"
          if want_item == "bombs" then pots = pots + 1 else shots = shots + 1 end
        end
        if rd(0x10) == 0x0E then b = (run.menu_run % 30) < 3 and { "start" } or {} end    -- never sit in a menu
        run:step(b)
      end
      -- stop everything: slots must empty, the cloud must end
      run.hooks = {}
      for f = 1, 900 do
        run:step({})
        local anc = 0
        for i = 0, 9 do if rd(0xC4A + i) ~= 0 then anc = anc + 1 end end
        if anc == 0 and rd16(0xC90C) == 0 and rd(0x10) == 0x07 and rd(0xC903) == 0 then break end
        if f == 900 then run:fail("after the spam stopped, " .. anc .. " ancilla slot(s) / cloud t=" .. rd16(0xC90C) .. " still active after 900 frames") end
      end
      run:idle(30)
      -- frame lag is reported, not failed (docs/bugs.md B-006); the inputs of a laggy run are kept in the test's result dir
      if run.stats.lagged > run.n * 0.05 then
        local f = io.open(string.format("%s/spam_%d_lag.inputs", hush.OUT, seed), "w")
        if f then f:write(run:repro_text("frame lag " .. run.stats.lagged .. " of " .. run.n)); f:close() end
      end
      hush.assert(run.stats.lagged <= run.n * 0.30, "frame lag: " .. run.stats.lagged .. " of " .. run.n .. " frames lost (limit 30 %)")
      local ts = {}
      for t in pairs(types_seen) do ts[#ts + 1] = string.format("$%02X", t) end
      table.sort(ts)
      hush.log(string.format("spam %s seed %d: %d pot presses, %d dart presses, max %d ancilla slots, max cloud timer %d, ancilla types %s",
        r[1], seed, pots, shots, max_anc, max_ink, table.concat(ts, " ")))
    end)
  end
  C.finish("6 seeds")
end)
