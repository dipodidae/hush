-- Smoke (E4): the guard drawing. Every call of Hush_DrawGuard (src/hooks/guard_draw.asm) is checked against the SHEET CONTRACT of
-- docs/gfx/art_map.md section 5: which OAM entries it writes (5 per guard: head, lantern, body, icon, shadow), which GFX_BC tiles
-- ($40-$7F; tile = $40 + cell index) for each facing / walk phase / state, flips, palette bits, positions, sizes. The check is done at
-- the instruction level: an exec callback on the entry of the routine snapshots the guard's RAM (state, facing, position, walk counter),
-- one on the return address reads back the 5 OAM entries it wrote through the OAM pointers $90 / $92, and a Lua model of the contract
-- compares them. Scenarios: natural patrols (facings, walk phases), every state x facing forced on the 4 guards of r14, the culling window,
-- the lantern flicker period. Screenshots of the forced poses go to build/test-results/smoke_guard_draw/.
-- OAM priorities (design/tiles.md 2.1 rule 3, revision 4; acceptance 7.10): head and body 2; "?" / "!" icon 3 (attr $39); lantern 3
-- while ALERT (2 or 3 otherwise: the spec says only "alert lantern"); "Z" icon 2 or 3 (not named by the spec); shadow follows the body.
-- Real ROM (design rooms); needs build/hush.sym (make build).
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local function sym(name)
  local f = assert(io.open(os.getenv("HUSH_ROOT") .. "/build/hush.sym"))
  for l in f:lines() do
    local b, a, n = l:match("^(%x%x):(%x%x%x%x) (%S+)")
    if n == name then f:close(); return tonumber(b, 16) * 65536 + tonumber(a, 16) end
  end
  f:close()
  error({ hush_fail = "symbol " .. name .. " not in build/hush.sym" })
end

local function room_index(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1 end end
  error({ hush_fail = "no room " .. id })
end

local WRAM = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, WRAM, false) end            -- a = WRAM offset (= SNES $7E0000 + a)
local function word(a) return rd(a) + 256 * rd(a + 1) end

-- ---- the contract (docs/gfx/art_map.md section 5), written independently of the ASM tables ----------------------------------
local FACING = { [0] = "right", [1] = "left", [2] = "down", [3] = "up" }
local HEAD = { right = 0x44, left = 0x44, down = 0x40, up = 0x42, sleep = 0x46 }
local BODY = { -- by phase 0..3: tile, H flip
  down = { { 0x48, 0 }, { 0x4A, 0 }, { 0x48, 0 }, { 0x4A, 0x40 } },
  up = { { 0x4C, 0 }, { 0x4E, 0 }, { 0x4C, 0 }, { 0x4E, 0x40 } },
  left = { { 0x60, 0 }, { 0x62, 0 }, { 0x60, 0 }, { 0x64, 0 } },
  right = { { 0x60, 0x40 }, { 0x62, 0x40 }, { 0x60, 0x40 }, { 0x64, 0x40 } },
}
local LANTERN = { right = { 13, 6 }, left = { -5, 6 }, down = { 10, 6 }, up = { -3, 6 }, sleep = { 10, 10 } }
local SHADOW_DY = { right = 12, left = 12, down = 10, up = 10 }
local TILE = { head = { [0x40] = "head_down", [0x42] = "head_up", [0x44] = "head_side", [0x46] = "head_sleep" },
               body = { [0x48] = "down_A", [0x4A] = "down_B", [0x4C] = "up_A", [0x4E] = "up_B", [0x60] = "side_A", [0x62] = "side_B", [0x64] = "side_C", [0x66] = "sleep" } }
local ZONE = { x0 = 8, x1 = 231, y0 = 24, y1 = 199 }   -- guard origin (screen px) inside which every part is drawn

local function s8(v) return v >= 128 and v - 256 or v end

