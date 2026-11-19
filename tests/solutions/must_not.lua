-- Solutions (QA): the `must_not` lines of the room specs (design/rooms/*.yaml) as tests. Each case enters a room of the real ROM
-- (build/hush.sfc) and does the WRONG thing with real button presses; the game must punish it as the spec says (guard Suspicious '?',
-- Alert '!', caught -> instant restart, knife useless, no free ride). One cold boot, rooms entered with the debug jump.
-- Output: one `MUST_NOT:` line per case; any case that does NOT end as specified fails the test.
-- @timeout 400
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local S = { UNAWARE = 0, SUSPICIOUS = 1, ALERT = 2, ASLEEP = 3 }
local failed, ncases = {}, 0

local function room_by_id(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no room " .. id })
end

-- Link pixel position of cell (cx, cy) (plus pixel offset)
local function cell(r, cx, cy, dx, dy)
  local m = bot.rooms()
  return r.base_x + m.win_x + 16 * cx + (dx or 0), r.base_y + m.win_y + 16 * cy - 8 + (dy or 0)
end

local function aware_max(r)
  local a = 0
  for k = 0, #r.guards - 1 do
    local v = hush.read("spr_aware", k)
    if v ~= S.ASLEEP and v > a then a = v end
  end
  return a
end

-- hold buttons n frames; returns the first frame (1-based) on which `pred()` was true, else nil
local function hold_until(btns, n, pred)
  for f = 1, n do
    hush.hold(btns, 1)
    if pred() then return f end
  end
  return nil
end

-- walk (closed loop) to Link position (x, y), stopping early when pred() holds; returns the frame count when pred held, else nil
local function walk_until(x, y, max, pred)
  for f = 1, max do
    local lx, ly = hush.read("link_x"), hush.read("link_y")
    local dx, dy = x - lx, y - ly
    if math.abs(dx) <= 1 and math.abs(dy) <= 1 then return nil end
    local b = {}
    if math.abs(dx) > 1 then b[#b + 1] = dx > 0 and "right" or "left" elseif math.abs(dy) > 1 then b[#b + 1] = dy > 0 and "down" or "up" end
    hush.hold(b, 1)
    if pred() then return f end
  end
  return nil
end

local function caught_now() return bot.peek(0x7EC902) ~= 0 or bot.peek(0x7EC903) ~= 0 end

local function case(name, body)
  ncases = ncases + 1
  local ok, err = pcall(body)
  local msg
  if ok then msg = "PASS" else
    msg = "FAIL " .. (type(err) == "table" and err.hush_fail or tostring(err))
    failed[#failed + 1] = name .. ": " .. msg
  end
  print("MUST_NOT: " .. name .. " " .. msg)
end

local S0
local function enter(id)
  local idx, r = room_by_id(id)
  hush.restore(S0)                      -- every case starts from the post-new-game state
  bot.jump_to_room_synced(idx)
  return r
end

hush.test("must_not: the spec's forbidden moves are punished", function()
  bot.start_new_game()
  S0 = hush.snapshot()

  case("r01 cross in front of the guard (7,3)/(8,3)/(9,3) -> Suspicious", function()
    local r = enter("r01")
    -- the safe route up to the gap, then straight at the exit along row 3 (the guard's wedge)
    for _, c in ipairs({ { 13, 8 }, { 10, 8 }, { 10, 3 }, { 7, 3 } }) do
      local x, y = cell(r, c[1], c[2])
      local f = walk_until(x, y, 400, function() return aware_max(r) >= S.SUSPICIOUS end)
      if f then return end
    end
    hush.assert(false, "walked in front of the guard and was never noticed")
  end)

  case("r03 walking on past the guard instead of the knife -> caught", function()
    local r = enter("r03")
    local x, y = cell(r, 12, 4)
    local f = walk_until(x, y, 400, caught_now)
    hush.assert(f ~= nil, "walked through the guard without being caught")
  end)

  case("r05 standing in the open at (8,9) -> Suspicious then Alert (1 s)", function()
    local r = enter("r05")
    local x, y = cell(r, 1, 9)
    walk_until(x, y, 200, function() return false end)
    x, y = cell(r, 8, 9, 3, 0)               -- 3 px into the cell: 77 px from the guard (his range is 80)
    walk_until(x, y, 400, function() return false end)
    local f = hold_until({}, 12, function() return aware_max(r) >= S.SUSPICIOUS end)   -- he looks every other frame
    hush.assert(f ~= nil, "no '?' at (8,9)")
    hush.assert_eq(hush.read("spr_aware", 0), S.SUSPICIOUS, "first only suspicious")
    local f2 = hold_until({}, 150, function() return hush.read("spr_aware", 0) == S.ALERT end)
    hush.assert(f2 ~= nil, "he never turned Alert although Link stood in the open")
    hush.assert(f2 >= 50 and f2 <= 100, "alert after " .. f2 .. " frames, spec says about 1 s")
  end)

  case("r05 the knife does nothing to a Suspicious guard", function()
    local r = enter("r05")
    local gx, gy = hush.sprite(0).x, hush.sprite(0).y
    local x, y = cell(r, 1, 9)
    walk_until(x, y, 200, function() return false end)
    x, y = cell(r, 8, 9, 3, 0)               -- 3 px into the cell: 77 px from the guard (his range is 80)
    walk_until(x, y, 400, function() return false end)
    hold_until({}, 12, function() return aware_max(r) >= S.SUSPICIOUS end)
    hush.assert_eq(hush.read("spr_aware", 0), S.SUSPICIOUS, "suspicious")
    bot.teleport(gx - 26, gy - 8)           -- 26 px in front of him: inside the sword's reach
    bot.poke(0x7E002F, 6)
    hush.hold({ "b" }, 3)
    hush.wait(15)
    hush.assert_eq(bot.peek(0x7E0DD0), 9, "the knife must not kill a Suspicious / Alert guard")
  end)

  case("r07 walking up the corridor without darts: seen from (1,10) -> Suspicious", function()
    local r = enter("r07")
    local x, y = cell(r, 1, 9)
    local f = walk_until(x, y, 400, function() return aware_max(r) >= S.SUSPICIOUS end)
    hush.assert(f ~= nil, "walked 3 cells up the corridor in his cone unnoticed")
  end)

  case("r10 walking east to meet the guard without ink -> caught", function()
    local r = enter("r10")
    local x, y = cell(r, 14, 9)
    local f = walk_until(x, y, 900, caught_now)
    hush.assert(f ~= nil, "met the patrol in the corridor without ink and was not caught")
  end)

  case("r10 ink pot thrown facing up does not protect the corridor", function()
    local r = enter("r10")
    -- select the pots (HUD slot 4) the way the recorder does: START, right until the cursor is on them, START
    hush.press({ "start" }, 2, 0)
    for _ = 1, 60 do hush.wait(1); if bot.peek(0x7E0200) == 4 then break end end
    for _ = 1, 8 do if bot.peek(0x7E0202) == 4 then break end; hush.press({ "right" }, 2, 6) end
    hush.press({ "start" }, 2, 0)
    for _ = 1, 80 do if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then break end; hush.wait(1) end
    hush.wait(2)
    hush.assert_eq(bot.peek(0x7E0303), 1, "bombs equipped")
    hush.press({ "up" }, 1, 3)           -- a wall above: Link turns without moving
    hush.press({ "y" }, 3, 2)
    local x, y = cell(r, 14, 9)
    local f = walk_until(x, y, 900, caught_now)
    hush.assert(f ~= nil, "a pot thrown against the north wall must not hide Link from the patrol")
  end)

  case("r12 standing east of col 4 before the guards sleep -> Suspicious (8 cells, lit)", function()
    local r = enter("r12")
    local x, y = cell(r, 6, 7)
    local f = walk_until(x, y, 400, function() return aware_max(r) >= S.SUSPICIOUS end)
    hush.assert(f ~= nil, "walked in front of the three lit guards unnoticed")
  end)

  case("r13 standing in the guard's lane (3,7) -> noticed", function()
    local r = enter("r13")
    local x, y = cell(r, 3, 12)
    walk_until(x, y, 200, function() return false end)
    x, y = cell(r, 3, 7)
    local f = walk_until(x, y, 400, function() return aware_max(r) >= S.SUSPICIOUS or caught_now() end)
    if not f then f = hold_until({}, 700, function() return aware_max(r) >= S.SUSPICIOUS or caught_now() end) end
    hush.assert(f ~= nil, "stood in the east-west lane and was never noticed")
  end)

  print(string.format("MUST_NOT: summary %d cases, %d failed", ncases, #failed))
  if #failed > 0 then hush.fail(table.concat(failed, "; ")) end
  hush.pass("every forbidden move was punished")
end)
