-- Smoke / QA bug hunt (mustnot2): the adversarial must_nots. tests/solutions/must_not.lua covers the spec's own `must_not` lines for 9 rooms;
-- this file goes after the shortcuts a player (or the engine's geometry) could open, on the real ROM (build/hush.sfc), real rooms:
--   K  the knife must not kill a guard through a wall  (every still / patrol-path guard cell that has exactly one wall cell between it and
--      a floor cell Link can reach, computed from the grids; Link is teleported flush against the wall, faces it, swings)
--   D  a dart must not put a guard to sleep through a wall (same geometry), and must still hit through an open door (r08)
--   P  a dart must not pass a pillar; the pillar does not move when Link pushes it with A / the d-pad
--   S  a sleeping guard blocks a 1-wide corridor for good (diagonals and pushing do not get Link past, the knife does kill him) (r07)
--   H  hiding spots and sight lines named by the specs: "standing here must NOT get you seen" (600+ frames) / "must get you Suspicious"
--   I  ink: a pot is useless until it has opened (157 frames), the cloud lapses after 300 frames and then the guard sees Link
--   E  exits: standing on a floor cell next to an exit cell does not leave the room; the exit cell itself does (all 21 rooms)
--   T  tools are gated by the room: no bow / pots in r01 even when the slot is forced
-- One `MUST_NOT2:` line per case. KNOWN (top of the file) maps a case family to the bug id of docs/bugs.md: its failures are reported as
-- XFAIL (never silently skipped); a KNOWN family with NO failing case is an XPASS and fails the test, so the entry gets removed when the
-- bug is fixed. Any other failing case fails the test.
-- @timeout 420
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

-- family -> bug id (docs/bugs.md)
local KNOWN = {
  -- (K = "B-003" removed: fixed by E7, the knife now needs a clear tile line of sight)
}

local S = { UNAWARE = 0, SUSPICIOUS = 1, ALERT = 2, ASLEEP = 3 }
local results, fam_fail, fam_n = {}, {}, {}
local DIRS = { { 1, 0, 6 }, { -1, 0, 4 }, { 0, 1, 2 }, { 0, -1, 0 } }   -- dx, dy, Link's facing code ($2F: 0 up, 2 down, 4 left, 6 right)

local m, S0
local snaps = {}

local function room_by_id(id)
  for i, r in ipairs(m.rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no room " .. id })
end

-- Enter a room (cached in-memory snapshot of the freshly loaded room: every case of a room starts from the identical state).
local function enter(id)
  local idx, r = room_by_id(id)
  if not snaps[id] then
    hush.restore(S0)
    bot.jump_to_room_synced(idx)
    hush.wait(3)
    snaps[id] = hush.snapshot()
  else
    hush.restore(snaps[id])
  end
  return r, idx
end

local function cellpx(r, cx, cy, dx, dy) return r.base_x + m.win_x + 16 * cx + (dx or 0), r.base_y + m.win_y + 16 * cy - 8 + (dy or 0) end
local function guard_cell(r, g) return (g.x - r.base_x - m.win_x) // 16, (g.y - r.base_y - m.win_y) // 16 end
local function at(r, cx, cy)
  if cy < 0 or cy >= #r.grid or cx < 0 or cx >= 16 then return "#" end
  return r.grid[cy + 1]:sub(cx + 1, cx + 1)
end
local function solid(r, cx, cy) local c = at(r, cx, cy); return c == "#" or c == "p" or c == "O" or c == "W" end
local function tele(r, cx, cy, dx, dy) local x, y = cellpx(r, cx, cy, dx, dy); bot.teleport(x, y) end
local function face(code) bot.poke(0x7E002F, code) end
local function alive(slot) return bot.peek(0x7E0DD0 + slot) == 9 end
local function aware(slot) return hush.read("spr_aware", slot) end
local function put_guard(slot, x, y)
  bot.poke(0x7E0D10 + slot, x & 0xFF); bot.poke(0x7E0D30 + slot, x >> 8)
  bot.poke(0x7E0D00 + slot, y & 0xFF); bot.poke(0x7E0D20 + slot, y >> 8)
  bot.poke(0x7E0D40 + slot, 0); bot.poke(0x7E0D50 + slot, 0)
end
local function give_bow() bot.poke(0x7EF340, 2); bot.poke(0x7EF377, 8); bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3) end

local function aware_max(r)
  local a = 0
  for k = 0, #r.guards - 1 do
    local v = aware(k)
    if v ~= S.ASLEEP and v > a then a = v end
  end
  return a
end
local function caught_now() return bot.peek(0x7EC902) ~= 0 or bot.peek(0x7EC903) ~= 0 end

-- run `body` as a case of family `fam`; PASS / XFAIL (family or case listed as known) / FAIL. A case with its own `bug` id that passes
-- is an XPASS: it fails the test so the entry gets removed.
local function case(fam, name, body, bug)
  fam_n[fam] = (fam_n[fam] or 0) + 1
  local ok, err = pcall(body)
  local msg = ok and "PASS" or ("FAIL " .. (type(err) == "table" and err.hush_fail or tostring(err)))
  local known = bug or KNOWN[fam]
  if not ok then
    fam_fail[fam] = (fam_fail[fam] or 0) + 1
    if not known then results[#results + 1] = fam .. " " .. name .. ": " .. msg end
  elseif bug then
    results[#results + 1] = fam .. " " .. name .. ": listed as known (" .. bug .. ") but passes: remove the entry"
    msg = "XPASS " .. msg
  end
  print(string.format("MUST_NOT: mn2 %-3s %-58s %s%s", fam, name, (not ok and known) and ("XFAIL(" .. known .. ") ") or "", msg))
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Geometry: (guard cell, wall cell, Link cell) in a straight line, the Link cell reachable from S (4-connected, guards ignored)
-- ---------------------------------------------------------------------------------------------------------------------------------
local function reachable(r)
  local sx, sy
  for y = 0, 13 do local c = r.grid[y + 1]:find("S", 1, true); if c then sx, sy = c - 1, y end end
  local seen, q = { [sy * 16 + sx] = true }, { { sx, sy } }
  while #q > 0 do
    local c = table.remove(q)
    for _, d in ipairs(DIRS) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      if not solid(r, nx, ny) and not seen[ny * 16 + nx] then seen[ny * 16 + nx] = true; q[#q + 1] = { nx, ny } end
    end
  end
  return seen
end

local function candidates(r)
  local seen, out = reachable(r), {}
  for slot, g in ipairs(r.guards) do
    local gx, gy = guard_cell(r, g)
    local cells = { { gx, gy } }
    if g.move == "patrol" then
      local d = ({ left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } })[g.facing]
      for _, s in ipairs({ 1, -1 }) do
        local k = 1
        while not solid(r, gx + s * d[1] * k, gy + s * d[2] * k) do cells[#cells + 1] = { gx + s * d[1] * k, gy + s * d[2] * k }; k = k + 1 end
      end
    end
    for _, c in ipairs(cells) do
      for _, d in ipairs(DIRS) do
        local wx, wy, lx, ly = c[1] + d[1], c[2] + d[2], c[1] + 2 * d[1], c[2] + 2 * d[2]
        if solid(r, wx, wy) and not solid(r, lx, ly) and seen[ly * 16 + lx] then
          -- Link at (lx, ly) faces the wall: the opposite direction of d
          out[#out + 1] = { slot = slot - 1, id = g.id, g = c, l = { lx, ly }, face = ({ [6] = 4, [4] = 6, [2] = 0, [0] = 2 })[d[3]], moved = (c[1] ~= gx or c[2] ~= gy), wall = { wx, wy } }
        end
      end
    end
  end
  return out
end

-- pick up to n candidates per room, spread over guards and directions
local function pick(list, n)
  local out, used = {}, {}
  for _, c in ipairs(list) do
    local key = c.id .. ":" .. c.face
    if not used[key] and #out < n then used[key] = true; out[#out + 1] = c end
  end
  return out
end

local function knife_trial(r, c)
  enter(r.id)
  if c.moved then put_guard(c.slot, cellpx(r, c.g[1], c.g[2], 0, 8)) end
  tele(r, c.l[1], c.l[2]); face(c.face)
  hush.wait(2)
  hush.assert(alive(c.slot) and aware(c.slot) == S.UNAWARE, "set-up: the guard is not unaware (" .. aware(c.slot) .. ")")
  hush.hold({ "b" }, 3)
  hush.wait(18)
  hush.assert(alive(c.slot), string.format("the knife killed guard %s at (%d,%d) through the wall at (%d,%d) from (%d,%d)",
    c.id, c.g[1], c.g[2], c.wall[1], c.wall[2], c.l[1], c.l[2]))
end

local function dart_trial(r, c)
  enter(r.id)
  if c.moved then put_guard(c.slot, cellpx(r, c.g[1], c.g[2], 0, 8)) end
  tele(r, c.l[1], c.l[2]); face(c.face); give_bow()
  hush.wait(2)
  hush.assert(alive(c.slot) and aware(c.slot) == S.UNAWARE, "set-up: the guard is not unaware (" .. aware(c.slot) .. ")")
  hush.hold({ "y" }, 3)
  hush.wait(40)
  hush.assert(aware(c.slot) ~= S.ASLEEP, string.format("the dart put guard %s to sleep through the wall at (%d,%d)", c.id, c.wall[1], c.wall[2]))
end

hush.test("mustnot2: shortcuts and adversarial moves are blocked", function()
  m = bot.rooms()
  bot.start_new_game()
  S0 = hush.snapshot()

  -- K / D: weapons through one-cell walls
  for _, r in ipairs(m.rooms) do
    for _, c in ipairs(pick(candidates(r), 2)) do
      case("K", string.format("%s knife: %s (%d,%d) <- Link (%d,%d)", r.id, c.id, c.g[1], c.g[2], c.l[1], c.l[2]), function() knife_trial(r, c) end)
    end
  end
  for _, rid in ipairs({ "r02", "r11", "r13", "r15", "r17", "r19", "r20", "final" }) do
    local _, r = room_by_id(rid)
    for _, c in ipairs(pick(candidates(r), 1)) do
      case("D", string.format("%s dart: %s (%d,%d) <- Link (%d,%d)", r.id, c.id, c.g[1], c.g[2], c.l[1], c.l[2]), function() dart_trial(r, c) end)
    end
  end

  -- D: the positive control: through the open door of r08 the dart hits guard a (12,7) from (6,7)
  case("D", "r08 dart through the open door hits guard a", function()
    local r = enter("r08")
    tele(r, 6, 7); face(6); give_bow()
    hush.wait(2)
    local slot
    for k, g in ipairs(r.guards) do if g.id == "a" then slot = k - 1 end end
    hush.assert(aware(slot) == S.UNAWARE, "set-up: guard a is not unaware")
    hush.hold({ "y" }, 3)
    hush.wait(60)
    hush.assert_eq(aware(slot), S.ASLEEP, "the dart through the open door must put a to sleep")
  end)

  -- P: a pillar stops darts and does not move
  case("P", "r05 dart from behind the pillar line does not reach a guard behind it", function()
    local r = enter("r05")
    put_guard(0, cellpx(r, 12, 9, 0, 8))          -- guard on the pillar's row (10,9), two cells east of it
    tele(r, 8, 9); face(6); give_bow()
    hush.wait(2)
    hush.assert(aware(0) == S.UNAWARE, "set-up: guard unaware")
    hush.hold({ "y" }, 3)
    hush.wait(60)
    hush.assert(aware(0) ~= S.ASLEEP, "the dart passed through the pillar")
  end)
  case("P", "r05 pushing the pillar (right + A for 200 frames) moves nothing", function()
    local r = enter("r05")
    local before = {}
    for i = 0, 64 * 64 - 1 do before[i] = bot.peek(0x7F2000 + i) end
    tele(r, 9, 9); face(6)
    hush.hold({ "right", "a" }, 200)
    local lx = hush.read("link_x")
    local px = r.base_x + m.win_x + 16 * 10
    hush.assert(lx <= px - 16 + 1, "Link walked into the pillar: x = " .. lx .. ", pillar starts at " .. px)
    for i = 0, 64 * 64 - 1 do
      if bot.peek(0x7F2000 + i) ~= before[i] then hush.assert(false, string.format("collision map changed at index %d", i)) end
    end
  end)

  -- S: the sleeper in the corridor of r07
  case("S", "r07 a sleeping guard blocks the corridor (up, diagonals, 400 frames of pushing)", function()
    local r = enter("r07")
    give_bow()
    tele(r, 1, 11); face(0)
    hush.wait(2)
    hush.hold({ "y" }, 3)
    local f
    for i = 1, 90 do hush.wait(1); if aware(0) == S.ASLEEP then f = i; break end end
    hush.assert(f ~= nil, "the dart did not put the guard to sleep")
    local gx, gy = hush.sprite(0).x, hush.sprite(0).y
    local best = hush.read("link_y")
    for i = 1, 400 do
      local b = { "up" }
      if i % 40 > 30 then b[#b + 1] = (i % 2 == 0) and "left" or "right" end
      hush.hold(b, 1)
      local ly = hush.read("link_y")
      if ly < best then best = ly end
      hush.assert(aware(0) == S.ASLEEP or i > 440, "he woke up early")
      if aware(0) ~= S.ASLEEP then break end
    end
    hush.assert(best + 16 >= gy, string.format("Link got past / into the sleeping guard: Link y %d, guard y %d", best, gy))
  end)
  case("S", "r07 the knife kills the sleeper (spec)", function()
    local r = enter("r07")
    give_bow()
    tele(r, 1, 11); face(0)
    hush.wait(2)
    hush.hold({ "y" }, 3)
    for _ = 1, 90 do hush.wait(1); if aware(0) == S.ASLEEP then break end end
    hush.assert_eq(aware(0), S.ASLEEP, "asleep")
    tele(r, 1, 7); face(0)
    hush.hold({ "up" }, 40)
    hush.hold({ "b" }, 3)
    hush.wait(20)
    hush.assert(not alive(0), "the knife did not kill the sleeping guard")
  end)

  -- H: hiding spots (NOT seen for N frames) and sight lines (seen within 20 frames); positions are the specs' (col, row) cells
  -- entries: room, col, row, frames, note [, guards that count (default all)] [, known bug id]
  local HIDE = {
    { "r02", 7, 11, 700, "waiting two cells south of the gap, the walls block the line" },
    { "r04", 4, 9, 900, "hiding in the pocket while the guard walks past" },
    { "r09", 8, 8, 700, "just below the gap" },
    { "r13", 1, 12, 900, "corner room" },
    { "r13", 3, 3, 900, "corner room" },
    { "r14", 1, 9, 700, "west of the lit hall" },
    { "r14", 7, 5, 500, "waiting for the smoke" },
    { "r15", 1, 12, 900, "south hall" },
    { "r15", 1, 6, 900, "middle corridor, west of col 6 (spec: not seen by the lane guards)", nil, "B-004" },
    { "r18", 3, 4, 600, "10 cells from the nearest guard" },
    { "r18", 3, 7, 600, "10 cells from the nearest guard" },
    { "r18", 3, 10, 600, "10 cells from the nearest guard" },
    { "r20", 8, 5, 500, "waiting for the smoke" },
    { "final", 8, 5, 500, "waiting for the smoke" },
    { "final", 3, 12, 700, "f's cone is vertical (only f counts: a at (2,11) is asleep in the real run)", { f = true } },
    { "r12", 3, 4, 500, "10 cells from the door guard (lit range 8)" },
    { "r12", 3, 7, 500, "10 cells from the door guard (lit range 8)" },
    { "r12", 3, 10, 500, "10 cells from the door guard (lit range 8)" },
  }
  for _, h in ipairs(HIDE) do
    case("H", string.format("%s hidden at (%d,%d) for %d frames: %s", h[1], h[2], h[3], h[4], h[5]), function()
      local r = enter(h[1])
      tele(r, h[2], h[3])
      for f = 1, h[4] do
        hush.hold({}, 1)
        local who, bad = {}, false
        for k = 0, #r.guards - 1 do
          local a = aware(k)
          who[#who + 1] = r.guards[k + 1].id .. "=" .. a
          if a ~= S.ASLEEP and a > 0 and (not h[6] or h[6][r.guards[k + 1].id]) then bad = true end
        end
        if bad or (caught_now() and not h[6]) then hush.assert(false, string.format("seen after %d frames (%s)", f, table.concat(who, " "))) end
      end
    end, h[7])
  end
  -- positive controls: the specs' sight lines (a guard that should see Link does so within 20 frames of Link standing there)
  local SEEN = {
    { "r12", 5, 4 }, { "r12", 5, 7 }, { "r12", 5, 10 }, { "r07", 1, 10 }, { "r08", 7, 7 }, { "r16", 7, 10 }, { "r18", 5, 4 }, { "r20", 5, 10 },
    { "final", 10, 11 },
  }
  for _, h in ipairs(SEEN) do
    case("H", string.format("%s seen at (%d,%d) within 20 frames", h[1], h[2], h[3]), function()
      local r = enter(h[1])
      tele(r, h[2], h[3])
      local f = nil
      for i = 1, 20 do hush.hold({}, 1); if aware_max(r) >= S.SUSPICIOUS or caught_now() then f = i; break end end
      hush.assert(f ~= nil, "standing there for 20 frames raised no awareness")
    end)
  end

  -- I: ink pots in r10 (corridor row 9, the guard patrols from the east end)
  local function pots(r)
    bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1)
    hush.wait(2)
  end
  case("I", "r10 a pot facing east is no cover before it has opened (157 frames)", function()
    local r = enter("r10")
    pots(r)
    hush.hold({ "right" }, 2); face(6)
    hush.hold({ "y" }, 3)
    local seen
    local t = 0
    while t < 150 and not seen do
      hush.hold({ "right" }, 1); t = t + 1
      if aware_max(r) >= S.SUSPICIOUS or caught_now() then seen = t end
    end
    hush.assert(seen ~= nil and seen < 150, "walked 150 frames towards the patrol with the pot still closed and was never noticed")
  end)
  case("I", "r10 the cloud lapses after 300 frames: standing in it ends in being seen", function()
    local r = enter("r10")
    pots(r)
    hush.hold({ "right" }, 2); face(6)
    -- put the pot at Link's feet position in the corridor, then wait in the cloud
    bot.teleport(r.base_x + m.win_x + 16 * 2, r.base_y + m.win_y + 16 * 9 - 8)
    hush.wait(2)
    face(6)
    hush.hold({ "y" }, 3)
    local ok_t
    for t = 1, 260 do
      hush.hold({}, 1)
      if bot.peek(0x7EC90C) + 256 * bot.peek(0x7EC90D) > 0 then ok_t = t; break end
    end
    hush.assert(ok_t ~= nil, "the cloud never opened")
    -- move into the cloud centre (the pot is ~14 px in front of Link)
    bot.walk_to(hush.read("link_x") + 14, hush.read("link_y"), 30, 1)
    local seen_in = nil
    local t = 0
    while bot.peek(0x7EC90C) + 256 * bot.peek(0x7EC90D) > 0 and t < 400 do
      hush.hold({}, 1); t = t + 1
      if caught_now() then seen_in = t; break end
    end
    -- after it lapses the guard must find Link within 300 frames (he patrols the whole corridor)
    local after = nil
    for i = 1, 400 do
      hush.hold({}, 1)
      if aware_max(r) >= S.SUSPICIOUS or caught_now() then after = i; break end
    end
    hush.assert(after ~= nil, "the cloud is gone and the patrol never noticed Link standing in the corridor (inside-cloud catch: " .. tostring(seen_in) .. ")")
  end)

  -- E: exit cells only. Link on a floor cell touching an X cell (centre of his box outside the exit rectangle) must not advance;
  -- teleported onto the X cell he must (the last room returns to the title: module 0)
  for i, r in ipairs(m.rooms) do
    local xs = {}
    for cy = 0, 13 do for cx = 0, 15 do if at(r, cx, cy) == "X" then xs[#xs + 1] = { cx, cy } end end end
    local adj
    for _, x in ipairs(xs) do
      for _, d in ipairs(DIRS) do
        local nx, ny = x[1] + d[1], x[2] + d[2]
        if not adj and not solid(r, nx, ny) and at(r, nx, ny) ~= "X" then adj = { nx, ny } end
      end
    end
    if adj then
      case("E", string.format("%s next to the exit at (%d,%d) does not advance", r.id, adj[1], adj[2]), function()
        enter(r.id)
        tele(r, adj[1], adj[2])
        hush.wait(30)
        hush.assert_eq(hush.read("hush_room"), i - 1, "left the room from a cell next to the exit")
        hush.assert_eq(hush.read("game_mode"), 0x07, "game module")
      end)
    end
    case("E", string.format("%s on the exit cell (%d,%d) advances", r.id, xs[1][1], xs[1][2]), function()
      enter(r.id)
      tele(r, xs[1][1], xs[1][2], 0, 0)
      local done = false
      for _ = 1, 400 do
        hush.wait(1)
        if (i < #m.rooms and hush.read("hush_room") == i) or (i == #m.rooms and (hush.read("game_mode") == 0x00 or hush.read("game_mode") == 0x13)) then done = true; break end
      end
      hush.assert(done, "standing on the exit cell did not leave the room within 400 frames")
    end)
  end

  -- T: SELECT is dead (B-002 fixed by E6): no save / quit dialog, no module change, no SRAM write
  case("T", "r01 SELECT does nothing (no dialog, no Save and Quit, no SRAM write)", function()
    enter("r01")
    local function sram()
      local n = 0
      for i = 0, 0x7FF do n = n + emu.read(i, emu.memType.snesSaveRam, false) end
      return n
    end
    local s0 = sram()
    for _ = 1, 3 do
      hush.hold({ "select" }, 4)
      hush.wait(40)
      hush.assert_eq(hush.read("game_mode"), 0x07, "SELECT changed the game module")
      hush.hold({ "down" }, 3); hush.hold({ "a" }, 3)
      hush.wait(30)
      hush.assert_eq(hush.read("game_mode"), 0x07, "SELECT, down, A left the game")
    end
    hush.wait(200)
    hush.assert_eq(hush.read("game_mode"), 0x07, "game module after 200 more frames")
    hush.assert_eq(sram(), s0, "SRAM was written")
  end)

  -- T: tools are gated by the room: r01 has neither darts nor pots even when the slot is forced
  case("T", "r01 forcing the bow / pots slot gives nothing", function()
    local r = enter("r01")
    hush.assert_eq(bot.peek(0x7EF340), 0, "no bow in r01")
    hush.assert_eq(bot.peek(0x7EF343), 0, "no pots in r01")
    bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1)
    hush.wait(2)
    hush.hold({ "y" }, 3)
    hush.wait(200)
    hush.assert_eq(bot.peek(0x7EC90C) + 256 * bot.peek(0x7EC90D), 0, "an ink cloud appeared in r01 without any pot")
    bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3)
    hush.hold({ "y" }, 3)
    hush.wait(30)
    local n = 0
    for i = 0, 9 do if bot.peek(0x7E0C4A + i) ~= 0 then n = n + 1 end end
    hush.assert_eq(n, 0, "an ancilla (arrow / pot) exists in r01 without the tool")
  end)

  -- ---- verdict -----------------------------------------------------------------------------------------------------------------
  local n_total = 0
  for f, n in pairs(fam_n) do n_total = n_total + n end
  for fam, bug in pairs(KNOWN) do
    if (fam_fail[fam] or 0) == 0 then
      results[#results + 1] = string.format("%s: listed as known (%s) but all %d cases pass: remove the KNOWN entry", fam, bug, fam_n[fam] or 0)
    end
    print(string.format("MUST_NOT: mn2 family %s known bug %s: %d of %d cases fail", fam, bug, fam_fail[fam] or 0, fam_n[fam] or 0))
  end
  print(string.format("MUST_NOT: mn2 summary %d cases, %d unexpected failure(s)", n_total, #results))
  if #results > 0 then hush.fail(table.concat(results, "; ")) end
  hush.pass(string.format("%d cases; failures only in known families", n_total))
end)