-- what the routine must have written, from the RAM snapshot taken at its entry
local function expect(s)
  local face = (s.state == 3) and "sleep" or FACING[s.dir]
  local facing_for_shadow = FACING[s.dir]
  local inzone = s.x >= ZONE.x0 and s.x <= ZONE.x1 and s.y >= ZONE.y0 and s.y <= ZONE.y1
  local e = {}
  if not inzone then return nil end
  local pal = (s.state == 2) and 0x0D or (s.e60 & 0x0F)
  local attr = pal ~ s.b89
  local phase = 0
  if face ~= "sleep" and (s.v40 ~= 0 or s.v50 ~= 0) then phase = (s.e80 >> 3) & 3 end
  local body, bflip
  if face == "sleep" then body, bflip = 0x66, 0 else body, bflip = BODY[face][phase + 1][1], BODY[face][phase + 1][2] end
  e.head = { x = s.x, y = s.y - 8, tile = HEAD[face], attr = attr | ((face == "right") and 0x40 or 0), size = 2, prio = 2 }
  -- lantern: priority bits checked apart (design/tiles.md 2.1 rule 3: "the guard's alert lantern, if it is a separate OAM entry" = 3;
  -- the spec is silent on the lantern of a non-alert guard, so 2 or 3 is accepted there)
  e.lantern = { x = s.x + LANTERN[face][1], y = s.y + LANTERN[face][2], attr = attr, size = 0, prio = (s.state == 2) and 3 or "2or3" }
  e.body = { x = s.x, y = s.y, tile = body, attr = attr | bflip, size = 2, prio = 2 }
  if s.state ~= 0 then
    -- design/tiles.md 2.1 rule 3 (rev 4): icons "?" / "!" are OAM priority 3 -> attr $39 (was $29: priority 2); palette 4, name table 1
    -- unchanged (docs/gfx/art_map.md section 6). The spec names only "?" / "!": the "Z" (asleep, state 3) may be 2 or 3.
    e.icon = { x = s.x + 4, y = s.y - 22, tile = 0xFB + s.state, attr = 0x39, size = 0, prio = (s.state == 3) and "2or3" or 3 }
  end
  e.shadow = { x = s.x, y = s.y + SHADOW_DY[facing_for_shadow], tile = 0x6C, attr = (attr & 0x30) | 0x08, size = 2 }
  e.face, e.phase = face, phase
  return e
end

-- ---- the probe: one record per Hush_DrawGuard call ------------------------------------------------------------------------------
local calls, pending = {}, nil
local fail_first
local seen = { head = {}, body = {}, flip = {}, lantern = {}, hidden = 0, drawn = 0, alloc = {} }
local function read_entry(i)
  local p90 = word(0x90)
  local b = p90 + 4 * i
  local hi = rd(word(0x92) + i)
  return { x = rd(b) + ((hi & 1) ~= 0 and 256 or 0), y = rd(b + 1), tile = rd(b + 2), attr = rd(b + 3), size = hi & 2 }
end

local function snapshot()
  local st = emu.getState()
  local slot = st["cpu.x"] & 0xFF
  local ex, ey = word(0xE2), word(0xE8)
  local function sp(a) return rd(a) end
  local x = (sp(0x0D30 + slot) * 256 + sp(0x0D10 + slot) - ex) & 0xFFFF
  local y = (sp(0x0D20 + slot) * 256 + sp(0x0D00 + slot) - ey) & 0xFFFF
  if x >= 0x8000 then x = x - 0x10000 end
  if y >= 0x8000 then y = y - 0x10000 end
  return { slot = slot, state = sp(0x0D80 + slot), dir = sp(0x0DE0 + slot) & 3, x = x, y = y, v40 = sp(0x0D40 + slot), v50 = sp(0x0D50 + slot),
           e80 = sp(0x0E80 + slot), e60 = sp(0x0E60 + slot), b89 = sp(0x0B89 + slot), e40 = sp(0x0E40 + slot), frame = sp(0x1A) }
end

local function check_call(s)
  local e = expect(s)
  local ents = {}
  for i = 0, 4 do ents[i] = read_entry(i) end
  local function bad(msg)
    if not fail_first then
      fail_first = string.format("frame %d slot %d state=%d dir=%d pos=(%d,%d) v=(%d,%d) e80=%d: %s", hush.frame(), s.slot, s.state, s.dir, s.x, s.y, s.v40, s.v50, s.e80, msg)
    end
  end
  seen.alloc[s.e40 & 0x1F] = true
  if not e then
    seen.hidden = seen.hidden + 1
    for i = 0, 4 do if ents[i].y ~= 0xF0 then bad("outside the culling window but entry " .. i .. " is visible") end end
    return
  end
  seen.drawn = seen.drawn + 1
  local order = { "head", "lantern", "body", "icon", "shadow" }
  for i, name in ipairs(order) do
    local want, got = e[name], ents[i - 1]
    if not want then
      if got.y ~= 0xF0 then bad(name .. " entry must be hidden (Y=$F0), Y=" .. got.y) end
    else
      if got.x ~= want.x or got.y ~= (want.y & 0xFF) then bad(string.format("%s at (%d,%d), expected (%d,%d)", name, got.x, got.y, want.x, want.y)) end
      if want.tile and got.tile ~= want.tile then bad(string.format("%s tile $%02X, expected $%02X", name, got.tile, want.tile)) end
      -- attribute without the priority bits (4-5), then the priority on its own (design/tiles.md 2.1 rule 3)
      if (got.attr & 0xCF) ~= (want.attr & 0xCF) then bad(string.format("%s attr $%02X, expected $%02X (priority bits aside)", name, got.attr, want.attr)) end
      local gp = (got.attr >> 4) & 3
      if want.prio == "2or3" then
        if gp ~= 2 and gp ~= 3 then bad(string.format("%s OAM priority %d, expected 2 or 3", name, gp)) end
      elseif want.prio then
        if gp ~= want.prio then bad(string.format("%s OAM priority %d, design/tiles.md 2.1 rule 3 says %d (state %d)", name, gp, want.prio, s.state)) end
      elseif got.attr ~= want.attr then bad(string.format("%s attr $%02X, expected $%02X", name, got.attr, want.attr)) end
      if got.size ~= want.size then bad(string.format("%s size bit %d, expected %d", name, got.size, want.size)) end
    end
  end
  local lt = ents[1].tile
  if lt ~= 0x68 and lt ~= 0x69 then bad(string.format("lantern tile $%02X", lt)) end
  if e.face == "sleep" and lt ~= 0x69 then bad("sleeping guard: lantern must be frame 1 ($69)") end
  -- coverage counters
  seen.head[ents[0].tile] = true
  seen.body[ents[2].tile] = true
  seen.lantern[lt] = true
  seen.flip[string.format("%s:%d:%02X", e.face, e.phase, ents[2].attr & 0xC0)] = true
  -- every tile the guard wrote lies in the contract: GFX_BC $40-$7F (+ the GFX_C5 icon tiles, + the name-table-0 shadow tile)
  for i = 0, 3 do
    local t = ents[i]
    if t.y ~= 0xF0 and not (t.tile >= 0x40 and t.tile <= 0x7F) and not (t.tile >= 0xFC and t.tile <= 0xFE) then bad(string.format("entry %d tile $%02X outside GFX_BC $40-$7F / icons", i, t.tile)) end
  end
end

local function install()
  local entry, ret = sym("Hush_DrawGuard"), sym("Hush_GuardAI") + 4
  emu.addMemoryCallback(function() pending = snapshot() end, emu.callbackType.exec, entry, entry)
  emu.addMemoryCallback(function()
    if pending then calls[#calls + 1] = pending.slot; check_call(pending); pending = nil end
  end, emu.callbackType.exec, ret, ret)
end

local function guards_alive(maxn)
  local t = {}
  for s = 0, 15 do if hush.read("spr_type", s) == 0x41 and hush.read("spr_state", s) == 9 and rd(0x0E30 + s) ~= 0 then t[#t + 1] = s end end
  return t
end

hush.test("guard_draw: OAM contract of the custom guard drawing", function()
  bot.start_new_game()
  install()

  -- 1. natural play: patrols and stills (facings, walk phases, flips), r06 / r09 / r13
  for _, id in ipairs({ "r06", "r09", "r13", "r14" }) do
    bot.jump_to_room(room_index(id))
    hush.wait(420)
    hush.assert(not fail_first, "natural play " .. id .. ": " .. tostring(fail_first))
  end
  hush.assert(seen.drawn > 1500, "enough guard draws observed: " .. seen.drawn)
  hush.assert_eq(seen.hidden, 0, "no guard of a design room is ever outside the culling window")
  local steps = 0
  for _, t in ipairs({ 0x4A, 0x4E, 0x62, 0x64 }) do if seen.body[t] then steps = steps + 1 end end
  hush.assert(steps >= 2, "patrolling guards showed step frames (body B/C tiles)")
  hush.assert(seen.body[0x48] or seen.body[0x4C] or seen.body[0x60], "standing frames seen")

  -- 2. every state x facing forced on the 4 guards of r14 (slot order = spec order); screenshots
  bot.jump_to_room(room_index("r14"))
  hush.wait(10)
  local g = guards_alive()
  hush.assert_eq(#g, 4, "r14 has 4 guards")
  -- park Link in the start corner so the guards neither catch nor restart anything during the sweep.
  -- The poses are forced, not earned: hush_aprev (the meter's last-seen spr_aware, docs/ram_map.md) is set to the forced state so the
  -- stealth meter (design/pillars.md:52-59) sees no transition and does not drain; the meter is not what this test checks.
  local sheets = { [0] = "unaware", [1] = "suspicious", [2] = "alert", [3] = "asleep" }
  for state = 0, 3 do
    for rot = 0, 3 do
      for rep = 1, 6 do
        for k, s in ipairs(g) do
          bot.poke(0x7E0D80 + s, state)
          hush.write("hush_aprev", state, s)
          bot.poke(0x7E0DE0 + s, (k - 1 + rot) % 4)
          bot.poke(0x7E0E10 + s, 250); bot.poke(0x7E0DF0 + s, 250); bot.poke(0x7E0D90 + s, 5); bot.poke(0x7E0EE0 + s, 60)
        end
        hush.wait(1)
        hush.assert(not fail_first, "forced pose: " .. tostring(fail_first))
        hush.assert(bot.peek(0x7EC902) == 0, "nobody caught Link during the sweep")
      end
      if rot == 0 or state == 0 then
        hush.screenshot(string.format("guard_%s_rot%d", sheets[state], rot))
      end
    end
  end
  for _, t in ipairs({ 0x40, 0x42, 0x44, 0x46 }) do hush.assert(seen.head[t], string.format("head tile $%02X was drawn", t)) end
  for _, t in ipairs({ 0x48, 0x4A, 0x4C, 0x4E, 0x60, 0x62, 0x64, 0x66 }) do hush.assert(seen.body[t], string.format("body tile $%02X was drawn", t)) end
  hush.assert(seen.lantern[0x68] and seen.lantern[0x69], "both lantern frames were drawn")
  -- flips: side-right all H flipped, side-left never; down / up only on the 2nd step
  hush.assert(seen.flip["right:0:40"] and seen.flip["left:0:00"], "side body: right = H flip, left = none")
  hush.assert(not seen.flip["left:0:40"] and not seen.flip["right:0:00"] and not seen.flip["left:1:40"], "no wrong side flips")
  hush.assert(seen.flip["down:3:40"] and seen.flip["up:3:40"] and seen.flip["down:0:00"], "front/back steps flip on the 4th phase only")
  hush.assert(not seen.flip["down:1:40"], "no flip on the first step")

  -- 3. the allocation: 5 OAM entries per guard instead of 9
  for _, s in ipairs(g) do hush.assert_eq(bot.peek(0x7E0E40 + s) & 0x1F, 4, "slot " .. s .. ": OAM allocation = 5 entries") end
  hush.assert(seen.alloc[4] and not seen.alloc[8], "only 5-entry guards were drawn")

  -- 4. lantern flicker: frame 0 / 1 alternate every ~12 frames for a standing guard (state 0, still)
  for k, s in ipairs(g) do bot.poke(0x7E0D80 + s, 0); bot.poke(0x7E0DE0 + s, 2) end
  local s0 = g[1]
  local runs, cur, len = {}, nil, 0
  local lt = {}
  local ref
  ref = emu.addMemoryCallback(function()
    local st = emu.getState()
    if (st["cpu.x"] & 0xFF) == s0 then lt[#lt + 1] = read_entry(1).tile end
  end, emu.callbackType.exec, sym("Hush_GuardAI") + 4, sym("Hush_GuardAI") + 4)
  for _, s in ipairs(g) do bot.poke(0x7E0EE0 + s, 60) end
  for f = 1, 90 do
    for _, s in ipairs(g) do bot.poke(0x7E0EE0 + s, 60); bot.poke(0x7E0D80 + s, 0) end
    hush.wait(1)
  end
  emu.removeMemoryCallback(ref, emu.callbackType.exec, sym("Hush_GuardAI") + 4, sym("Hush_GuardAI") + 4)
  for _, t in ipairs(lt) do
    if t == cur then len = len + 1 else if cur then runs[#runs + 1] = len end cur, len = t, 1 end
  end
  hush.assert(#runs >= 4, "lantern flickered at least 4 times in 90 frames, runs: " .. #runs)
  for i = 2, #runs do hush.assert(runs[i] >= 11 and runs[i] <= 13, "lantern frame lasts 12 frames, got " .. runs[i]) end

  -- 5. culling window: every part inside the screen is drawn, a guard outside the window is hidden entirely
  hush.assert(not fail_first, "before the window test: " .. tostring(fail_first))
  local ex = word(0xE2)
  local ey = word(0xE8)
  local function place(s, x0, y0)
    local ax, ay = ex + x0, ey + y0
    bot.poke(0x7E0D10 + s, ax & 0xFF); bot.poke(0x7E0D30 + s, (ax >> 8) & 0xFF)
    bot.poke(0x7E0D00 + s, ay & 0xFF); bot.poke(0x7E0D20 + s, (ay >> 8) & 0xFF)
  end
  local function probe_at(x0, y0)
    local n0 = #calls
    for _, s in ipairs(g) do bot.poke(0x7E0D80 + s, 3); bot.poke(0x7E0DF0 + s, 250); bot.poke(0x7E0D90 + s, 5) end
    place(g[1], x0, y0)
    hush.wait(1)
    place(g[1], x0, y0)
    local pre = seen.hidden
    hush.wait(1)
    return seen.hidden - pre
  end
  local cases = { { 8, 100, false }, { 231, 100, false }, { 100, 24, false }, { 100, 199, false },
                  { 7, 100, true }, { 232, 100, true }, { 100, 23, true }, { 100, 200, true }, { 2, 2, true } }
  for _, c in ipairs(cases) do
    local before = #calls
    local h = probe_at(c[1], c[2])
    hush.assert(not fail_first, string.format("window case (%d,%d): %s", c[1], c[2], tostring(fail_first)))
    hush.assert(c[3] == (h > 0), string.format("guard origin (%d,%d): %s", c[1], c[2], c[3] and "must be hidden" or "must be drawn"))
  end

  hush.pass(string.format("%d guard draws checked against the contract, %d outside the window", seen.drawn + seen.hidden, seen.hidden))
end)
